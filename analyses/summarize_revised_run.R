source("R/bootstrap.R")

revised_tool_usage <- function(directory) {
  path <- file.path(directory, "audit/messages.json")
  if (!file.exists(path)) return(list(explorations = NA_integer_, references = NA_integer_, ids = ""))
  messages <- jsonlite::read_json(path, simplifyVector = FALSE)
  parts <- unlist(lapply(messages, `[[`, "parts"), recursive = FALSE)
  calls <- Filter(function(x) identical(x$part_kind, "tool-call"), parts)
  names <- vapply(calls, function(x) x$tool_name %||% "", character(1))
  refs <- calls[names == "read_reference"]
  ids <- vapply(refs, function(x) {
    args <- if (is.character(x$args)) jsonlite::fromJSON(x$args) else x$args
    paste(args$reference_id %||% "?", args$section_id %||% "overview", sep = "/")
  }, character(1))
  list(explorations = sum(names == "run_r"), references = length(refs), ids = paste(unique(ids), collapse = "; "))
}

revised_design_row <- function(run_dir, scenario, source) {
  directory <- file.path(run_dir, "scenarios", scenario$id, paste0("agent-", source))
  session <- read_json(file.path(directory, "audit/session.json"))
  usage <- revised_tool_usage(directory)
  target <- source %% 3L + 1L
  setting <- readRDS(file.path(run_dir, "private", paste0(scenario$data_id, ".rds")))
  effects <- stats::setNames(setting$effects[target, ], colnames(setting$observations[[target]]$exposed))
  frozen <- file.path(directory, "frozen")
  if (dir.exists(frozen)) {
    verify_frozen(frozen)
    manifest <- read_json(file.path(frozen, "frozen.json"))$manifest
    hypotheses <- read_hypothesis_table(file.path(frozen, "hypotheses.csv"))
  } else {
    manifest <- list()
    hypotheses <- NULL
  }
  covered <- if (is.null(hypotheses)) NA_integer_ else length(unique(
    hypotheses$measurement_id[hypotheses$direction * effects[hypotheses$measurement_id] > 0]))
  data.frame(scenario = scenario$id, criterion = scenario$criterion, m = scenario$m, c = scenario$c,
    source = source, target = target, status = session$status,
    selected_coordinates = if (is.null(hypotheses)) NA_integer_ else length(unique(hypotheses$measurement_id)),
    selected_hypotheses = if (is.null(hypotheses)) NA_integer_ else nrow(hypotheses),
    positive_directions = if (is.null(hypotheses)) NA_integer_ else sum(hypotheses$direction == 1L),
    negative_directions = if (is.null(hypotheses)) NA_integer_ else sum(hypotheses$direction == -1L),
    covered_true_directions = covered, nonnull_target = sum(effects != 0),
    explorations = usage$explorations, reference_calls = usage$references, references_requested = usage$ids,
    seconds = session$duration_seconds %||% NA_real_, api_attempts = session$physical_api_attempts %||% NA_integer_,
    test_summary = manifest$test_summary %||% "", multiplicity_summary = manifest$multiplicity_summary %||% "")
}

revised_metric <- function(global, scenario, method, field = "power") {
  row <- global[global$scenario == scenario & global$method == method, ]
  if (nrow(row) != 1L || !row$complete) return(NA_real_)
  row[[field]]
}

revised_comparison <- function(old_dir, run_dir) {
  scenarios <- read_csv(file.path(run_dir, "scenarios.csv"))
  planning <- read_csv(file.path(run_dir, "planning.csv"))
  old <- global_scores(read_csv(file.path(old_dir, "scores.csv")))
  new <- global_scores(read_csv(file.path(run_dir, "scores.csv")))
  rows <- lapply(seq_len(nrow(scenarios)), function(i) {
    scenario <- scenarios[i, ]
    primary <- if (scenario$criterion == "FDR") "welch_bh" else "welch"
    secondary <- if (scenario$criterion == "FDR") "welch_by" else "welch"
    for (field in c("power", "rejected", "false", "realized_fdp")) {
      stopifnot(isTRUE(all.equal(revised_metric(old, scenario$id, "welch", field),
                                revised_metric(new, scenario$id, secondary, field), tolerance = 1e-12)))
    }
    data.frame(scenario = scenario$id, criterion = scenario$criterion, m = scenario$m, c = scenario$c,
      n = planning$n[planning$m == scenario$m & planning$c == scenario$c],
      original_agent_power = revised_metric(old, scenario$id, "agent"),
      revised_agent_power = revised_metric(new, scenario$id, "agent"),
      primary_welch_power = revised_metric(new, scenario$id, primary),
      by_welch_power = if (scenario$criterion == "FDR") revised_metric(new, scenario$id, secondary) else NA_real_,
      revised_agent_rejections = revised_metric(new, scenario$id, "agent", "rejected"),
      revised_agent_false = revised_metric(new, scenario$id, "agent", "false"),
      revised_agent_fdp = revised_metric(new, scenario$id, "agent", "realized_fdp"))
  })
  do.call(rbind, rows)
}

revised_coverage_note <- function(designs) {
  focus <- designs[designs$scenario == "fdr_m1000_c60", ]
  if (nrow(focus) != 3L || anyNA(focus$covered_true_directions)) return("")
  covered <- sum(focus$covered_true_directions)
  total <- sum(focus$nonnull_target)
  sprintf("For example, in FDR / m = 1,000 / c = 0.6, the frozen directions covered %d of %d true target effects (%.1f%%). This limits attainable discoveries before the target test is applied, despite retaining every measurement.",
    covered, total, 100 * covered / total)
}

revised_method_note <- function(designs) {
  weighted <- grepl("\\bweighted\\b|fixed-weight", tolower(designs$multiplicity_summary), perl = TRUE)
  bh <- sum(weighted & designs$criterion == "FDR" & grepl("BH", designs$multiplicity_summary, fixed = TRUE))
  holm <- sum(weighted & designs$criterion == "FWER" & grepl("Holm", designs$multiplicity_summary, fixed = TRUE))
  sprintf("The submitted summaries describe weighted BH in %d FDR designs and weighted Holm in %d FWER designs. Source-derived weights prioritize promising directions while leaving positive weight for others. The allocations remain design choices, not evidence that the agents found an optimal rule.", bh, holm)
}

revised_summary_text <- function(comparison, designs, run_dir) {
  percent <- function(x) ifelse(is.na(x), "—", sprintf("%.1f%%", 100 * x))
  rows <- sprintf("| %s / %d / %.1f | %d | %s | %s | %s | %s |", comparison$criterion,
    comparison$m, comparison$c, comparison$n, percent(comparison$original_agent_power),
    percent(comparison$revised_agent_power), percent(comparison$primary_welch_power), percent(comparison$by_welch_power))
  success <- designs[designs$status == "ok", ]
  evaluations <- read_csv(file.path(run_dir, "scores.csv"))
  agent_evaluations <- evaluations[evaluations$method == "agent", ]
  retries <- list.files(file.path(run_dir, "infrastructure-retries"), pattern = "^session.json$",
                          recursive = TRUE, full.names = TRUE)
  report <- c("# Revised-prompt live run", "",
    sprintf("Completed designs: %d/24. Failed designs: %d. One iteration per scenario; no additional validation draws.",
      nrow(success), sum(designs$status != "ok")), "",
    sprintf("Successful agent evaluations: %d/24; failed or unavailable: %d.",
      sum(agent_evaluations$status == "ok"), sum(agent_evaluations$status != "ok")), "",
    sprintf("Archived infrastructure-failed attempts: %d. Partial histories are preserved separately; the final session usage table describes retained sessions and does not include complete usage for those failed attempts.", length(retries)), "",
    "## Agent design behavior", "",
    sprintf("%d of %d successful designs retained every measurement. Across retained sessions there were %d exploratory R calls and %d reference-tool requests; %d sessions requested at least one reference section. Every session also received the shared reference brief.",
      sum(success$selected_coordinates == success$m), nrow(success), sum(designs$explorations, na.rm = TRUE),
      sum(designs$reference_calls, na.rm = TRUE), sum(designs$reference_calls > 0, na.rm = TRUE)), "",
    revised_method_note(success), "",
    "The per-design CSV contains exact submitted test/correction summaries, selected directions, tool counts, and requested reference IDs. A negative direction in a family containing both alternatives is not evidence that the agent inferred a negative source effect.", "",
    "Retaining every measurement does not necessarily retain its correct target direction. The per-design CSV records how many true target effects were eligible in the frozen directional family; exclusion of the correct direction limits discovery opportunities even without measurement screening.", "",
    revised_coverage_note(designs), "",
    "## Realized power", "",
    "The original and revised runs use identical saved datasets. Primary full-family Welch uses Holm for FWER and BH for FDR; BY is shown separately for FDR. All target families use 0.05/3, with no pooling across groups.", "",
    "| Criterion / m / c | n per arm | Original agent | Revised agent | Primary full Welch | BY full Welch |",
    "|:---|---:|---:|---:|---:|---:|", rows, "",
    "## Interpretation", "",
    sprintf("Revised agent power exceeded the original agent power in %d of eight scenarios and exceeded the primary full-family Welch comparator in %d of eight scenarios in this realization.",
      sum(comparison$revised_agent_power > comparison$original_agent_power, na.rm = TRUE),
      sum(comparison$revised_agent_power > comparison$primary_welch_power, na.rm = TRUE)), "",
    "These are realized outcomes, not estimated long-run error rates. The update changed the prompt, added reference context, and preferred practical BH. Changes from the original agents therefore cannot be attributed to prompt wording alone; the within-run primary Welch comparison is important. The original FDR agents used BY.", "",
    "Execution checks establish the software contract, not statistical validity. Frozen scientific explanations and R code should be examined alongside discovery yield. An incomplete method has no scenario-level power rather than being treated as a zero-discovery success.", "",
    "[Full execution report](report.html) · [Comparison data](comparison.csv) · [Per-agent designs](agent-designs.csv)")
  paste(report, collapse = "\n")
}

render_revised_summary <- function(run_dir) {
  source <- c("---", "title: Revised-prompt live run", "output:", "  html_document:",
    "    self_contained: true", "    theme: readable", "---", "",
    "```{r setup, include=FALSE}",
    "knitr::opts_chunk$set(echo = FALSE, warning = FALSE, message = FALSE)",
    "run_dir <- getwd()", "report_root <- normalizePath(\"../..\", mustWork = TRUE)",
    "knitr::opts_knit$set(root.dir = report_root)", "```", "",
    "```{r results, results='asis'}", "source(\"analyses/summarize_revised_run.R\")",
    "designs <- read_csv(file.path(run_dir, \"agent-designs.csv\"))",
    "comparison <- revised_comparison(file.path(project_root, \"results/live-first\"), run_dir)",
    "text <- revised_summary_text(comparison, designs, run_dir)",
    "cat(sub(\"^# Revised-prompt live run\\n\", \"\", text))", "```")
  input <- file.path(run_dir, "analysis-summary.Rmd")
  writeLines(source, input, useBytes = TRUE)
  rmarkdown::render(input, quiet = TRUE, envir = new.env(parent = globalenv()))
}

summarize_revised_run <- function(old_dir, run_dir) {
  stopifnot(read_json(file.path(run_dir, "run.json"))$mode == "live",
            file.exists(file.path(run_dir, "completion.json")))
  old <- list.files(file.path(old_dir, "private"), pattern = "\\.rds$", full.names = TRUE)
  stopifnot(all(vapply(old, function(x) {
    identical(readRDS(x), readRDS(file.path(run_dir, "private", basename(x))))
  }, logical(1))))
  scenarios <- read_csv(file.path(run_dir, "scenarios.csv"))
  designs <- do.call(rbind, lapply(seq_len(nrow(scenarios)), function(i) {
    do.call(rbind, lapply(seq_len(3L), function(source) revised_design_row(run_dir, scenarios[i, ], source)))
  }))
  comparison <- revised_comparison(old_dir, run_dir)
  write_csv(designs, file.path(run_dir, "agent-designs.csv"))
  write_csv(comparison, file.path(run_dir, "comparison.csv"))
  summary <- file.path(run_dir, "analysis-summary.md")
  writeLines(revised_summary_text(comparison, designs, run_dir), summary, useBytes = TRUE)
  render_revised_summary(run_dir)
  message("Revised-run summary: ", summary)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  summarize_revised_run(cli_value(args, "--original-dir", "results/live-first"),
    cli_value(args, "--run-dir", "results/live-revised-20261101"))
}
