escape_html <- function(text) {
  text <- gsub("&", "&amp;", text, fixed = TRUE)
  text <- gsub("<", "&lt;", text, fixed = TRUE)
  text <- gsub(">", "&gt;", text, fixed = TRUE)
  gsub('"', "&quot;", text, fixed = TRUE)
}

planning_table <- function(run_dir) {
  paths <- list.files(file.path(run_dir, "private"), pattern = "\\.rds$", full.names = TRUE)
  rows <- lapply(paths, function(path) {
    setting <- readRDS(path)
    if (!is.null(setting$error)) return(NULL)
    data.frame(m = setting$m, c = setting$target, n = setting$planning$n,
               min_planning_power = min(setting$planning$power),
               previous_min_power = if (is.null(setting$planning$previous_power)) NA_real_
                                    else min(setting$planning$previous_power),
               signals_1 = sum(setting$states[1, ]), signals_2 = sum(setting$states[2, ]),
               signals_3 = sum(setting$states[3, ]))
  })
  data.table::rbindlist(rows, fill = TRUE) |> as.data.frame()
}

agent_reports <- function(run_dir) {
  paths <- list.files(file.path(run_dir, "scenarios"), pattern = "report.md$", recursive = TRUE, full.names = TRUE)
  paths <- paths[basename(dirname(paths)) == "frozen"]
  lapply(paths, function(path) {
    list(label = paste(basename(dirname(dirname(dirname(path)))), basename(dirname(dirname(path)))),
         text = paste(readLines(path, warn = FALSE), collapse = "\n"))
  })
}

session_usage <- function(run_dir) {
  files <- list.files(file.path(run_dir, "scenarios"), pattern = "session.json$", recursive = TRUE, full.names = TRUE)
  rows <- lapply(files, function(path) {
    session <- read_json(path)
    data.frame(session = session$session_id %||% basename(dirname(dirname(path))),
               status = session$status, model = session$model %||% NA_character_,
               seconds = session$duration_seconds %||% NA_real_,
               api_attempts = session$physical_api_attempts %||% 0L,
               input_tokens = session$usage$input_tokens %||% 0L,
               output_tokens = session$usage$output_tokens %||% 0L)
  })
  data.table::rbindlist(rows, fill = TRUE) |> as.data.frame()
}

save_report_plots <- function(scores, run_dir) {
  good <- scores[scores$status == "ok", , drop = FALSE]
  if (!nrow(good)) return(invisible(NULL))
  figure <- ggplot2::ggplot(good, ggplot2::aes(scenario, power, colour = method)) +
    ggplot2::geom_point(position = ggplot2::position_jitter(width = 0.12, height = 0, seed = 1)) +
    ggplot2::theme_minimal(base_size = 11) +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 35, hjust = 1)) +
    ggplot2::labs(title = "Realized directional power — one iteration", x = NULL, y = "Power")
  ggplot2::ggsave(file.path(run_dir, "power.png"), figure, width = 11, height = 5, dpi = 150)
}

render_pilot_report <- function(run_dir) {
  run_dir <- normalizePath(run_dir, mustWork = TRUE)
  run <- read_json(file.path(run_dir, "run.json"))
  scores <- read_csv(file.path(run_dir, "scores.csv"))
  environment <- new.env(parent = globalenv())
  environment$run <- run
  environment$run_dir <- run_dir
  environment$scores <- scores
  environment$global <- read_csv(file.path(run_dir, "global-scores.csv"))
  environment$planning <- planning_table(run_dir)
  environment$reports <- agent_reports(run_dir)
  environment$usage <- session_usage(run_dir)
  environment$escape_html <- escape_html
  save_report_plots(scores, run_dir)
  write_csv(environment$usage, file.path(run_dir, "usage.csv"))
  write_csv(environment$planning, file.path(run_dir, "planning.csv"))
  rmarkdown::render(file.path(project_root, "reports", "pilot.Rmd"),
                     output_file = "report.html", output_dir = run_dir,
                     intermediates_dir = ensure_dir(file.path(run_dir, "report-build")),
                     knit_root_dir = run_dir, envir = environment, quiet = TRUE)
}
