source(file.path(project_root, "R/document.R"))
source(file.path(project_root, "R/document_report.R"))
source(file.path(project_root, "R/document_checkpoint.R"))
source(file.path(project_root, "R/document_results.R"))

#' Validate document configuration without resolving legacy reference packs.
#' @param config Document configuration.
doc_config <- function(config) {
  stopifnot(config$protocol == "document-v2", config$alpha == 0.05,
    identical(config$scientific_prompt, "prompts/document-20261111.txt"),
    identical(names(config$regimes), c("dense", "sparse")))
  prompt <- file.path(project_root, config$scientific_prompt)
  stopifnot(file_hash(prompt) == read_json(sub("[.]txt$", ".provenance.json", prompt))$prompt_sha256)
  for (regime in names(config$regimes)) {
    cfg <- config
    cfg$state_probabilities <- config$regimes[[regime]]
    validate_config(cfg)
  }
  invisible(config)
}

#' Export exactly the agent-visible instructions, metadata template and tool schemas.
#' @param output Preview destination.
doc_preview <- function(output) {
  result <- processx::run("poetry", c("run", "python", "-m", "agents.document_preview", "--output", output), wd = project_root)
  invisible(result)
}

#' Run offline/live preflight, including every planning slot before agent calls.
#' @param config Document configuration.
#' @param offline Whether to skip credential availability checks.
doc_preflight <- function(config, offline = TRUE) {
  doc_config(config)
  if (!offline && (!nzchar(Sys.getenv("OPENAI_API_KEY")) || !nzchar(config$openai$model)))
    stop("Explicit model and exported OPENAI_API_KEY required; .env is never read")
  require_packages(r_packages())
  stopifnot(rmarkdown::pandoc_available())
  image <- docker_info(config$sandbox$image)
  grid <- doc_grid(config)
  cat("Scenarios:", nrow(grid), "Datasets:", length(unique(grid$data_id)),
    "Maximum source sessions:", 3*nrow(grid), "Validation draws: 0\n")
  image
}

#' Persist one method's full target results and score tables.
#' @param method Method name.
#' @param targets Three target outputs.
#' @param setting Host-private truth used only here.
#' @param scenario Scenario row.
#' @param directory Scenario directory.
doc_save_method <- function(method, targets, setting, scenario, directory) {
  destination <- ensure_dir(file.path(directory, method))
  write_json(targets, file.path(destination, "target-results.json"))
  scored <- doc_scores(setting$effects, targets)
  display <- doc_display(targets, scored$table, colnames(setting$effects))
  write_csv(display, file.path(destination, "outcomes.csv"))
  directional <- doc_directional(setting$effects, targets)
  if (!is.null(directional)) write_csv(directional, file.path(destination, "directional-metrics.csv"))
  cbind(scenario[c("id", "regime", "m", "c", "criterion")], method = method, scored$summary)
}

#' Execute one already-planned scenario after all source sessions finish.
#' @param config Document configuration.
#' @param scenario Scenario row.
#' @param setting Generated/imported setting.
#' @param run_dir New run root.
#' @param offline Use deterministic PydanticAI fixtures.
doc_scenario <- function(config, scenario, setting, run_dir, offline) {
  directory <- ensure_dir(file.path(run_dir, "scenarios", scenario$id))
  cached <- doc_scenario_checkpoint(directory)
  if (!is.null(cached)) return(cached)
  for (source in 1:3) doc_session(config, scenario, setting, directory, source, offline)
  results <- doc_select(config, setting$observations, directory)
  results$welch_two_sided <- doc_baseline(config, setting$observations, scenario$criterion)
  results$oracle_z_secondary <- doc_oracle(config, setting$observations, setting$effects, scenario$criterion)
  scores <- do.call(rbind, lapply(names(results), function(method)
    doc_save_method(method, results[[method]], setting, scenario, directory)))
  doc_commit_scenario(directory, scores)
  scores
}

#' Create a new versioned run, prepare all datasets, run scenarios and package outputs.
#' @param config Document configuration.
#' @param options CLI execution options; legacy resume/design reuse are not accepted.
doc_run <- function(config, options) {
  doc_config(config)
  grid <- doc_grid(config)
  if (!is.null(options$scenario)) grid <- grid[grid$id %in% options$scenario, , drop = FALSE]
  stopifnot(nrow(grid) > 0)
  if (options$dry_run) {
    print(grid)
    cat("Source designs:", 3*nrow(grid), "\nAdditional validation draws: 0\n")
    return(invisible(NULL))
  }
  stopifnot(!is.null(options$run_dir))
  config$sandbox$image <- doc_preflight(config, options$offline)
  run_dir <- doc_initialize(config, options, grid)
  lock <- doc_lock(run_dir)
  on.exit(unlink(lock, recursive = TRUE))
  if (doc_package_valid(run_dir)) return(invisible(run_dir))
  historical <- options$reuse_run
  data <- doc_prepare_data(config, grid, run_dir, historical)
  summaries <- failures <- list()
  for (i in seq_len(nrow(grid))) {
    scenario <- grid[i, ]
    setting <- data[[scenario$data_id]]
    if (!is.null(setting$error)) {
      failures[[length(failures)+1]] <- data.frame(scenario = scenario$id, error = setting$error)
      next
    }
    summaries[[length(summaries)+1]] <- doc_scenario(config, scenario, setting, run_dir, options$offline)
    write_csv(do.call(rbind, summaries), file.path(run_dir, "summary-progress.csv"))
  }
  summary <- if (length(summaries)) do.call(rbind, summaries) else data.frame()
  failed <- if (length(failures)) do.call(rbind, failures) else data.frame(scenario = character(), error = character())
  write_json(list(completed = timestamp(), scenarios = nrow(grid), offline = options$offline), file.path(run_dir, "completion.json"))
  doc_audits(run_dir, data, historical)
  doc_report(run_dir, summary, failed)
  invisible(run_dir)
}
