#' Import historical source artifacts explicitly, without weakening strict resume identity.

#' Preserve the original six stream slots and append c=0.9 settings.
#' @param config Validated experiment configuration.
#' @return Ordered data IDs; stable for both supported grids.
setting_stream_ids <- function(config) {
  historical <- config
  historical$power_targets <- c(0.2, 0.6)
  old <- unique(scenario_grid(historical)$data_id)
  c(old, setdiff(unique(scenario_grid(config)$data_id), old))
}

#' Print planned imported/new design counts without Docker, credentials, or models.
#' @param scenarios Selected scenario rows.
#' @param reuse_run Optional historical run directory; contents are verified during execution.
#' @return Prints the plan, explicitly distinguishing artifacts from new sessions.
print_run_plan <- function(scenarios, reuse_run = NULL) {
  print(scenarios, row.names = FALSE)
  reused <- 0L
  if (!is.null(reuse_run)) {
    for (id in scenarios$id) for (source in 1:3) {
      path <- file.path(reuse_run, "scenarios", id, paste0("agent-", source), "frozen/frozen.json")
      reused <- reused + as.integer(file.exists(path))
    }
  }
  cat("Source designs:", 3L * nrow(scenarios), "\nPlanned imported designs:", reused,
    "\nPlanned new sessions:", 3L * nrow(scenarios) - reused, "\nAdditional validation draws: 0\n")
}

#' Snapshot and validate a reuse source before any new sessions.
#' @param config Current configuration with resolved Docker and reference identities.
#' @param path Optional saved run directory.
#' @param offline Whether the destination uses deterministic fixture sessions.
#' @return NULL or provenance containing the source path, identity, and file hashes.
prepare_reuse <- function(config, path, offline) {
  if (is.null(path)) return(NULL)
  path <- normalizePath(path, mustWork = TRUE)
  old <- read_json(file.path(path, "run.json"))
  mode <- if (offline) "offline_fixture" else "live"
  stopifnot(old$mode == mode, file.exists(file.path(path, "completion.json")))
  fields <- c("seed", "alpha", "delta", "tau_squared", "state_probabilities", "openai", "agent",
    "sandbox", "measurements", "max_n", "max_dataset_cells")
  for (field in fields) {
    if (!isTRUE(all.equal(old$config[[field]], config[[field]], check.attributes = FALSE)))
      stop("Reuse configuration differs: ", field)
  }
  stopifnot(old$image_id == config$sandbox$image,
            old$config$reference_digest == reference_pack_digest(config))
  files <- list.files(path, recursive = TRUE, full.names = TRUE, all.files = TRUE)
  files <- files[!file.info(files)$isdir & !grepl("/work/|/report-build/", files)]
  hashes <- as.list(setNames(vapply(files, file_hash, character(1)), substring(files, nchar(path) + 2L)))
  code <- paste("import json; from pathlib import Path; from agents.prompts import load_prompts;",
    "from agents.references import ReferenceLibrary;",
    "print(json.dumps(load_prompts(Path.cwd(), ReferenceLibrary.load(Path('references/agent-pack')))))")
  prompts <- processx::run("poetry", c("run", "python", "-c", code), wd = project_root)
  list(path = path, signature = old$signature, mode = mode, files = hashes,
    prompts = jsonlite::fromJSON(prompts$stdout))
}

#' Verify a snapshotted source file before importing it.
#' @param config Destination configuration containing reuse provenance.
#' @param relative Source-run-relative path.
#' @return Verified regular source file path, or NULL if absent from the source snapshot.
reuse_file <- function(config, relative) {
  if (is.null(config$reuse) || !relative %in% names(config$reuse$files)) return(NULL)
  path <- safe_file(file.path(config$reuse$path, relative), config$reuse$path)
  if (file_hash(path) != config$reuse$files[[relative]]) stop("Reuse source changed: ", relative)
  path
}

#' Copy an available historical dataset without reserializing it.
#' @param config Destination configuration with optional reuse record.
#' @param data_id Measurement/power setting ID.
#' @param destination New private RDS path.
#' @return TRUE if imported; FALSE if this setting requires generation.
import_setting <- function(config, data_id, destination) {
  source <- reuse_file(config, file.path("private", paste0(data_id, ".rds")))
  if (is.null(source)) return(FALSE)
  stopifnot(file.copy(source, destination, overwrite = FALSE), file_hash(source) == file_hash(destination))
  TRUE
}

#' Copy approved historical session files with byte-integrity checks.
#' @param config Configuration containing the source snapshot.
#' @param relative Source-run-relative agent directory.
#' @param directory New agent directory.
#' @return NULL; creates input, frozen, and audit copies only.
copy_imported_session <- function(config, relative, directory) {
  prefix <- paste0(relative, "/")
  paths <- names(config$reuse$files)
  paths <- paths[startsWith(paths, prefix)]
  suffix <- substring(paths, nchar(prefix) + 1L)
  keep <- grepl("^(input/|frozen/|audit/)", suffix) & !grepl("controller[.]log$", suffix)
  for (i in which(keep)) {
    target <- file.path(directory, suffix[i])
    ensure_dir(dirname(target))
    source <- reuse_file(config, paths[i])
    if (!file.exists(target)) stopifnot(file.copy(source, target, overwrite = FALSE))
    stopifnot(file_hash(source) == file_hash(target))
  }
}

#' Recheck one imported design against its own source observations.
#' @param config Current sandbox configuration.
#' @param scenario One scenario row.
#' @param pair Expected source observations from the imported setting.
#' @param directory Destination agent directory.
#' @param source Source subgroup number.
#' @return Original successful session summary, with a separate import/check provenance file.
import_design <- function(config, scenario, pair, directory, source) {
  relative <- file.path("scenarios", scenario$id, paste0("agent-", source))
  existing <- file.path(directory, "design-origin.json")
  if (file.exists(existing)) {
    verify_frozen(file.path(directory, "frozen"))
    return(read_json(file.path(directory, "audit/session.json")))
  }
  ensure_dir(directory)
  copy_imported_session(config, relative, directory)
  for (name in c("exposed", "unexposed"))
    stopifnot(identical(readRDS(file.path(directory, "input", paste0(name, ".rds"))), pair[[name]]))
  prompts <- read_json(file.path(directory, "audit/prompts.json"))
  stopifnot(identical(prompts$system, config$reuse$prompts[[1]]),
            identical(prompts$developer, config$reuse$prompts[[2]]))
  frozen <- file.path(directory, "frozen")
  verify_frozen(frozen)
  request <- list(mode = "check", input_dir = file.path(directory, "input"), workspace = frozen,
    alpha = config$alpha / 3, execution_seed = 731L, sandbox = config$sandbox)
  checked <- execute_sandbox(request)
  write_json(checked, file.path(directory, "imported-check.json"))
  if (checked$status != "ok") stop("Imported source contract failed: ", scenario$id, "/", source)
  verify_frozen(frozen)
  summary <- read_json(file.path(directory, "audit/session.json"))
  stopifnot(summary$status == "ok")
  write_json(list(origin = "imported", source_run = config$reuse$path,
    source_signature = config$reuse$signature, source_directory = relative,
    hashes = read_json(file.path(frozen, "frozen.json"))$hashes, new_api_attempts = 0L), existing)
  summary
}

#' Import an available source design or launch exactly one new session.
#' @param config Validated configuration and optional reuse snapshot.
#' @param scenario One scenario record.
#' @param pair This source's observations only.
#' @param directory Destination source-agent directory.
#' @param source Source subgroup number.
#' @param offline Whether to use a fixture provider for new sessions.
#' @param image_id Resolved Docker image identity.
#' @return Source session summary; imported sessions make no API calls.
prepare_design <- function(config, scenario, pair, directory, source, offline, image_id) {
  relative <- file.path("scenarios", scenario$id, paste0("agent-", source), "frozen/frozen.json")
  if (!is.null(reuse_file(config, relative))) return(import_design(config, scenario, pair, directory, source))
  result <- run_design(config, scenario, pair, directory, offline, image_id)
  write_json(list(origin = "generated", mode = if (offline) "offline_fixture" else "live"),
    file.path(directory, "design-origin.json"))
  result
}
