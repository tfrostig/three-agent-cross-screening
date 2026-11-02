write_pair <- function(pair, directory) {
  ensure_dir(directory)
  saveRDS(pair$exposed, file.path(directory, "exposed.rds"), version = 3)
  saveRDS(pair$unexposed, file.path(directory, "unexposed.rds"), version = 3)
}

fixture_design <- function(pair, workspace, criterion) {
  differences <- colMeans(pair$exposed) - colMeans(pair$unexposed)
  selected <- names(differences)[abs(differences) > 0.25]
  hypotheses <- data.frame(hypothesis_id = paste0(selected, "_selected"),
                           measurement_id = selected,
                           direction = as.integer(sign(differences[selected])))
  write_csv(hypotheses, file.path(workspace, "hypotheses.csv"))
  correction <- if (criterion == "FWER") "holm" else "BY"
  source <- readLines(file.path(project_root, "fixtures", "analysis.R"))
  writeLines(c(sprintf('FIXTURE_CORRECTION <- "%s"', correction), source),
             file.path(workspace, "analysis.R"))
  writeLines(c("OFFLINE FIXTURE — NOT A LIVE AGENT DESIGN", "",
               "Select coordinates with absolute source mean difference > 0.25.",
               "Freeze the source-estimated sign; use one-sided Welch target p-values.",
               paste("Apply", correction, "over the frozen selected hypotheses."),
               "Welch calibration is approximate. Transfer may lose signals or reverse effects.",
               "n < 2 and degenerate variance are explicit failures."),
             file.path(workspace, "report.md"))
}

design_cache_key <- function(config, scenario, input_dir, mode, image_id) {
  prompt_files <- list.files(file.path(project_root, "prompts"), full.names = TRUE)
  object_hash(list(exposed = file_hash(file.path(input_dir, "exposed.rds")),
                   unexposed = file_hash(file.path(input_dir, "unexposed.rds")),
                   criterion = scenario$criterion, alpha = config$alpha / 3,
                   openai = config$openai, agent = config$agent, sandbox = config$sandbox,
                   image_id = image_id, mode = mode,
                   prompts = vapply(prompt_files, file_hash, character(1)),
                   source = source_fingerprint(), references = reference_pack_record(config)))
}

source_fingerprint <- function() {
  directories <- c("agents", "R", "scripts", "fixtures", "docker")
  files <- unlist(lapply(directories, function(x) {
    list.files(file.path(project_root, x), pattern = "\\.(R|py)$", recursive = TRUE, full.names = TRUE)
  }))
  files <- c(files, file.path(project_root, c("poetry.lock", "renv.lock", "docker/Dockerfile")),
             list.files(file.path(project_root, "prompts"), full.names = TRUE))
  object_hash(vapply(sort(files), file_hash, character(1)))
}

verify_frozen <- function(directory) {
  record <- read_json(file.path(directory, "frozen.json"))
  for (name in names(record$hashes)) {
    path <- safe_file(file.path(directory, name), directory)
    if (file_hash(path) != record$hashes[[name]]) stop("Frozen design integrity failure")
  }
  invisible(TRUE)
}

session_manifest <- function(config, scenario, directory, pair, session_id) {
  list(session_id = session_id, m = ncol(pair$exposed), n = nrow(pair$exposed),
       criterion = scenario$criterion, alpha = config$alpha / 3, model = config$openai$model,
       input_dir = file.path(directory, "input"), workspace = file.path(directory, "work"),
       audit_dir = file.path(directory, "audit"), project_root = project_root,
       sandbox = config$sandbox, limits = config$agent, openai = config$openai,
       reference_pack = reference_pack_path(config), reference_digest = reference_pack_digest(config))
}

run_design <- function(config, scenario, pair, directory, offline, image_id) {
  directory <- ensure_dir(directory)
  workspace <- ensure_dir(file.path(directory, "work"))
  ensure_dir(file.path(directory, "audit"))
  write_pair(pair, file.path(directory, "input"))
  key <- design_cache_key(config, scenario, file.path(directory, "input"), offline, image_id)
  cache_file <- file.path(directory, "cache.json")
  if (file.exists(cache_file)) {
    if (read_json(cache_file)$key != key) stop("Cached design inputs changed; start a new run directory")
    verify_frozen(file.path(directory, "frozen"))
    return(read_json(file.path(directory, "audit", "session.json")))
  }
  if (dir.exists(file.path(directory, "frozen"))) stop("Unindexed frozen design; inspect before resume")
  session_id <- paste0("session-", substr(object_hash(list(directory, Sys.time())), 1L, 20L))
  manifest <- session_manifest(config, scenario, directory, pair, session_id)
  write_json(manifest, file.path(directory, "session-input.json"))
  if (offline) fixture_design(pair, workspace, scenario$criterion)
  args <- c("run", "python", "-m", "agents.session", "--session", file.path(directory, "session-input.json"))
  if (offline) args <- c(args, "--offline")
  process <- processx::run("poetry", args, wd = project_root, error_on_status = FALSE,
                           timeout = config$openai$request_limit * 400 + 120)
  writeLines(c(process$stdout, process$stderr), file.path(directory, "audit", "controller.log"))
  summary_file <- file.path(directory, "audit", "session.json")
  if (!file.exists(summary_file)) return(list(status = "failed", error = "Agent controller failed"))
  summary <- read_json(summary_file)
  if (process$status == 0 && identical(summary$status, "ok")) {
    verify_frozen(file.path(directory, "frozen"))
    write_json(list(key = key, completed_at = timestamp()), cache_file)
  }
  summary
}
