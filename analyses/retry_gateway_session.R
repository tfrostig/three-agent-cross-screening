source("R/bootstrap.R")

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

preserve_first_pass <- function(run_dir) {
  output <- file.path(run_dir, "infrastructure-retries/first-pass")
  if (dir.exists(output)) stop("First-pass archive already exists; inspect before any further retry")
  ensure_dir(output)
  files <- file.path(run_dir, c("scores.csv", "global-scores.csv", "completion.json", "usage.csv",
                                 "planning.csv", "report.html", "power.png"))
  stopifnot(all(file.exists(files)), all(file.copy(files, output, overwrite = FALSE)))
}

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
