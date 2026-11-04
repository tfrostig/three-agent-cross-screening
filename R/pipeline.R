#' R entry-point orchestration: generate once per data_id, freeze three source designs,
#'   transfer cyclically, score, and render.

#' Generate or reuse one trusted dataset per unique setting
#'
#' @param config Validated configuration list from load_config(), unless a SessionConfig is
#'   explicitly noted.
#' @param scenarios Scenario-grid data frame, optionally filtered to one setting.
#' @param run_dir Saved run directory containing metadata, scenarios, scores, and host-private
#'   inputs.
#' @return Data frame mapping data_id to private RDS paths. Matching criteria reuse
#'   observations; generation errors are stored without redrawing.
prepare_data <- function(config, scenarios, run_dir) {
  settings <- scenarios[!duplicated(scenarios$data_id), c("data_id", "m", "c")]
  all_settings <- setting_stream_ids(config)
  streams <- seed_streams(config$seed, 3L * length(all_settings))
  private <- ensure_dir(file.path(run_dir, "private"))
  Sys.chmod(private, "0700")
  records <- lapply(seq_len(nrow(settings)), function(i) {
    row <- settings[i, ]
    stream_index <- match(row$data_id, all_settings)
    path <- file.path(private, paste0(row$data_id, ".rds"))
    if (!file.exists(path)) {
      imported <- import_setting(config, row$data_id, path)
      if (!imported) {
        setting <- tryCatch(generate_setting(config, row$m, row$c,
                                           streams[(3L * stream_index - 2L):(3L * stream_index)]),
                          error = function(error) list(error = conditionMessage(error)))
        atomic_rds(setting, path)
      }
    }
    data.frame(data_id = row$data_id, path = path)
  }) |> data.table::rbindlist() |> as.data.frame()
  provenance <- records
  provenance$stream_index <- match(provenance$data_id, all_settings)
  provenance$sha256 <- vapply(provenance$path, file_hash, character(1))
  provenance$origin <- vapply(provenance$data_id, function(id) {
    if (is.null(reuse_file(config, file.path("private", paste0(id, ".rds"))))) "generated" else "imported"
  }, character(1))
  write_csv(provenance, file.path(run_dir, "data-provenance.csv"))
  records
}

#' Create a run record or enforce an identical resume signature
#'
#' @param config Validated configuration list from load_config(), unless a SessionConfig is
#'   explicitly noted.
#' @param run_dir Saved run directory containing metadata, scenarios, scores, and host-private
#'   inputs.
#' @param offline Logical; use deterministic fixture artifacts/provider instead of OpenAI.
#' @param resume Logical; permit an existing run only if its full identity matches.
#' @param image_id Resolved Docker image SHA-256 identifier.
#' @param scenario_ids Ordered character vector of scenario identifiers included in the run.
#' @return Absolute run path. Writes run.json and R-session.txt for a new run; refuses
#'   mismatched existing runs.
new_run <- function(config, run_dir, offline, resume, image_id, scenario_ids) {
  exists <- dir.exists(run_dir)
  if (exists && !resume) stop("Run directory exists; use --resume or choose a new directory")
  run_dir <- ensure_dir(run_dir)
  signature <- object_hash(list(config, offline, image_id, scenario_ids, source_fingerprint(),
                                reference_pack_record(config)))
  path <- file.path(run_dir, "run.json")
  if (exists) {
    old <- read_json(path)
    if (!identical(old$signature, signature)) stop("Run configuration or implementation changed")
    return(run_dir)
  }
  write_json(list(signature = signature, started_at = timestamp(),
                  mode = if (offline) "offline_fixture" else "live", image_id = image_id,
                  config = config, references = reference_pack_record(config),
                  r_version = R.version.string), path)
  writeLines(capture.output(utils::sessionInfo()), file.path(run_dir, "R-session.txt"))
  run_dir
}

#' Create a uniform success or failure row for scores.csv
#'
#' @param scenario One-row scenario record containing id, data_id, m, c, and criterion.
#' @param method Method ID used in score tables.
#' @param source Source subgroup index (1, 2, or 3).
#' @param target Target subgroup index, or NA for a failure without a target.
#' @param status Execution status, normally ok or failed.
#' @param error Error condition or failure message, as indicated by the caller.
#' @param metrics One-row score_claims() result, or NULL to preserve missing metrics.
#' @param elapsed Elapsed seconds, or NA when unavailable.
#' @return One-row data frame. Missing metrics remain NA rather than becoming zero
#'   discoveries.
score_row <- function(scenario, method, source, target, status, error = "", metrics = NULL, elapsed = NA_real_) {
  base <- data.frame(scenario = scenario$id, criterion = scenario$criterion, m = scenario$m,
                     c = scenario$c, method = method, source = source, target = target,
                     status = status, error = error, elapsed_seconds = elapsed)
  if (is.null(metrics)) metrics <- data.frame(selected = NA_integer_, rejected = NA_integer_,
    false = NA_integer_, correct_coordinates = NA_integer_, nonnull = NA_integer_,
    fdp = NA_real_, any_false = NA_integer_, power = NA_real_)
  cbind(base, metrics)
}

#' Apply a frozen source design to its independent target group
#'
#' @param config Validated configuration list from load_config(), unless a SessionConfig is
#'   explicitly noted.
#' @param scenario One-row scenario record containing id, data_id, m, c, and criterion.
#' @param setting Trusted generated setting including observations, effects, and planning
#'   metadata.
#' @param directory Filesystem directory holding the relevant inputs or outputs.
#' @param source Source subgroup index (1, 2, or 3).
#' @param output_dir Directory receiving target CSVs and execution metadata.
#' @return One score row after fresh-container execution; writes results and execution audit.
#'   Verifies artifact hashes before and after evaluation.
evaluate_agent <- function(config, scenario, setting, directory, source, output_dir) {
  target <- source %% 3L + 1L
  frozen <- file.path(directory, "frozen")
  started <- Sys.time()
  verify_frozen(frozen)
  input <- ensure_dir(tempfile("target-"))
  on.exit(unlink(input, recursive = TRUE))
  write_pair(setting$observations[[target]], input)
  result_file <- file.path(output_dir, paste0("agent-", source, "-result.csv"))
  request <- list(mode = "evaluate", input_dir = input, workspace = frozen,
                  alpha = config$alpha / 3, sandbox = config$sandbox,
                  execution_seed = as.integer(strtoi(substr(object_hash(list(scenario$id, source)), 1, 7), 16)),
                  result_file = result_file)
  execution <- execute_sandbox(request)
  write_json(execution, file.path(output_dir, paste0("agent-", source, "-execution.json")))
  verify_frozen(frozen)
  if (execution$status != "ok") stop(execution$error %||% "Target execution failed")
  hypotheses <- read_hypothesis_table(file.path(frozen, "hypotheses.csv"))
  effects <- stats::setNames(setting$effects[target, ], colnames(setting$observations[[target]]$exposed))
  metrics <- score_claims(hypotheses, read_result_table(result_file), effects)
  elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  score_row(scenario, "agent", source, target, "ok", metrics = metrics, elapsed = elapsed)
}

#' Evaluate one full-family baseline on one target group
#'
#' @param config Validated configuration list from load_config(), unless a SessionConfig is
#'   explicitly noted.
#' @param scenario One-row scenario record containing id, data_id, m, c, and criterion.
#' @param setting Trusted generated setting including observations, effects, and planning
#'   metadata.
#' @param target Target subgroup index (1, 2, or 3); observations are never pooled.
#' @param output_dir Directory receiving target CSVs and execution metadata.
#' @param known Logical; select oracle z instead of Welch.
#' @param fdr_method BH or BY; ignored for Holm FWER correction.
#' @return One success/failure score row; writes hypothesis and target-result CSVs without
#'   model calls.
evaluate_baseline <- function(config, scenario, setting, target, output_dir, known, fdr_method = "BY") {
  method <- if (known) "oracle_variance_z" else "welch"
  if (scenario$criterion == "FDR") method <- paste0(method, "_", tolower(fdr_method))
  started <- Sys.time()
  tryCatch({
    pair <- setting$observations[[target]]
    analysis <- baseline_analysis(pair$exposed, pair$unexposed, scenario$criterion,
                                  config$alpha / 3, known, fdr_method)
    write_csv(analysis$result, file.path(output_dir, paste0(method, "-target-", target, ".csv")))
    write_csv(analysis$hypotheses, file.path(output_dir, paste0(method, "-hypotheses.csv")))
    effects <- stats::setNames(setting$effects[target, ], colnames(pair$exposed))
    metrics <- score_claims(analysis$hypotheses, analysis$result, effects)
    elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
    score_row(scenario, method, NA_integer_, target, "ok", metrics = metrics, elapsed = elapsed)
  }, error = function(error) score_row(scenario, method, NA_integer_, target, "failed", conditionMessage(error)))
}

#' Enumerate target groups and configured baseline variants
#'
#' @param config Validated configuration list from load_config(), unless a SessionConfig is
#'   explicitly noted.
#' @param scenario One-row scenario record containing id, data_id, m, c, and criterion.
#' @param setting Trusted generated setting including observations, effects, and planning
#'   metadata.
#' @param output_dir Directory receiving target CSVs and execution metadata.
#' @return List of score rows for Welch and oracle z, including both configured FDR
#'   corrections.
evaluate_scenario_baselines <- function(config, scenario, setting, output_dir) {
  methods <- if (scenario$criterion == "FDR") config$baseline_fdr_methods %||% "BY" else "BY"
  variants <- expand.grid(target = seq_len(3L), known = c(FALSE, TRUE),
                           fdr_method = methods, stringsAsFactors = FALSE)
  lapply(seq_len(nrow(variants)), function(i) {
    variant <- variants[i, ]
    evaluate_baseline(config, scenario, setting, variant$target, output_dir,
                       variant$known, variant$fdr_method)
  })
}

#' Finish all three source sessions before target execution
#'
#' @param config Validated configuration list from load_config(), unless a SessionConfig is
#'   explicitly noted.
#' @param scenario One-row scenario record containing id, data_id, m, c, and criterion.
#' @param setting Trusted generated setting including observations, effects, and planning
#'   metadata.
#' @param scenario_dir Directory for this scenario's three source-agent sessions.
#' @param offline Logical; use deterministic fixture artifacts/provider instead of OpenAI.
#' @param image_id Resolved Docker image SHA-256 identifier.
#' @return List of three session summaries, retaining failures for later scoring.
scenario_designs <- function(config, scenario, setting, scenario_dir, offline, image_id) {
  lapply(seq_len(3L), function(source) {
    directory <- file.path(scenario_dir, paste0("agent-", source))
    message("Design ", scenario$id, " / agent ", source)
    tryCatch(prepare_design(config, scenario, setting$observations[[source]], directory, source, offline, image_id),
             error = function(error) list(status = "failed", error = conditionMessage(error)))
  })
}

#' Execute one complete freeze-then-transfer cycle
#'
#' @param config Validated configuration list from load_config(), unless a SessionConfig is
#'   explicitly noted.
#' @param scenario One-row scenario record containing id, data_id, m, c, and criterion.
#' @param setting Trusted generated setting including observations, effects, and planning
#'   metadata.
#' @param run_dir Saved run directory containing metadata, scenarios, scores, and host-private
#'   inputs.
#' @param offline Logical; use deterministic fixture artifacts/provider instead of OpenAI.
#' @param image_id Resolved Docker image SHA-256 identifier.
#' @return Score data frame for all agents and baselines; records generation/design/evaluation
#'   failures explicitly.
run_scenario <- function(config, scenario, setting, run_dir, offline, image_id) {
  scenario_dir <- ensure_dir(file.path(run_dir, "scenarios", scenario$id))
  output_dir <- ensure_dir(file.path(scenario_dir, "evaluation"))
  if (!is.null(setting$error)) {
    return(score_row(scenario, "generation", NA_integer_, NA_integer_, "failed", setting$error))
  }
  designs <- scenario_designs(config, scenario, setting, scenario_dir, offline, image_id)
  write_json(designs, file.path(scenario_dir, "design-status.json"))
  if (identical(config$aggregation, "pooled_leave_one_out")) {
    return(run_selected_scenario(config, scenario, setting, scenario_dir, designs))
  }
  agent_scores <- lapply(seq_len(3L), function(source) {
    if (designs[[source]]$status != "ok") {
      return(score_row(scenario, "agent", source, source %% 3L + 1L, "failed",
                        designs[[source]]$error %||% "Design failed"))
    }
    tryCatch(evaluate_agent(config, scenario, setting, file.path(scenario_dir, paste0("agent-", source)),
                            source, output_dir), error = function(error) {
      score_row(scenario, "agent", source, source %% 3L + 1L, "failed", conditionMessage(error))
    })
  })
  baselines <- evaluate_scenario_baselines(config, scenario, setting, output_dir)
  do.call(rbind, c(agent_scores, baselines))
}

#' Coordinate the configured one-iteration experiment
#'
#' @param config Validated configuration list from load_config(), unless a SessionConfig is
#'   explicitly noted.
#' @param options List with offline, dry_run, resume, run_dir, and scenario CLI settings.
#' @return Run directory invisibly on success; writes datasets, designs, incremental scores
#'   and report. Stops after reporting if any evaluation failed.
run_pilot <- function(config, options) {
  require_packages(c("jsonlite", "yaml", "digest", "data.table", "processx", "ggplot2", "rmarkdown"))
  scenarios <- scenario_grid(config)
  if (!is.null(options$scenario)) scenarios <- scenarios[scenarios$id == options$scenario, , drop = FALSE]
  if (!nrow(scenarios)) stop("Unknown scenario")
  if (options$dry_run) {
    print_run_plan(scenarios, options$reuse_run)
    return(invisible(NULL))
  }
  if (!options$offline) validate_live_config(config)
  image_id <- docker_info(config$sandbox$image)
  config$sandbox$image <- image_id
  config$reference_digest <- reference_pack_digest(config)
  config$reuse <- prepare_reuse(config, options$reuse_run, options$offline)
  directory <- options$run_dir %||% file.path(config$results_directory,
    paste0(if (options$offline) "offline-" else "live-", format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC")))
  run_dir <- new_run(config, directory, options$offline, options$resume, image_id, scenarios$id)
  write_csv(scenarios, file.path(run_dir, "scenarios.csv"))
  settings <- prepare_data(config, scenarios, run_dir)
  summaries <- vector("list", nrow(scenarios))
  for (i in seq_len(nrow(scenarios))) {
    scenario <- scenarios[i, ]
    setting <- readRDS(settings$path[match(scenario$data_id, settings$data_id)])
    summaries[[i]] <- run_scenario(config, scenario, setting, run_dir, options$offline, image_id)
    write_csv(do.call(rbind, summaries[seq_len(i)]), file.path(run_dir, "scores.csv"))
  }
  scores <- do.call(rbind, summaries)
  write_run_summaries(scores, run_dir)
  write_json(list(completed_at = timestamp(), successful = sum(scores$status == "ok"),
                  failed = sum(scores$status != "ok")), file.path(run_dir, "completion.json"))
  render_pilot_report(run_dir)
  message("Results: ", run_dir)
  if (any(scores$status != "ok")) stop("Run contains failures; inspect scores.csv and report.html")
  invisible(run_dir)
}
