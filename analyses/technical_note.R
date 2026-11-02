#' Legacy original-run reporting helpers; require saved original/comparison data and manually
#'   reviewed test categories.

#' Format a scenario label for the original research note
#'
#' @param row One scenario record to label, or a Word XML row in styling helpers.
#' @return Character label containing criterion, m, and c.
technical_setting <- function(row) sprintf("%s %d / %.1f", row$criterion, row$m, row$c)

#' Format the original run's four-method power comparison
#'
#' @return Markdown table string; requires original run and saved Welch comparison.
concise_note_results <- function() {
  scores <- global_scores(technical_scores())
  scenarios <- read_csv("results/live-first/scenarios.csv")
  planning <- read_csv("results/live-first/planning.csv")
  scenarios <- scenarios[order(match(scenarios$criterion, c("FWER", "FDR")), scenarios$m, scenarios$c), ]
  methods <- c("agent", "agent_shortlist_welch", "welch_screen_welch", "welch")
  rows <- vapply(seq_len(nrow(scenarios)), function(i) {
    scenario <- scenarios[i, ]
    result <- scores[scores$scenario == scenario$id, ]
    result <- result[match(methods, result$method), ]
    n <- planning$n[planning$m == scenario$m & planning$c == scenario$c]
    stopifnot(length(n) == 1L, nrow(result) == 4L, all(result$complete))
    sprintf("| %s | %d | %s |", technical_setting(scenario), n,
      paste(sprintf("%.1f%%", 100 * result$power), collapse = " | "))
  }, character(1))
  paste(c("| Criterion / m / c | n | Agent | Same list | Welch screen | Full Welch |",
    "|:---|---:|---:|---:|---:|---:|", rows), collapse = "\n")
}

#' Map historical report column labels to method IDs
#'
#' @return Named character vector A through E.
technical_methods <- function() {
  c(A = "agent", B = "agent_shortlist_welch", C = "welch_screen_welch",
    D = "welch", E = "oracle_variance_z")
}

#' Join saved historical comparison and oracle rows
#'
#' @return Validated 120-row score table from local results; no analysis is rerun.
technical_scores <- function() {
  replay <- read_csv("results/welch-method-comparison/scores.csv")
  original <- read_csv("results/live-first/scores.csv")
  scores <- rbind(replay, original[original$method == "oracle_variance_z", ])
  stopifnot(nrow(scores) == 120L, all(scores$status == "ok"))
  scores
}

#' Format a chosen historical metric across five methods
#'
#' @param formatter Function accepting an ordered method table and returning display strings.
#' @param headers Character vector of Markdown column headings.
#' @return Markdown table string using the caller's formatter and column headers.
technical_metric_table <- function(formatter, headers) {
  scores <- global_scores(technical_scores())
  scenarios <- read_csv("results/live-first/scenarios.csv")
  rows <- vapply(seq_len(nrow(scenarios)), function(i) {
    scenario <- scenarios[i, ]
    values <- scores[scores$scenario == scenario$id, ]
    values <- values[match(technical_methods(), values$method), ]
    stopifnot(nrow(values) == 5L, all(values$complete))
    paste0("| ", technical_setting(scenario), " | ", paste(formatter(values), collapse = " | "), " |")
  }, character(1))
  paste(c(paste0("| Setting | ", paste(headers, collapse = " | "), " |"),
          "|:---|---:|---:|---:|---:|---:|", rows), collapse = "\n")
}

#' Format and check historical sample-size minimality
#'
#' @return Markdown table; requires planning.csv and verifies the strict crossing condition.
technical_planning_table <- function() {
  x <- read_csv("results/live-first/planning.csv")
  x <- x[order(x$m, x$c), ]
  stopifnot(all(x$min_planning_power > x$c), all(x$previous_min_power <= x$c))
  rows <- sprintf("| %d / %.1f | %d | %.6f | %.6f | %d, %d, %d |", x$m, x$c, x$n,
                  x$previous_min_power, x$min_planning_power, x$signals_1, x$signals_2, x$signals_3)
  paste(c("| m / c | n | Min power at n minus 1 | Min power at n | Signals in Groups 1, 2, 3 |",
          "|:---|---:|---:|---:|:---|", rows), collapse = "\n")
}

#' Look up manually reviewed test categories in the original run
#'
#' @param scenario Original-run scenario ID string, not a scenario data frame.
#' @param source Source subgroup index (1, 2, or 3).
#' @return T1-T4 label; valid only for the archived original 24 designs, not new runs.
technical_test_type <- function(scenario, source) {
  id <- paste0(scenario, "/agent-", source)
  if (id %in% c("fdr_m100_c20/agent-1", "fdr_m1000_c20/agent-1")) return("T4")
  if (id == "fdr_m1000_c60/agent-3") return("T3")
  if (id %in% c("fdr_m100_c20/agent-2", "fdr_m1000_c20/agent-2",
                "fdr_m1000_c20/agent-3", "fwer_m20_c60/agent-3")) return("T2")
  "T1"
}

#' Summarize all original frozen designs and true-direction coverage
#'
#' @return Validated 24-row table; reads private truth on the trusted host and verifies frozen
#'   hashes.
technical_agent_rows <- function() {
  scenarios <- read_csv("results/live-first/scenarios.csv")
  original <- read_csv("results/live-first/scores.csv")
  rows <- lapply(seq_len(nrow(scenarios)), function(i) {
    scenario <- scenarios[i, ]
    setting <- readRDS(file.path("results/live-first/private", paste0(scenario$data_id, ".rds")))
    lapply(seq_len(3L), function(source) {
      target <- source %% 3L + 1L
      directory <- file.path("results/live-first/scenarios", scenario$id, paste0("agent-", source), "frozen")
      verify_frozen(directory)
      h <- read_hypothesis_table(file.path(directory, "hypotheses.csv"))
      ids <- colnames(setting$observations[[target]]$exposed)
      effects <- stats::setNames(setting$effects[target, ], ids)
      covered <- length(unique(h$measurement_id[h$direction * effects[h$measurement_id] > 0]))
      score <- original[original$scenario == scenario$id & original$method == "agent" & original$source == source, ]
      stopifnot(nrow(score) == 1L, score$selected == nrow(h), score$correct_coordinates <= covered)
      data.frame(scenario = scenario$id, setting = technical_setting(scenario), source = source, target = target,
        type = technical_test_type(scenario$id, source), selected_coordinates = length(unique(h$measurement_id)),
        selected_hypotheses = nrow(h), covered = covered, nonnull = sum(effects != 0),
        rejected = score$rejected, false = score$false, correct = score$correct_coordinates,
        fdp = score$fdp, power = score$power)
    })
  }) |> unlist(recursive = FALSE)
  result <- do.call(rbind, rows)
  stopifnot(identical(as.integer(table(result$type)), c(17L, 4L, 1L, 2L)))
  result
}

#' Aggregate original source-family coverage of target signals
#'
#' @param agents Original per-design table from technical_agent_rows().
#' @return Markdown table and a saved coverage.csv under comparison report-tables.
technical_coverage_table <- function(agents) {
  rows <- lapply(split(agents, factor(agents$scenario, levels = unique(agents$scenario))), function(x) {
    data.frame(setting = x$setting[1], scenario = x$scenario[1], covered = sum(x$covered),
      nonnull = sum(x$nonnull), correct = sum(x$correct), coverage = sum(x$covered) / sum(x$nonnull),
      conditional_detection = sum(x$correct) / sum(x$covered))
  })
  x <- do.call(rbind, rows)
  write_csv(x, "results/welch-method-comparison/report-tables/coverage.csv")
  values <- sprintf("| %s | %d / %d | %.1f%% | %d / %d | %.1f%% |", x$setting,
    x$covered, x$nonnull, 100 * x$coverage, x$correct, x$covered, 100 * x$conditional_detection)
  paste(c("| Setting | Covered signals / all signals | Coverage | Correct / covered | Detection among covered |",
          "|:---|---:|---:|---:|---:|", values), collapse = "\n")
}

#' Format original-run elapsed time and model usage
#'
#' @return Markdown table from saved retained-session usage and run timestamps.
technical_usage_table <- function() {
  x <- read_csv("results/live-first/usage.csv")
  run <- read_json("results/live-first/run.json")
  done <- read_json("results/live-first/completion.json")
  elapsed <- as.numeric(difftime(as.POSIXct(done$completed_at, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    as.POSIXct(run$started_at, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), units = "mins"))
  rows <- c(sprintf("| Successful sessions | %d / 24 |", sum(x$status == "ok")),
    sprintf("| Total physical API attempts | %d |", sum(x$api_attempts)),
    sprintf("| Input tokens summed across requests | %s |", format(sum(x$input_tokens), big.mark = ",", scientific = FALSE)),
    sprintf("| Output tokens | %s |", format(sum(x$output_tokens), big.mark = ",", scientific = FALSE)),
    sprintf("| Session duration median and range in seconds | %.1f; %.1f to %.1f |", median(x$seconds), min(x$seconds), max(x$seconds)),
    sprintf("| Original run elapsed time in minutes | %.1f |", elapsed),
    "| Target execution or contract failures | 0 |")
  paste(c("| Execution measure | Observed value |", "|:---|---:|", rows), collapse = "\n")
}

#' Build the historical technical note's data-dependent sections
#'
#' @return Named Markdown replacements; also writes agent-design and global-results report
#'   tables.
technical_sections <- function() {
  agents <- technical_agent_rows()
  scores <- technical_scores()
  write_csv(agents, "results/welch-method-comparison/report-tables/agent-designs.csv")
  write_csv(global_scores(scores), "results/welch-method-comparison/report-tables/global-results.csv")
  list(TECH_PLANNING = technical_planning_table(),
    TECH_POWER = technical_metric_table(function(x) sprintf("%.2f%%", 100 * x$power),
      c("A Agent", "B Same family", "C Welch screen", "D Full Welch", "E Oracle z")),
    TECH_COUNTS = technical_metric_table(function(x) sprintf("%d / %d", x$rejected, x$false), LETTERS[1:5]),
    TECH_FDP = technical_metric_table(function(x) sprintf("%.3f%%", 100 * x$realized_fdp), LETTERS[1:5]),
    TECH_COVERAGE = technical_coverage_table(agents), TECH_USAGE = technical_usage_table())
}

#' Format original per-design routes and outcomes
#'
#' @return Markdown appendix; depends on manually reviewed original test-type labels.
technical_agent_appendix <- function() {
  x <- technical_agent_rows()
  rows <- sprintf("| %s | %d to %d | %s | %d / %d | %d / %d | %.2f%% |", x$setting,
    x$source, x$target, x$type, x$selected_coordinates, x$selected_hypotheses,
    x$rejected, x$false, 100 * x$power)
  paste0(note_page_break(), "# Appendix E Results for each frozen design\n\n",
    "The route identifies source and target. J is the number of selected coordinates; K counts directional hypotheses. R is rejections and V false directional claims. Power uses all nonzero target effects as denominator. Test types T1 to T4 are defined in the main text.\n\n",
    paste(c("| Setting | Route | Test | J / K | R / V | Power |", "|:---|:---|:---|---:|---:|---:|", rows), collapse = "\n"))
}
