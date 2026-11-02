#' Historical, narrowly guarded HTTP 520 recovery. CLI: --run-dir DIR, --scenario ID, --source
#'   1|2|3. Can make live paid calls and update one failed result.

source("R/bootstrap.R")

#' Require the exact original implementation before a targeted gateway retry
#'
#' @param run_dir Saved run directory containing metadata, scenarios, scores, and host-private
#'   inputs.
#' @return Validated live-run configuration with image and reference identities; stops after
#'   any signature change.
gateway_retry_config <- function(run_dir) {
  run <- read_json(file.path(run_dir, "run.json"))
  stopifnot(run$mode == "live", file.exists(file.path(run_dir, "completion.json")))
  config <- load_config("config/pilot.yml")
  config$sandbox$image <- docker_info(config$sandbox$image)
  config$reference_digest <- reference_pack_digest(config)
  scenarios <- read_csv(file.path(run_dir, "scenarios.csv"))
  signature <- object_hash(list(config, FALSE, config$sandbox$image, scenarios$id,
                                source_fingerprint(), reference_pack_record(config)))
  if (!identical(signature, run$signature)) stop("Retry requires unchanged run configuration and implementation")
  config
}

#' Archive score tables and report before replacing a failed attempt
#'
#' @param run_dir Saved run directory containing metadata, scenarios, scores, and host-private
#'   inputs.
#' @return Creates infrastructure-retries/first-pass once; stops rather than replacing an
#'   existing archive.
preserve_first_pass <- function(run_dir) {
  output <- file.path(run_dir, "infrastructure-retries/first-pass")
  if (dir.exists(output)) stop("First-pass archive already exists; inspect before any further retry")
  ensure_dir(output)
  files <- file.path(run_dir, c("scores.csv", "global-scores.csv", "completion.json", "usage.csv",
                                 "planning.csv", "report.html", "power.png"))
  stopifnot(all(file.exists(files)), all(file.copy(files, output, overwrite = FALSE)))
}

#' Replace one failed score and rebuild recovery summaries
#'
#' @param run_dir Saved run directory containing metadata, scenarios, scores, and host-private
#'   inputs.
#' @param scenario One-row scenario record containing id, data_id, m, c, and criterion.
#' @param source Source subgroup index (1, 2, or 3).
#' @param result Recovered source-session summary from run_design().
#' @param score One updated per-target score row.
#' @param scores Per-target scores.csv data frame including method, status, and discovery
#'   metrics.
#' @param index Row index to replace in the scores table.
#' @return Updates design status, scores, completion metadata and report; preserves unrelated
#'   score rows.
publish_gateway_recovery <- function(run_dir, scenario, source, result, score, scores, index) {
  status_path <- file.path(run_dir, "scenarios", scenario$id, "design-status.json")
  statuses <- jsonlite::read_json(status_path, simplifyVector = FALSE)
  statuses[[source]] <- result
  write_json(statuses, status_path)
  scores[index, ] <- score
  write_csv(scores, file.path(run_dir, "scores.csv"))
  write_csv(global_scores(scores), file.path(run_dir, "global-scores.csv"))
  write_json(list(completed_at = timestamp(), successful = sum(scores$status == "ok"),
    failed = sum(scores$status != "ok"), infrastructure_retries = 1L), file.path(run_dir, "completion.json"))
  render_pilot_report(run_dir)
  message("Gateway recovery complete: ", scenario$id, " / agent ", source)
}

#' Recover the historical unfrozen HTTP 520 session under strict guards
#'
#' @param run_dir Saved run directory containing metadata, scenarios, scores, and host-private
#'   inputs.
#' @param scenario_id Stable scenario identifier such as fwer_m20_c20.
#' @param source Source subgroup index (1, 2, or 3).
#' @return Runs only one missing source design and its target evaluation; requires a matching
#'   archived failed audit. Not a general retry command.
retry_gateway_session <- function(run_dir, scenario_id, source) {
  run_dir <- normalizePath(run_dir, mustWork = TRUE)
  config <- gateway_retry_config(run_dir)
  stopifnot(source %in% seq_len(3L))
  directory <- file.path(run_dir, "scenarios", scenario_id, paste0("agent-", source))
  failure_path <- file.path(directory, "audit/session.json")
  failure <- read_json(failure_path)
  stopifnot(failure$status == "failed", grepl("status_code: 520", failure$error, fixed = TRUE),
            !dir.exists(file.path(directory, "frozen")))
  archive <- file.path(run_dir, "infrastructure-retries", scenario_id, paste0("agent-", source),
                       "attempt-1/audit/session.json")
  stopifnot(file.exists(archive), identical(file_hash(archive), file_hash(failure_path)))
  scores <- read_csv(file.path(run_dir, "scores.csv"))
  index <- which(scores$scenario == scenario_id & scores$method == "agent" & scores$source == source)
  stopifnot(length(index) == 1L, scores$status[index] == "failed")
  scenarios <- read_csv(file.path(run_dir, "scenarios.csv"))
  scenario <- scenarios[scenarios$id == scenario_id, ]
  stopifnot(nrow(scenario) == 1L)
  setting <- readRDS(file.path(run_dir, "private", paste0(scenario$data_id, ".rds")))
  preserve_first_pass(run_dir)
  result <- run_design(config, scenario, setting$observations[[source]], directory, FALSE, config$sandbox$image)
  if (result$status != "ok") stop("Infrastructure retry failed; its audit has been retained")
  score <- tryCatch(evaluate_agent(config, scenario, setting, directory, source,
    file.path(run_dir, "scenarios", scenario_id, "evaluation")), error = function(error) {
      score_row(scenario, "agent", source, source %% 3L + 1L, "failed", conditionMessage(error))
    })
  publish_gateway_recovery(run_dir, scenario, source, result, score, scores, index)
  if (score$status != "ok") stop("Recovered design failed target evaluation; the failure was recorded")
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  retry_gateway_session(cli_value(args, "--run-dir", "results/live-revised-20261101"),
    cli_value(args, "--scenario", "fwer_m20_c20"), as.integer(cli_value(args, "--source", "1")))
}
