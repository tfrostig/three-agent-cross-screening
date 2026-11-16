#' Atomic state and immutable identities for resumable document experiments.

#' Publish a small checkpoint atomically in its destination directory.
#' @param value JSON-serializable controller metadata.
#' @param path Destination file.
doc_atomic <- function(value, path) {
  temporary <- paste0(path, ".partial")
  write_json(value, temporary)
  if (!file.rename(temporary, path)) stop("Cannot publish checkpoint")
}

#' Verify the atomic freeze commit marker and artifact hashes.
#' @param frozen Frozen source directory.
doc_committed <- function(frozen) {
  marker <- file.path(frozen, "complete.json")
  if (!file.exists(marker)) return(FALSE)
  stopifnot(read_json(marker)$frozen_sha256 == file_hash(safe_file(file.path(frozen, "frozen.json"), frozen)))
  doc_frozen(frozen)
  TRUE
}

#' Recover source state without starting a second model conversation.
#' @param base Source attempt directory.
#' @return pending, running, frozen or failed state record.
doc_source_state <- function(base) {
  path <- file.path(base, "checkpoint.json")
  if (doc_committed(file.path(base, "frozen"))) {
    state <- list(status = "frozen", recovered = TRUE)
    doc_atomic(state, path)
    return(state)
  }
  state <- if (file.exists(path)) read_json(path) else list(status = "pending")
  if (state$status == "frozen") stop("Frozen source is missing its commit marker")
  if (state$status == "running") {
    doc_interrupted_usage(base)
    state <- list(status = "failed", error = "Interrupted before atomic freeze; no new API budget allocated")
    doc_atomic(state, path)
  }
  state
}

#' Execute at most one paid/source attempt; committed designs are reused.
#' @param config Run configuration.
#' @param scenario Scenario metadata.
#' @param setting Source observations.
#' @param directory Scenario output directory.
#' @param source Source index.
#' @param offline Fixture mode.
doc_session <- function(config, scenario, setting, directory, source, offline) {
  base <- ensure_dir(file.path(directory, paste0("agent-", source)))
  state <- doc_source_state(base)
  if (state$status %in% c("frozen", "failed")) return(state$status == "frozen")
  doc_atomic(list(status = "running", started = timestamp()), file.path(base, "checkpoint.json"))
  tryCatch(doc_session_execute(config, scenario, setting, directory, source, offline),
    error = function(e) writeLines(conditionMessage(e), file.path(base, "controller-error.txt")))
  success <- doc_committed(file.path(base, "frozen"))
  doc_atomic(list(status = if (success) "frozen" else "failed", ended = timestamp()),
    file.path(base, "checkpoint.json"))
  success
}

#' Describe every byte that determines safe resume compatibility.
#' @param config Configuration with resolved image digest.
#' @param grid Requested scenarios.
#' @param offline Whether model calls are disabled.
doc_identity <- function(config, grid, offline) {
  list(config = config, scenarios = grid$id, offline = offline,
    source = source_fingerprint(), scientific_prompt = file_hash(file.path(project_root, config$scientific_prompt)),
    interfaces = object_hash(c(readLines(file.path(project_root, "agents/document.py")), readLines(file.path(project_root, "agents/document_state.py")))))
}

#' Initialize or validate a run without weakening identity checks.
#' @param config Configuration with immutable image ID.
#' @param options Execution options including resume and destination.
#' @param grid Requested scenario grid.
doc_initialize <- function(config, options, grid) {
  exists <- dir.exists(options$run_dir)
  if (exists && !options$resume) stop("Run exists; use --resume or a new directory")
  if (!exists && options$resume) stop("Cannot resume a missing run")
  run_dir <- ensure_dir(options$run_dir)
  identity <- doc_identity(config, grid, options$offline)
  path <- file.path(run_dir, "run.json")
  if (exists) {
    record <- read_json(path)
    stopifnot(record$identity_sha256 == object_hash(identity))
    stopifnot(record$preview_sha256 == file_hash(file.path(run_dir, "prompt-preview.md")))
  } else {
    doc_preview(file.path(run_dir, "prompt-preview.md"))
    doc_atomic(list(protocol = config$protocol, config = config, offline = options$offline,
      identity_sha256 = object_hash(identity), source_sha256 = identity$source,
      prompt_sha256 = identity$scientific_prompt, started = timestamp(),
      preview_sha256 = file_hash(file.path(run_dir, "prompt-preview.md"))), path)
  }
  run_dir
}

#' Refuse concurrent writers and recover only locks owned by dead local processes.
#' @param run_dir Controller run root.
#' @return Lock directory, to remove on controller exit.
doc_lock <- function(run_dir) {
  path <- file.path(run_dir, ".controller-lock")
  if (dir.exists(path)) {
    owner <- read_json(file.path(path, "owner.json"))
    alive <- tryCatch(isTRUE(tools::pskill(owner$pid, 0)), error = function(e) TRUE)
    if (owner$host != Sys.info()[["nodename"]] || alive) stop("Run already has a controller")
    unlink(path, recursive = TRUE)
  }
  if (!dir.create(path)) stop("Cannot acquire controller lock")
  write_json(list(pid = Sys.getpid(), host = Sys.info()[["nodename"]]), file.path(path, "owner.json"))
  path
}

#' Read an existing dataset only when its recorded byte hash remains valid.
#' @param path Existing private RDS file.
doc_existing_data <- function(path) {
  provenance <- read_json(sub(".rds$", "-provenance.json", path))
  stopifnot(provenance$sha256 == file_hash(path))
  setting <- readRDS(path)
  if (is.null(setting$error)) colnames(setting$effects) <- colnames(setting$observations[[1]]$exposed)
  setting
}

#' Seal dataset hashes before any source session and verify them on resume.
#' @param run_dir Run root.
#' @param ids Dataset identifiers.
doc_seal_data <- function(run_dir, ids) {
  paths <- file.path(run_dir, "private", paste0(ids, ".rds"))
  value <- as.list(setNames(vapply(paths, file_hash, character(1)), ids))
  path <- file.path(run_dir, "datasets.json")
  if (file.exists(path)) stopifnot(identical(read_json(path), value))
  else doc_atomic(value, path)
}

#' Reuse completed scenario scores only after every saved output verifies.
#' @param directory Scenario directory.
doc_scenario_checkpoint <- function(directory) {
  marker <- file.path(directory, "scenario-complete.json")
  if (!file.exists(marker)) return(NULL)
  record <- read_json(marker)
  for (name in names(record)) stopifnot(record[[name]] == file_hash(safe_file(file.path(directory, name), directory)))
  for (source in 1:3) doc_source_state(file.path(directory, paste0("agent-", source)))
  read_csv(file.path(directory, "scenario-summary.csv"))
}

#' Atomically commit scenario outputs and scores after evaluation.
#' @param directory Scenario directory.
#' @param scores Completed scenario summary table.
doc_commit_scenario <- function(directory, scores) {
  write_csv(scores, file.path(directory, "scenario-summary.csv"))
  files <- list.files(directory, recursive = TRUE, full.names = TRUE)
  files <- files[!file.info(files)$isdir & grepl("(csv|json|R|md)$", files) &
    !grepl("/work/|/input/|/audit/|scenario-complete.json$|checkpoint.json$", files)]
  relative <- substring(files, nchar(directory)+2)
  doc_atomic(as.list(setNames(vapply(files, file_hash, character(1)), relative)), file.path(directory, "scenario-complete.json"))
}

#' Import either regime from a hash-indexed document-protocol dataset snapshot.
#' @param config Current generator configuration.
#' @param row Dataset metadata.
#' @param path Destination private file.
#' @param index Fixed stream slot.
#' @param historical Source document run root.
doc_import_snapshot <- function(config, row, path, index, historical) {
  source <- file.path(historical, "private", paste0(row$data_id, ".rds"))
  prior <- read_json(file.path(historical, "run.json"))$config
  for (field in c("seed", "alpha", "delta", "tau_squared", "regimes", "max_n", "max_dataset_cells"))
    stopifnot(isTRUE(all.equal(prior[[field]], config[[field]], check.attributes = FALSE)))
  manifest <- read_csv(file.path(historical, "SHA256.csv"))
  expected <- manifest$sha256[manifest$path == paste0("private/", row$data_id, ".rds")]
  stopifnot(length(expected) == 1, file_hash(source) == expected)
  temporary <- paste0(path, ".partial")
  stopifnot(file.copy(source, temporary, overwrite = TRUE), file_hash(temporary) == expected)
  value <- list(origin = normalizePath(source), sha256 = expected, stream_index = index)
  doc_atomic(value, sub(".rds$", "-provenance.json", path))
  stopifnot(file.rename(temporary, path))
  setting <- doc_existing_data(path)
  if (is.null(setting$error)) {
    stopifnot(setting$m == row$m, setting$target == row$c,
      identical(smallest_sample(setting$effects, row$c, config$alpha, config$max_n)$n, setting$planning$n))
  }
  setting
}

#' Create pending records before the first live source attempt.
#' @param grid Requested scenarios.
#' @param settings Prepared datasets.
#' @param run_dir Run root.
doc_pending_sources <- function(grid, settings, run_dir) {
  for (i in seq_len(nrow(grid))) {
    if (!is.null(settings[[grid$data_id[i]]]$error)) next
    for (source in 1:3) {
      base <- ensure_dir(file.path(run_dir, "scenarios", grid$id[i], paste0("agent-", source)))
      path <- file.path(base, "checkpoint.json")
      if (!file.exists(path)) doc_atomic(list(status = "pending"), path)
    }
  }
}

#' Verify completed packages before a resume returns without recomputation.
#' @param run_dir Run root.
doc_package_valid <- function(run_dir) {
  path <- file.path(run_dir, "package-complete.json")
  if (!file.exists(path)) return(FALSE)
  marker <- read_json(path)
  stopifnot(marker$sha256 == file_hash(marker$zip), marker$share_sha256 == file_hash(marker$share),
    marker$manifest_sha256 == file_hash(file.path(run_dir, "SHA256.csv")))
  manifest <- read_csv(file.path(run_dir, "SHA256.csv"))
  for (i in seq_len(nrow(manifest))) stopifnot(manifest$sha256[i] ==
    file_hash(safe_file(file.path(run_dir, manifest$path[i]), run_dir)))
  TRUE
}

#' Prepare every stable dataset slot before any paid source session.
#' @param config Run configuration.
#' @param grid Requested scenarios.
#' @param run_dir Run root.
#' @param historical Optional data snapshot.
doc_prepare_data <- function(config, grid, run_dir, historical) {
  full <- doc_grid(config)
  ids <- c(paste0("dense_", setting_stream_ids(config)), paste0("sparse_", setting_stream_ids(config)))
  settings <- full[!duplicated(full$data_id), ]
  streams <- seed_streams(config$seed, 3*length(ids))
  data <- lapply(seq_len(nrow(settings)), function(i) doc_data(config, settings[i, ],
    match(settings$data_id[i], ids), streams, run_dir, historical))
  names(data) <- settings$data_id
  doc_seal_data(run_dir, names(data))
  Sys.chmod(file.path(run_dir, "private"), "0700")
  doc_pending_sources(grid, data, run_dir)
  write_csv(grid, file.path(run_dir, "scenarios.csv"))
  data
}

#' Retain a crash's known API attempts and tokens without inventing missing usage.
#' @param base Interrupted source directory.
doc_interrupted_usage <- function(base) {
  audit <- ensure_dir(file.path(base, "audit"))
  path <- file.path(audit, "session.json")
  if (file.exists(path)) return(invisible(NULL))
  attempt_file <- file.path(audit, "api-attempts.json")
  attempts <- if (file.exists(attempt_file)) read_json(attempt_file)$attempts else 0L
  messages_file <- file.path(audit, "messages.json")
  usage <- NULL
  if (file.exists(messages_file)) {
    messages <- tryCatch(jsonlite::read_json(messages_file), error = function(e) list())
    responses <- Filter(function(x) identical(x$kind, "response"), messages)
    usage <- list(input_tokens = sum(vapply(responses, function(x) x$usage$input_tokens %||% 0, numeric(1))),
      output_tokens = sum(vapply(responses, function(x) x$usage$output_tokens %||% 0, numeric(1))))
  }
  doc_atomic(list(status = "failed", error = "Interrupted; usage may be partial", usage = usage,
    physical_api_attempts = attempts), path)
}
