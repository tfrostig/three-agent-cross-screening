#' Saved-output reporting for pooled selection and count-only study recovery.

#' Collect selection ledgers without treating their counts as confirmed discoveries.
#' @param run_dir Saved pooled-selection run.
#' @param filename Scenario-relative CSV filename.
#' @return Combined data frame with a scenario identifier.
collect_scenario_tables <- function(run_dir, filename) {
  scenarios <- read_csv(file.path(run_dir, "scenarios.csv"))
  rows <- lapply(scenarios$id, function(id) {
    path <- file.path(run_dir, "scenarios", id, filename)
    if (!file.exists(path)) return(NULL)
    cbind(data.frame(scenario = id), read_csv(path))
  })
  as.data.frame(data.table::rbindlist(rows, fill = TRUE))
}

#' Plot primary recovery rather than conventional directional power.
#' @param counts Scenario/method count-recovery table.
#' @param run_dir Destination run directory.
#' @return Writes study-count-recovery.png using complete method rows.
plot_study_recovery <- function(counts, run_dir) {
  good <- counts[counts$complete & is.finite(counts$study_count_recovery), ]
  if (!nrow(good)) return(invisible(NULL))
  plot <- ggplot2::ggplot(good, ggplot2::aes(scenario, study_count_recovery, colour = method)) +
    ggplot2::geom_point(position = ggplot2::position_jitter(width = .12, height = 0, seed = 1)) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 40, hjust = 1)) +
    ggplot2::labs(title = "Realized study-count recovery — one iteration", x = NULL, y = "Recovery score")
  ggplot2::ggsave(file.path(run_dir, "study-count-recovery.png"), plot, width = 12, height = 6, dpi = 150)
}

#' Render both full and portable concise reports from saved output only.
#' @param run_dir Completed or failed pooled-selection run.
#' @return Writes report.html, summary.Rmd/html/md, usage, planning, and recovery plot.
render_study_report <- function(run_dir) {
  run_dir <- normalizePath(run_dir, mustWork = TRUE)
  run <- read_json(file.path(run_dir, "run.json"))
  counts <- read_csv(file.path(run_dir, "study-count-summary.csv"))
  scores <- read_csv(file.path(run_dir, "scores.csv"))
  global <- read_csv(file.path(run_dir, "global-scores.csv"))
  planning <- planning_table(run_dir)
  usage <- session_usage(run_dir)
  decisions <- collect_scenario_tables(run_dir, "selection-decisions.csv")
  candidates <- collect_scenario_tables(run_dir, "selection-candidates.csv")
  reports <- agent_reports(run_dir)
  write_csv(planning, file.path(run_dir, "planning.csv"))
  write_csv(usage, file.path(run_dir, "usage.csv"))
  write_csv(decisions, file.path(run_dir, "selection-decisions.csv"))
  write_csv(candidates, file.path(run_dir, "selection-candidates.csv"))
  plot_study_recovery(counts, run_dir)
  environment <- environment()
  rmarkdown::render(file.path(project_root, "reports/study-pilot.Rmd"), output_file = "report.html",
    output_dir = run_dir, intermediates_dir = ensure_dir(file.path(run_dir, "report-build")),
    knit_root_dir = run_dir, envir = environment, quiet = TRUE)
  file.copy(file.path(project_root, "reports/study-summary.Rmd"), file.path(run_dir, "summary.Rmd"), overwrite = TRUE)
  rmarkdown::render(file.path(run_dir, "summary.Rmd"), envir = new.env(parent = baseenv()), quiet = TRUE)
}
