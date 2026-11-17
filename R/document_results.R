#' Results-first reporting helpers; agent text is always rendered as inert content.

#' Extract a named section without altering the agent's wording.
#' @param lines Agent Markdown lines.
#' @param heading Exact required section title.
doc_section <- function(lines, heading) {
  start <- grep(paste0("^#{1,6} +", heading, " *#* *$"), lines, ignore.case = TRUE)
  if (!length(start)) return("Missing section; inspect original report")
  following <- which(seq_along(lines) > start[1] & grepl("^#{1,6} ", lines))
  end <- if (length(following)) following[1]-1 else length(lines)
  paste(lines[seq.int(start[1]+1, max(start[1]+1, end))], collapse = "\n")
}

#' Inventory all proposed designs separately from the selected target algorithms.
#' @param run_dir Run root.
doc_method_inventory <- function(run_dir) {
  paths <- list.files(file.path(run_dir, "scenarios"), pattern = "checkpoint.json$", recursive = TRUE, full.names = TRUE)
  rows <- lapply(paths, function(path) {
    base <- dirname(path)
    scenario <- basename(dirname(base))
    source <- as.integer(sub("agent-", "", basename(base)))
    state <- read_json(path)$status
    frozen <- file.path(base, "frozen")
    targets <- integer()
    choices <- file.path(dirname(base), "selection-decisions.csv")
    if (file.exists(choices)) {
      decisions <- read_csv(choices)
      targets <- decisions$target[!is.na(decisions$source) & decisions$source == source]
    }
    h <- if (state == "frozen") doc_hypotheses(doc_frozen(frozen)$hypotheses) else NULL
    report <- if (state == "frozen") readLines(file.path(frozen, "report.md"), warn = FALSE) else character()
    relative <- substring(frozen, nchar(run_dir)+2)
    data.frame(scenario = scenario, source = source, status = state,
      measurements = if (is.null(h)) NA_integer_ else length(unique(h$measurement_id)),
      directional_hypotheses = if (is.null(h)) NA_integer_ else nrow(h),
      positive = if (is.null(h)) NA_integer_ else sum(h$direction == 1),
      negative = if (is.null(h)) NA_integer_ else sum(h$direction == -1),
      both_directions = if (is.null(h)) NA_integer_ else sum(table(h$measurement_id) == 2),
      selected_targets = paste(targets, collapse = ","), selected_count = length(targets),
      procedure = doc_section(report, "Final procedure"), selection = doc_section(report, "Hypothesis selection"),
      report_file = paste0(relative, "/report.md"), code_file = paste0(relative, "/analysis.R"),
      exploration_file = paste0(relative, "/exploration.md"))
  })
  if (length(rows)) do.call(rbind, rows) else data.frame()
}

#' Pair only complete agent and standard evaluations for fair comparisons.
#' @param summary Scenario/method scores.
doc_pairs <- function(summary) {
  a <- summary[summary$method == "agent_pooled_select", ]
  b <- summary[summary$method == "welch_two_sided", ]
  b <- b[match(a$id, b$id), ]
  good <- !is.na(a$complete) & a$complete == 1 & !is.na(b$complete) & b$complete == 1
  a <- a[good, ]; b <- b[good, ]
  data.frame(a[c("id", "regime", "criterion", "m", "c")], agent_recovery = a$study_count_recovery,
    standard_recovery = b$study_count_recovery, agent_true_rep = a$true_replicability_discoveries,
    standard_true_rep = b$true_replicability_discoveries,
    recovery_difference = a$study_count_recovery-b$study_count_recovery,
    replicability_difference = a$true_replicability_discoveries-b$true_replicability_discoveries)
}

#' Summarize paired score differences without estimating long-run performance.
#' @param pairs Matched complete scenarios.
doc_pair_table <- function(pairs) {
  if (!nrow(pairs)) return(data.frame(Note = "No complete matched comparisons"))
  groups <- split(pairs, interaction(pairs$regime, pairs$criterion, drop = TRUE))
  do.call(rbind, lapply(groups, function(x) data.frame(regime = x$regime[1], criterion = x$criterion[1],
    paired_scenarios = nrow(x), agent_higher = sum(x$recovery_difference > 1e-12),
    tied = sum(abs(x$recovery_difference) <= 1e-12), agent_lower = sum(x$recovery_difference < -1e-12),
    mean_difference_percentage_points = 100*mean(x$recovery_difference))))
}

#' Show the six primary counts on the same completed scenarios for both methods.
#' @param summary All saved scores.
#' @param pairs Common evaluable scenarios.
doc_primary_table <- function(summary, pairs) {
  x <- summary[summary$id %in% pairs$id & summary$method %in% c("agent_pooled_select", "welch_two_sided"), ]
  if (!nrow(x)) return(data.frame(Note = "No common complete scenarios"))
  fields <- c("claimed_studies", "correct_lower_bound_credit", "global_discoveries", "true_global_discoveries",
    "replicability_discoveries", "true_replicability_discoveries")
  total <- aggregate(x[fields], x[c("regime", "criterion", "method")], sum)
  data.frame(total[c("regime", "criterion", "method")], study_claims = total$claimed_studies,
    correct_count_credit = total$correct_lower_bound_credit,
    global_total_true = sprintf("%d (%d)", total$global_discoveries, total$true_global_discoveries),
    replicability_total_true = sprintf("%d (%d)", total$replicability_discoveries, total$true_replicability_discoveries))
}

#' Save two static scientific plots for export with the report.
#' @param pairs Complete paired results.
#' @param run_dir Run root.
doc_result_plots <- function(pairs, run_dir) {
  if (!nrow(pairs)) return(character())
  directory <- ensure_dir(file.path(run_dir, "figures"))
  p <- ggplot2::ggplot(pairs, ggplot2::aes(standard_recovery, agent_recovery, colour = factor(m))) +
    ggplot2::geom_abline(slope = 1, intercept = 0, linetype = 2, colour = "grey50") +
    ggplot2::geom_point(size = 3) + ggplot2::facet_grid(regime ~ criterion) +
    ggplot2::labs(x = "Standard Welch: study-count recovery", y = "Agents: study-count recovery", colour = "m") +
    ggplot2::theme_minimal(base_size = 12)
  ggplot2::ggsave(file.path(directory, "recovery.png"), p, width = 9, height = 6, dpi = 160)
  p <- ggplot2::ggplot(pairs, ggplot2::aes(paste0("m=", m, ", c=", c), replicability_difference)) +
    ggplot2::geom_hline(yintercept = 0, colour = "grey50") + ggplot2::geom_col(fill = "#31688e") +
    ggplot2::facet_grid(regime ~ criterion, scales = "free_x") + ggplot2::coord_flip() +
    ggplot2::labs(x = NULL, y = "True replicability discoveries: agents minus standard Welch") +
    ggplot2::theme_minimal(base_size = 11)
  ggplot2::ggsave(file.path(directory, "replicability.png"), p, width = 10, height = 7, dpi = 160)
  c("![Paired study-count recovery](figures/recovery.png)",
    "![Difference in true replicability discoveries](figures/replicability.png)")
}

#' Link and preserve every original agent report and its recorded exploration.
#' @param inventory Proposed-design inventory.
#' @param run_dir Run root.
doc_agent_appendix <- function(inventory, run_dir) {
  if (!nrow(inventory)) return("No source attempts available.")
  index <- inventory[c("scenario", "source", "status", "measurements", "both_directions", "selected_targets")]
  lines <- c("## Appendix: proposed and selected designs", knitr::kable(index),
    "Full procedure descriptions, hypothesis-selection explanations and artifact links are in agent-methods.csv.")
  for (i in seq_len(nrow(inventory))) {
    row <- inventory[i, ]
    if (row$status != "frozen") next
    text <- paste(readLines(file.path(run_dir, row$report_file), warn = FALSE), collapse = "\n")
    label <- paste(row$scenario, "agent", row$source)
    lines <- c(lines, "", paste0("<details><summary>", label, ": original agent Markdown</summary><pre>",
      doc_escape(text), "</pre></details>"),
      sprintf("[Original Markdown](%s) | [R design](%s) | [Executed exploration](%s)",
        row$report_file, row$code_file, row$exploration_file))
  }
  writeLines(lines, file.path(run_dir, "agent-index.md"))
  lines
}

#' Quote representative selections and code while keeping original text distinguishable.
#' @param inventory Proposed-design inventory.
#' @param run_dir Run root.
doc_method_examples <- function(inventory, run_dir) {
  rows <- inventory[inventory$status == "frozen", ]
  if (!nrow(rows)) return(character())
  rows <- rows[order(-rows$selected_count), ]
  signatures <- paste(grepl("fwer", rows$scenario), rows$both_directions > 0,
    rows$measurements, substr(rows$procedure, 1, 120))
  rows <- head(rows[!duplicated(signatures), ], 6)
  lines <- "## Appendix: representative hypothesis choices and code"
  for (i in seq_len(nrow(rows))) {
    row <- rows[i, ]
    code <- readLines(file.path(run_dir, row$code_file), warn = FALSE)
    start <- grep("analyze *<- *function", code)
    start <- if (length(start)) start[1] else 1
    excerpt <- paste(head(code[seq.int(start, length(code))], 30), collapse = "\n")
    lines <- c(lines, paste("###", row$scenario, "agent", row$source),
      "Agent's hypothesis-selection explanation (excerpt; not a validation of its justification):",
      paste0("<pre>", doc_escape(substr(row$selection, 1, 1800)), "</pre>"),
      "Agent's executable procedure (excerpt; full script linked in the index):",
      paste0("<pre>", doc_escape(excerpt), "</pre>"))
  }
  lines
}

#' Create controlled report text, distinguishing real calls from fixtures.
#' @param run_dir Run root.
#' @param summary Scenario scores.
#' @param failures Planning failure rows.
#' @param inventory Proposed/selected source designs.
doc_results_text <- function(run_dir, summary, failures, inventory) {
  offline <- isTRUE(read_json(file.path(run_dir, "run.json"))$offline)
  pairs <- doc_pairs(summary)
  write_csv(pairs, file.path(run_dir, "paired-comparisons.csv"))
  mode <- if (offline) "OFFLINE SOFTWARE FIXTURES: prewritten analyses, not autonomous agent findings." else
    "LIVE AGENT EXPERIMENT: new source designs under the unchanged document prompt."
  frozen <- if (nrow(inventory)) sum(inventory$status == "frozen") else 0
  lines <- c("---", "title: 'Updated-prompt experiment: results and methods'", "output: html_document", "---", "",
    paste0("**", mode, "**"), "## Findings",
    sprintf("There are %d frozen designs from %d source attempts, %d planning failures, and %d complete agent-versus-standard scenario comparisons.",
      frozen, nrow(inventory), nrow(failures), nrow(pairs)),
    if (nrow(pairs)) sprintf("Study-count recovery was higher for agents in %d scenarios, tied in %d, and lower in %d.",
      sum(pairs$recovery_difference > 1e-12), sum(abs(pairs$recovery_difference) <= 1e-12), sum(pairs$recovery_difference < -1e-12)),
    "These are realized outcomes from one iteration, not estimates of long-run FWER or FDR.",
    "## Compared procedures",
    "Agents explore only their source study and freeze an R design. For each target, the other two designs compete on their pooled data; the one with more discovered measurements is applied unchanged to the held-out target. Pooled selection counts are exploratory. The original cycle and the truth-informed oracle remain secondary.",
    "Standard analysis tests all measurements with two-sided Welch tests, Holm for FWER or BH for FDR, separately within each of the three studies at 0.05/3. Both procedures use identical target observations and identical discovery/count scores. The standard procedure makes no directional claims.",
    "## Six main results",
    "Counts below use only scenarios complete for both primary approaches. Parentheses contain true discoveries. Full per-scenario results, including incomplete cases and secondary comparators, are in summary.csv. These are descriptive sums over different settings; m=100 FWER/FDR settings share data.",
    knitr::kable(doc_primary_table(summary, pairs)), "## Paired recovery comparisons",
    knitr::kable(doc_pair_table(pairs)), doc_result_plots(pairs, run_dir),
    "## Interpretation",
    "Global discovery finds measurements with an effect somewhere; replicability requires effects in at least two studies. Count recovery rewards the recovered number of studies and penalizes overclaims; it can give credit for the wrong studies or signs. These objectives need not rank methods identically. See wrong-study, overclaim, all-null and directional error outputs alongside discovery yields. A zero-error realization does not establish error control.",
    "## Failures and resource use", knitr::kable(failures))
  for (name in c("usage.csv", "planning.csv")) if (file.exists(file.path(run_dir, name)))
    lines <- c(lines, paste("###", name), knitr::kable(read_csv(file.path(run_dir, name))))
  lines
}

#' Render a results-first report with inert original-agent appendices.
#' @param run_dir Run root.
#' @param summary Saved scenario scores.
#' @param failures Planning failures.
doc_write_results <- function(run_dir, summary, failures) {
  inventory <- doc_method_inventory(run_dir)
  write_csv(inventory, file.path(run_dir, "agent-methods.csv"))
  lines <- doc_results_text(run_dir, summary, failures, inventory)
  lines <- c(lines, doc_history(run_dir, summary), readLines(file.path(project_root, "docs/document-metrics.md")),
    "## Appendix: exact scientific prompt",
    paste0("<pre>", doc_escape(paste(readLines("prompts/system.txt", warn = FALSE), collapse = "\n")), "</pre>"),
    "## Appendix: complete model-visible technical instructions",
    paste0("<pre>", doc_escape(paste(readLines(file.path(run_dir, "prompt-preview.md")), collapse = "\n")), "</pre>"),
    doc_method_examples(inventory, run_dir), doc_agent_appendix(inventory, run_dir))
  choices <- list.files(file.path(run_dir, "scenarios"), pattern = "selection-decisions.csv$", recursive = TRUE, full.names = TRUE)
  routes <- lapply(choices, function(path) cbind(scenario = basename(dirname(path)), read_csv(path)))
  if (length(routes)) {
    routes <- do.call(rbind, routes)
    write_csv(routes, file.path(run_dir, "selected-algorithms.csv"))
    lines <- c(lines, "## Appendix: selected target algorithms", knitr::kable(routes))
  }
  path <- file.path(run_dir, "report.Rmd")
  writeLines(lines, path)
  rmarkdown::render(path, quiet = TRUE, envir = new.env(parent = baseenv()))
}

#' Package complete local records and a smaller shareable subset without raw matrices.
#' @param run_dir Run root.
doc_package <- function(run_dir) {
  files <- list.files(run_dir, recursive = TRUE, full.names = TRUE)
  files <- files[!file.info(files)$isdir & !grepl("/SHA256.csv$|/package-complete.json$|/.controller-lock/", files)]
  write_csv(data.frame(path = substring(files, nchar(run_dir)+2), sha256 = vapply(files, file_hash, character(1))), file.path(run_dir, "SHA256.csv"))
  destination <- ensure_dir(file.path(project_root, "exports"))
  zip <- file.path(destination, paste0(basename(run_dir), ".zip"))
  if (file.exists(zip)) stopifnot(file.rename(zip, paste0(zip, ".interrupted-", format(Sys.time(), "%Y%m%d%H%M%S"))))
  old <- setwd(dirname(run_dir))
  on.exit(setwd(old))
  utils::zip(zip, basename(run_dir), flags = "-qr", extras = "-x */.controller-lock/*")
  setwd(old)
  share <- file.path(destination, paste0(basename(run_dir), "-share.zip"))
  staging <- ensure_dir(tempfile("document-share-"))
  on.exit(unlink(staging, recursive = TRUE), add = TRUE)
  root <- ensure_dir(file.path(staging, basename(run_dir)))
  relative <- substring(files, nchar(run_dir)+2)
  keep <- !grepl("(^|/)(private|input|work|.controller-lock)/", relative)
  for (i in which(keep)) {
    path <- file.path(root, relative[i])
    ensure_dir(dirname(path))
    stopifnot(file.copy(files[i], path))
  }
  writeLines(c("# Shareable results bundle", "Open report.html. Editable report.Rmd, agent-index.md and agent-methods.csv provide methods, rationale and exploratory code.",
    "All scenario/measurement tables and execution audits are included. Raw observations, truth matrices and mutable workspaces are omitted; dataset hashes remain in datasets.json.",
    "The complete local archive contains raw simulation data. SHA256.csv indexes this subset only."), file.path(root, "README.md"))
  shared <- list.files(root, recursive = TRUE, full.names = TRUE)
  write_csv(data.frame(path = substring(shared, nchar(root)+2), sha256 = vapply(shared, file_hash, character(1))), file.path(root, "SHA256.csv"))
  setwd(staging)
  if (file.exists(share)) stopifnot(file.rename(share, paste0(share, ".interrupted-", format(Sys.time(), "%Y%m%d%H%M%S"))))
  utils::zip(share, basename(run_dir), flags = "-qr")
  setwd(old)
  doc_atomic(list(zip = zip, sha256 = file_hash(zip), share = share, share_sha256 = file_hash(share),
    manifest_sha256 = file_hash(file.path(run_dir, "SHA256.csv"))), file.path(run_dir, "package-complete.json"))
}

#' Record the selected artifact digest, including a missing-candidate sentinel.
#' @param directory Scenario directory.
#' @param source Source index or NA.
doc_source_hash <- function(directory, source) {
  if (is.na(source)) return(NA_character_)
  tryCatch(object_hash(doc_frozen(file.path(directory, paste0("agent-", source), "frozen"))$hashes),
    error = function(e) NA_character_)
}

#' Compare new and prior live workflows only on byte-identical dense datasets.
#' @param run_dir Current run root.
#' @param summary Current scores.
doc_history <- function(run_dir, summary) {
  record <- read_json(file.path(run_dir, "run.json"))
  if (isTRUE(record$offline)) return(character())
  config <- record$config
  root <- config$historical_comparison_run
  if (is.null(root) || !file.exists(file.path(root, "study-count-summary.csv"))) return(character())
  old <- read_csv(file.path(root, "study-count-summary.csv"))
  new <- summary[summary$method == "agent_pooled_select" & summary$regime == "dense", ]
  rows <- lapply(seq_len(nrow(new)), function(i) {
    row <- new[i, ]
    id <- sub("^dense_", "", row$id)
    prior <- old[old$scenario == id & old$method == row$method, ]
    if (nrow(prior) != 1) return(NULL)
    data_id <- sub("^(fwer|fdr)_", "", id)
    stopifnot(file_hash(file.path(root, "private", paste0(data_id, ".rds"))) ==
      file_hash(file.path(run_dir, "private", paste0("dense_", data_id, ".rds"))))
    data.frame(scenario = row$id, new_complete = row$complete, prior_complete = prior$complete,
      new_recovery = row$study_count_recovery, prior_recovery = prior$study_count_recovery,
      difference = row$study_count_recovery-prior$study_count_recovery)
  })
  rows <- do.call(rbind, rows)
  if (is.null(rows)) return(character())
  write_csv(rows, file.path(run_dir, "historical-workflow-comparison.csv"))
  c("## Appendix: matched historical live-workflow comparison",
    "Dense settings only, verified identical observations. This compares workflows, not a prompt-only causal effect: technical interfaces, reference context and source-validation procedures also changed. Incomplete results are retained as missing.",
    knitr::kable(rows))
}
