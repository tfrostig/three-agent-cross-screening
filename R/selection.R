#' Frozen-algorithm selection on pooled non-target observations, entirely in trusted R.

#' Pool only the two non-target observation pairs.
#' @param observations List of three exposed/control pairs.
#' @param target Held-out study index.
#' @return Exposed/control matrices with aligned columns and 2n rows per arm.
pool_non_target <- function(observations, target) {
  stopifnot(target %in% 1:3, length(observations) == 3L)
  other <- setdiff(1:3, target)
  ids <- colnames(observations[[other[1]]]$exposed)
  for (i in other) validate_matrices(observations[[i]]$exposed, observations[[i]]$unexposed)
  for (i in other) stopifnot(identical(colnames(observations[[i]]$exposed), ids))
  list(exposed = do.call(rbind, lapply(observations[other], `[[`, "exposed")),
    unexposed = do.call(rbind, lapply(observations[other], `[[`, "unexposed")))
}

#' Choose the most discoveries, breaking ties by smaller source index.
#' @param candidates Table containing source, status, and discoveries.
#' @return Selection record; failed candidates are excluded rather than scored zero.
choose_candidate <- function(candidates) {
  good <- candidates[candidates$status == "ok", , drop = FALSE]
  if (!nrow(good)) return(list(source = NA_integer_, status = "failed", tie = FALSE, degraded = TRUE))
  good <- good[order(-good$discoveries, good$source), , drop = FALSE]
  list(source = good$source[1], status = "ok", tie = sum(good$discoveries == good$discoveries[1]) > 1,
    degraded = nrow(good) < nrow(candidates))
}

#' Run one fixed analysis on a supplied pair and record reusable result integrity.
#' @param config Sandbox and testing-level configuration.
#' @param pair Observations for either pooled selection or held-out testing.
#' @param frozen Verified frozen design directory.
#' @param prefix Output file prefix identifying purpose, target, and source.
#' @return Result, hypotheses, artifact/result hashes, and cache identity.
execute_frozen_pair <- function(config, pair, frozen, prefix) {
  verify_frozen(frozen)
  record <- read_json(file.path(frozen, "frozen.json"))
  key <- object_hash(list(pair, record$hashes, config$alpha / 3, config$sandbox, prefix))
  csv <- paste0(prefix, "-result.csv")
  cache <- paste0(prefix, "-cache.json")
  if (file.exists(cache)) {
    stored <- read_json(cache)
    stopifnot(stored$key == key, stored$result_hash == file_hash(csv))
  } else {
    input <- ensure_dir(tempfile("held-out-input-"))
    on.exit(unlink(input, recursive = TRUE))
    write_pair(pair, input)
    request <- list(mode = "evaluate", input_dir = input, workspace = frozen,
      alpha = config$alpha / 3, sandbox = config$sandbox, result_file = csv,
      execution_seed = as.integer(strtoi(substr(key, 1, 7), 16)))
    execution <- execute_sandbox(request)
    write_json(execution, paste0(prefix, "-execution.json"))
    verify_frozen(frozen)
    if (execution$status != "ok") stop(execution$error %||% "Frozen analysis execution failed")
    write_json(list(key = key, result_hash = file_hash(csv), artifact_hashes = record$hashes), cache)
  }
  h <- read_hypothesis_table(file.path(frozen, "hypotheses.csv"))
  r <- read_result_table(csv)
  validate_hypotheses(h, colnames(pair$exposed))
  validate_result(r, h)
  verify_frozen(frozen)
  list(hypotheses = h, result = r, key = key, result_hash = file_hash(csv), hashes = record$hashes)
}

#' Evaluate a candidate without making any truth-based selection decisions.
#' @param config Testing and sandbox configuration.
#' @param pair Pooled non-target observations only.
#' @param directory Scenario directory.
#' @param source Candidate source index.
#' @param target Held-out index, used solely for filenames and routing.
#' @return Audit row with a unique-measurement count and directional-conflict count.
evaluate_candidate <- function(config, pair, directory, source, target) {
  prefix <- file.path(directory, "selection", paste0("target-", target, "-source-", source))
  frozen <- file.path(directory, paste0("agent-", source), "frozen")
  tryCatch({
    fit <- execute_frozen_pair(config, pair, frozen, prefix)
    ids <- fit$hypotheses$measurement_id[fit$hypotheses$hypothesis_id %in%
      fit$result$hypothesis_id[fit$result$reject]]
    data.frame(target = target, source = source, status = "ok", error = "",
      discoveries = length(unique(ids)), directional_conflicts = sum(table(ids) > 1L),
      artifact_hash = object_hash(fit$hashes), result_hash = fit$result_hash)
  }, error = function(e) data.frame(target = target, source = source, status = "failed",
    error = conditionMessage(e), discoveries = NA_integer_, directional_conflicts = NA_integer_,
    artifact_hash = "", result_hash = ""))
}

#' Reuse an identical historical held-out result after verifying its source snapshot.
#' @param config Destination configuration with optional historical snapshot.
#' @param scenario Scenario row.
#' @param source Source index.
#' @param target Held-out index.
#' @param prefix New evaluation prefix.
#' @return TRUE if copied, otherwise FALSE; only the archived cyclic route is available.
reuse_target_result <- function(config, scenario, source, target, prefix) {
  if (is.null(config$reuse) || target != source %% 3L + 1L) return(FALSE)
  relative <- file.path("scenarios", scenario$id, "evaluation", paste0("agent-", source, "-result.csv"))
  csv <- reuse_file(config, relative)
  execution <- reuse_file(config, sub("-result.csv$", "-execution.json", relative))
  if (is.null(csv) || is.null(execution) || read_json(execution)$status != "ok") return(FALSE)
  target_csv <- paste0(prefix, "-result.csv")
  ensure_dir(dirname(target_csv))
  if (!file.exists(target_csv)) stopifnot(file.copy(csv, target_csv, overwrite = FALSE))
  stopifnot(file_hash(csv) == file_hash(target_csv))
  write_json(list(origin = "historical_target", source_file = relative, result_hash = file_hash(csv)),
    paste0(prefix, "-reuse.json"))
  TRUE
}

#' Evaluate or reuse a held-out source/target pair and create ledger and score rows.
#' @param config Current execution configuration.
#' @param scenario Scenario row.
#' @param setting Trusted setting; effects are used only after analysis finishes.
#' @param directory Scenario directory.
#' @param source Selected or cyclic source index; NA denotes failed selection.
#' @param target Held-out study index.
#' @param method agent_pooled_select or agent_cycle.
#' @return List with a directional score and an evaluation-ledger row.
evaluate_selected_target <- function(config, scenario, setting, directory, source, target, method) {
  prefix <- file.path(directory, "evaluation", paste0("target-", target, "-source-", source))
  hypotheses_file <- file.path(paste0("agent-", source), "frozen/hypotheses.csv")
  result_file <- file.path("evaluation", paste0("target-", target, "-source-", source, "-result.csv"))
  started <- Sys.time()
  result <- tryCatch({
    if (is.na(source)) stop("No successful pooled candidate")
    frozen <- file.path(directory, paste0("agent-", source), "frozen")
    verify_frozen(frozen)
    pair <- setting$observations[[target]]
    reused <- reuse_target_result(config, scenario, source, target, prefix)
    if (!reused) execute_frozen_pair(config, pair, frozen, prefix)
    h <- read_hypothesis_table(file.path(directory, hypotheses_file))
    r <- read_result_table(file.path(directory, result_file))
    truth <- stats::setNames(setting$effects[target, ], colnames(pair$exposed))
    metrics <- score_claims(h, r, truth)
    verify_frozen(frozen)
    score_row(scenario, method, source, target, "ok", metrics = metrics,
      elapsed = as.numeric(difftime(Sys.time(), started, units = "secs")))
  }, error = function(e) score_row(scenario, method, source, target, "failed", conditionMessage(e)))
  ledger <- data.frame(method = method, source = source, target = target, status = result$status,
    hypotheses_file = hypotheses_file, result_file = result_file)
  list(score = result, ledger = ledger)
}

#' Evaluate full-family baselines and expose their outputs in the common ledger.
#' @param config Baseline configuration.
#' @param scenario Scenario row.
#' @param setting Trusted setting.
#' @param directory Scenario directory.
#' @return List of score data frame and ledger data frame.
selected_baselines <- function(config, scenario, setting, directory) {
  scores <- do.call(rbind, evaluate_scenario_baselines(config, scenario, setting,
    ensure_dir(file.path(directory, "evaluation"))))
  ledger <- data.frame(method = scores$method, source = scores$source, target = scores$target,
    status = scores$status,
    hypotheses_file = file.path("evaluation", paste0(scores$method, "-hypotheses.csv")),
    result_file = file.path("evaluation", paste0(scores$method, "-target-", scores$target, ".csv")))
  list(score = scores, ledger = ledger)
}

#' Run pooled selection for all targets and retain the cyclic comparison.
#' @param config Current configuration.
#' @param scenario Scenario row.
#' @param setting Trusted setting; truth is excluded from candidate evaluations.
#' @param directory Scenario directory with three completed source attempts.
#' @param designs Source attempt summaries, retained by the caller for audit.
#' @return Directional score rows; writes candidate, decision, and evaluation ledgers.
run_selected_scenario <- function(config, scenario, setting, directory, designs) {
  evaluations <- candidates <- decisions <- list()
  for (target in 1:3) {
    pair <- pool_non_target(setting$observations, target)
    rows <- do.call(rbind, lapply(setdiff(1:3, target), function(source)
      evaluate_candidate(config, pair, directory, source, target)))
    winner <- choose_candidate(rows)
    candidates[[target]] <- rows
    decisions[[target]] <- data.frame(target = target, selected_source = winner$source,
      status = winner$status, tie = winner$tie, degraded = winner$degraded,
      pooled_studies = paste(setdiff(1:3, target), collapse = "+"), alpha = config$alpha / 3)
    evaluations <- c(evaluations, list(evaluate_selected_target(config, scenario, setting,
      directory, winner$source, target, "agent_pooled_select")),
      list(evaluate_selected_target(config, scenario, setting, directory,
        if (target == 1L) 3L else target - 1L, target, "agent_cycle")))
    write_csv(do.call(rbind, candidates), file.path(directory, "selection-candidates.csv"))
    write_csv(do.call(rbind, decisions), file.path(directory, "selection-decisions.csv"))
  }
  evaluations <- c(evaluations, list(selected_baselines(config, scenario, setting, directory)))
  ledger <- do.call(rbind, lapply(evaluations, `[[`, "ledger"))
  write_csv(ledger, file.path(directory, "evaluation-ledger.csv"))
  do.call(rbind, lapply(evaluations, `[[`, "score"))
}
