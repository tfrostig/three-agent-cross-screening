#' Complete timed-out source sessions in a separate, explicitly derived run.
if (!exists("project_root")) source("R/bootstrap.R")

#' Copy regular controller-owned records without changing their bytes.
#' @param origin Original directory.
#' @param destination New directory.
completion_copy <- function(origin, destination) {
  files <- list.files(origin, recursive = TRUE, full.names = TRUE)
  files <- files[!file.info(files)$isdir]
  for (path in files) {
    relative <- substring(path, nchar(origin)+2)
    target <- file.path(destination, relative)
    ensure_dir(dirname(target))
    stopifnot(file.copy(safe_file(path, origin), target, overwrite = FALSE),
      file_hash(path) == file_hash(target))
  }
}

#' Import an accepted design or prepare one isolated timeout continuation.
#' @param previous Original source directory.
#' @param destination New source directory.
#' @param config New run configuration.
#' @param pair Only this source's observations.
completion_source <- function(previous, destination, config, pair) {
  if (doc_committed(file.path(previous, "frozen"))) {
    for (name in c("frozen", "audit"))
      completion_copy(file.path(previous, name), file.path(destination, name))
    doc_atomic(list(status = "frozen", imported_from = previous), file.path(destination, "checkpoint.json"))
    return(data.frame(previous = previous, disposition = "imported_frozen",
      frozen_sha256 = file_hash(file.path(destination, "frozen/frozen.json"))))
  }
  old <- read_json(file.path(previous, "audit/session.json"))
  stopifnot(old$status == "failed", grepl("timed out", old$error, ignore.case = TRUE))
  session <- read_json(file.path(previous, "session-config.json"))
  session$project_root <- project_root
  session$input_dir <- ensure_dir(file.path(destination, "input"))
  session$workspace <- ensure_dir(file.path(destination, "work"))
  session$audit_dir <- ensure_dir(file.path(destination, "audit"))
  session$sandbox <- config$sandbox
  write_pair(pair, session$input_dir)
  write_json(session, file.path(destination, "session-config.json"))
  data.frame(previous = previous, disposition = "continue_timeout", frozen_sha256 = NA_character_)
}

#' Initialize a derivative experiment after verifying the complete original archive.
#' @param source Original sealed live run.
#' @param destination New run directory.
#' @param image Rebuilt original-source restricted image.
#' @param runtime_manifest Build-source hashes and commit identity.
completion_prepare <- function(source, destination, image, runtime_manifest) {
  source <- normalizePath(source, mustWork = TRUE)
  stopifnot(doc_package_valid(source), !dir.exists(destination))
  prior <- read_json(file.path(source, "run.json"))
  stopifnot(!prior$offline, prior$prompt_sha256 == file_hash("prompts/system.txt"))
  config <- prior$config
  config$scientific_prompt <- "prompts/system.txt"
  config$sandbox$image <- docker_info(image)
  doc_config(config)
  grid <- doc_grid(config)
  options <- list(run_dir = destination, resume = FALSE, offline = FALSE)
  run_dir <- doc_initialize(config, options, grid)
  data <- doc_prepare_data(config, grid, run_dir, source)
  imports <- list()
  for (i in seq_len(nrow(grid))) {
    setting <- data[[grid$data_id[i]]]
    if (!is.null(setting$error)) next
    for (j in 1:3) {
      relative <- file.path("scenarios", grid$id[i], paste0("agent-", j))
      row <- completion_source(file.path(source, relative), file.path(run_dir, relative),
        config, setting$observations[[j]])
      imports[[length(imports)+1]] <- cbind(scenario = grid$id[i], source = j, row)
    }
  }
  write_csv(do.call(rbind, imports), file.path(run_dir, "source-imports.csv"))
  write_json(list(original_run = source, original_manifest_sha256 = file_hash(file.path(source, "SHA256.csv")),
    original_archive = read_json(file.path(source, "package-complete.json")),
    runtime_source = read_json(runtime_manifest), original_image = prior$config$sandbox$image,
    rebuilt_image = config$sandbox$image, fresh_budgets = FALSE,
    procedure = "Import frozen designs; continue only source-only timeout histories within original budgets; reevaluate every target in rebuilt original-source runtime",
    unchanged_planning_failures = TRUE), file.path(run_dir, "completion-provenance.json"))
  cat("Prepared", run_dir, "with hash-verified imports and isolated timeout continuations.\n")
}

#' Continue only explicitly prepared timeouts; reruns never reset failed budgets.
#' @param run_dir Prepared derivative run.
completion_continue <- function(run_dir) {
  stopifnot(nzchar(Sys.getenv("OPENAI_API_KEY")))
  imports <- read_csv(file.path(run_dir, "source-imports.csv"))
  imports <- imports[imports$disposition == "continue_timeout", ]
  for (i in seq_len(nrow(imports))) {
    row <- imports[i, ]
    base <- file.path(run_dir, "scenarios", row$scenario, paste0("agent-", row$source))
    if (doc_committed(file.path(base, "frozen"))) next
    if (file.exists(file.path(base, "audit/recovery.json"))) {
      cat("Existing continuation retained; no automatic retry:", row$scenario, row$source, "\n")
      next
    }
    doc_atomic(list(status = "running", started = timestamp()), file.path(base, "checkpoint.json"))
    result <- processx::run("poetry", c("run", "python", "-m", "agents.recovery", "--session",
      file.path(base, "session-config.json"), "--previous", row$previous),
      wd = project_root, error_on_status = FALSE, timeout = 3000, cleanup_tree = TRUE)
    writeLines(c(result$stdout, result$stderr), file.path(base, "controller.log"))
    success <- doc_committed(file.path(base, "frozen"))
    doc_atomic(list(status = if (success) "frozen" else "failed", ended = timestamp()),
      file.path(base, "checkpoint.json"))
    cat("Continuation", row$scenario, "source", row$source,
      if (success) "completed" else "failed; audit retained", "\n")
  }
}

#' Evaluate every imported/continued frozen design and regenerate all current summaries.
#' @param run_dir Prepared derivative run with completed continuations.
completion_evaluate <- function(run_dir) {
  imports <- read_csv(file.path(run_dir, "source-imports.csv"))
  for (i in seq_len(nrow(imports))) stopifnot(doc_committed(file.path(run_dir, "scenarios",
    imports$scenario[i], paste0("agent-", imports$source[i]), "frozen")))
  config <- read_json(file.path(run_dir, "run.json"))$config
  options <- list(run_dir = run_dir, resume = TRUE, offline = FALSE, dry_run = FALSE,
    scenario = NULL, reuse_run = NULL)
  doc_run(config, options)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  stage <- cli_value(args, "--stage")
  run_dir <- cli_value(args, "--run-dir")
  stopifnot(!is.null(run_dir), stage %in% c("prepare", "continue", "evaluate"))
  if (stage == "prepare") completion_prepare(cli_value(args, "--source"), run_dir,
    cli_value(args, "--image"), cli_value(args, "--runtime-manifest"))
  if (stage == "continue") completion_continue(normalizePath(run_dir, mustWork = TRUE))
  if (stage == "evaluate") completion_evaluate(normalizePath(run_dir, mustWork = TRUE))
}
