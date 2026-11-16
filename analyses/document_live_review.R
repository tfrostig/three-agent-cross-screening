#' Add an interpretive appendix to a portable copy, preserving the sealed live run.
source("R/bootstrap.R")
source("R/document_pipeline.R")

#' Describe the actual hypothesis families proposed and selected.
#' @param run_dir Completed live run root.
review_family_structure <- function(run_dir) {
  inventory <- read_csv(file.path(run_dir, "agent-methods.csv"))
  scenarios <- read_csv(file.path(run_dir, "scenarios.csv"))
  inventory <- merge(inventory, scenarios[c("id", "regime", "criterion", "m")], by.x = "scenario", by.y = "id", all.x = TRUE)
  inventory <- inventory[inventory$status == "frozen", ]
  groups <- split(inventory, interaction(inventory$regime, inventory$criterion, drop = TRUE))
  do.call(rbind, lapply(groups, function(x) data.frame(regime = x$regime[1], criterion = x$criterion[1],
    proposed_designs = nrow(x), proposed_retaining_all = sum(x$measurements == x$m),
    proposed_empty = sum(x$measurements == 0),
    proposed_one_direction = sum(x$both_directions == 0 & x$measurements > 0),
    proposed_both_directions = sum(x$both_directions == x$measurements & x$measurements > 0),
    proposed_mixed = sum(x$both_directions > 0 & x$both_directions < x$measurements),
    target_uses = sum(x$selected_count), uses_retaining_all = sum(x$selected_count[x$measurements == x$m]),
    uses_one_direction = sum(x$selected_count[x$both_directions == 0 & x$measurements > 0]),
    uses_both_directions = sum(x$selected_count[x$both_directions == x$measurements & x$measurements > 0]))))
}

#' Count true effects whose correct direction was eligible in each selected design.
#' @param run_dir Completed live run root; truth is read only for this post-run diagnostic.
review_direction_eligibility <- function(run_dir) {
  scenarios <- read_csv(file.path(run_dir, "scenarios.csv"))
  rows <- lapply(seq_len(nrow(scenarios)), function(i) {
    scenario <- scenarios[i, ]
    directory <- file.path(run_dir, "scenarios", scenario$id)
    path <- file.path(directory, "selection-decisions.csv")
    if (!file.exists(path)) return(NULL)
    choices <- read_csv(path)
    setting <- readRDS(file.path(run_dir, "private", paste0(scenario$data_id, ".rds")))
    ids <- colnames(setting$observations[[1]]$exposed)
    do.call(rbind, lapply(1:3, function(target) {
      source <- choices$source[choices$target == target]
      if (length(source) != 1 || is.na(source)) return(NULL)
      frozen <- file.path(directory, paste0("agent-", source), "frozen")
      h <- doc_hypotheses(doc_frozen(frozen)$hypotheses)
      truth <- setting$effects[target, ]
      correct <- paste(ids, sign(truth)) %in% paste(h$measurement_id, h$direction)
      data.frame(scenario = scenario$id, regime = scenario$regime, criterion = scenario$criterion,
        target = target, source = source, true_effects = sum(truth != 0),
        correct_direction_eligible = sum(truth != 0 & correct),
        excluded_true_measurements = sum(truth != 0 & !ids %in% h$measurement_id),
        included_only_wrong_direction = sum(truth != 0 & ids %in% h$measurement_id & !correct))
    }))
  })
  do.call(rbind, rows)
}

#' Summarize a diagnostic separately from discovery or power scores.
#' @param eligibility Per-target eligibility counts.
review_eligibility_table <- function(eligibility) {
  fields <- c("true_effects", "correct_direction_eligible", "excluded_true_measurements", "included_only_wrong_direction")
  table <- aggregate(eligibility[fields], eligibility[c("regime", "criterion")], sum)
  table$eligible_fraction <- table$correct_direction_eligible/table$true_effects
  table
}

#' Preserve source failure reasons and explain their consequences for comparison.
#' @param run_dir Original live run directory.
review_failures <- function(run_dir) {
  paths <- list.files(file.path(run_dir, "scenarios"), pattern = "session.json$", recursive = TRUE, full.names = TRUE)
  rows <- lapply(paths, function(path) {
    record <- read_json(path)
    if (record$status != "failed") return(NULL)
    base <- dirname(dirname(path))
    data.frame(scenario = basename(dirname(base)), source = basename(base),
      reason = record$error %||% "Unspecified; inspect audit", stringsAsFactors = FALSE)
  })
  failures <- do.call(rbind, rows)
  if (is.null(failures)) failures <- data.frame(scenario = character(), source = character(), reason = character())
  summary <- read_csv(file.path(run_dir, "summary.csv"))
  incomplete <- summary$id[summary$method == "agent_pooled_select" & summary$complete == 0]
  text <- sprintf("%d source sessions failed. Pooled-agent results are incomplete for %d plannable scenario%s; aggregate scores remain missing and are excluded from paired comparisons. Standard results for those settings remain in summary.csv. Surviving candidates were used where possible, with degraded comparisons flagged in selected-algorithms.csv. Failed sessions were not restarted with fresh budgets.",
    nrow(failures), length(incomplete), if (length(incomplete)==1) "" else "s")
  list(table = failures, lines = c(text, if (nrow(failures)) knitr::kable(failures)))
}

#' Lead with the actual comparison and the main ways agents changed the analysis.
#' @param run_dir Completed live run root.
#' @param structure Proposed family counts.
review_findings <- function(run_dir, structure) {
  summary <- read_csv(file.path(run_dir, "summary.csv"))
  pairs <- doc_pairs(summary)
  comparisons <- lapply(c("FDR", "FWER"), function(criterion) {
    x <- pairs[pairs$criterion == criterion, ]
    sprintf("%s settings: across %d complete paired scenarios, agents produced %d true replicability discoveries versus %d with standard Welch. Study-count recovery was higher in %d, tied in %d and lower in %d scenarios.",
      criterion, nrow(x), sum(x$agent_true_rep), sum(x$standard_true_rep),
      sum(x$recovery_difference > 1e-12), sum(abs(x$recovery_difference) <= 1e-12),
      sum(x$recovery_difference < -1e-12))
  })
  family <- sprintf("%d of %d frozen designs retained every measurement in their declared hypothesis family. Their main adaptations were source-derived directions, weights, error-budget allocation or ordering, rather than removal of measurements. Retaining a family does not ensure every member is reached by a sequential procedure or receives useful testing weight.",
    sum(structure$proposed_retaining_all), sum(structure$proposed_designs))
  c("### What the run shows", unlist(comparisons),
    "Interpret discovery yield and recovery separately. The totals describe the saved settings; large measurement families contribute more counts, while recovery comparisons give each scenario equal weight.",
    "### What the agents changed", family,
    "Inspect the submitted tests, weighting and ordering in the original explanations and code preserved below. Reproducible code and detailed rationales establish an auditable analysis, not that the chosen procedure is optimal.")
}

#' Compare secondary routes on the same fully paired settings as the main report.
#' @param run_dir Completed live run root.
review_secondary <- function(run_dir) {
  summary <- read_csv(file.path(run_dir, "summary.csv"))
  summary <- summary[summary$id %in% doc_pairs(summary)$id & summary$complete == 1, ]
  fields <- c("claimed_studies", "correct_lower_bound_credit", "global_discoveries", "true_global_discoveries",
    "replicability_discoveries", "true_replicability_discoveries")
  groups <- c("regime", "criterion", "method")
  totals <- aggregate(summary[fields], summary[groups], sum)
  recovery <- aggregate(summary["study_count_recovery"], summary[groups], mean)
  merge(totals, recovery, by = groups)
}

#' Format secondary totals without conflating them with primary comparisons.
#' @param secondary Aggregated scores for all four routes.
review_secondary_text <- function(secondary) {
  labels <- c(agent_pooled_select = "Pooled agents", agent_cycle = "Cyclic agents",
    welch_two_sided = "Standard Welch", oracle_z_secondary = "Oracle reference")
  table <- data.frame(Regime = secondary$regime, Criterion = secondary$criterion,
    Approach = unname(labels[secondary$method]), Claims = secondary$claimed_studies,
    Credit = secondary$correct_lower_bound_credit,
    Global = sprintf("%d (%d)",secondary$global_discoveries,secondary$true_global_discoveries),
    Replicability = sprintf("%d (%d)",secondary$replicability_discoveries,secondary$true_replicability_discoveries),
    Recovery = round(secondary$study_count_recovery,4))
  c("## Appendix: secondary route comparisons",
    "All four routes below use the same complete agent-versus-standard settings. Claims and credit are sums; global and replicability columns show total (true). Recovery is the equal-scenario mean. The oracle uses unavailable truth and is only a reference. Exact six-count totals are also in all-route-comparisons.csv; individual scenarios remain in summary.csv.",
    knitr::kable(table))
}

#' Explain all compared procedures and distinguish correct eligibility from actual power.
#' @param structure Actual source-family counts.
#' @param eligibility Aggregated diagnostic.
review_interpretation <- function(structure, eligibility) {
  proposed <- structure[c("regime", "criterion", "proposed_designs", "proposed_retaining_all",
    "proposed_one_direction", "proposed_both_directions", "proposed_mixed", "proposed_empty")]
  names(proposed) <- c("Regime", "Criterion", "N", "Retain all", "One sign", "Both signs", "Mixed", "Empty")
  selected <- structure[c("regime", "criterion", "target_uses", "uses_retaining_all", "uses_one_direction", "uses_both_directions")]
  names(selected) <- c("Regime", "Criterion", "Target uses", "Retain all", "One sign", "Both signs")
  selected$Other <- selected[[3]]-selected[[5]]-selected[[6]]
  c("## Appendix: interpretation of the submitted designs",
    "The following summaries describe the frozen live designs, separately counting proposed source designs and selected target uses. They do not re-fit or change any procedure.",
    "Proposed source designs:", knitr::kable(proposed),
    "Selected target uses (a design may serve more than one target):", knitr::kable(selected),
    "### Which true effects could the selected designs discover in the correct direction?",
    "This is an eligibility diagnostic, not observed power or a new primary endpoint. A true target effect is eligible only when the selected frozen family contains its correct direction. The fraction below divides eligible true study–measurement effects by all true effects in the corresponding evaluated targets. True effects can be excluded entirely or retained only with the opposite sign. Merely retaining every measurement does not ensure correct-direction eligibility. The conventional two-sided comparator examines every measurement without committing to a source-selected sign.",
    knitr::kable(eligibility),
    "An eligibility loss is a structural limitation on correct directional discovery. When eligibility is high but observed recovery is lower, weights, testing choices, multiplicity allocation and realized sampling variation may matter. These diagnostics do not isolate the causal contribution of each design choice.",
    "### Interpretation of the agents' explanations",
    "The original explanations are scientific rationales, not transcripts of internal deliberation. A reproducible numerical rule is not, by itself, evidence that the rule maximizes transferable discoveries. Empirical-Bayes models, cutoffs and budget splits should be read with their stated working assumptions. Source diagnostics do not establish unseen-target tail behavior or dependence conditions. The software verified executable contracts, not the truth of every claimed error-control argument.",
    "## Appendix: the different analysis routes",
    "| Approach | How the target analysis is chosen | What observations confirm discoveries? |",
    "|:--|:--|:--|",
    "| Pooled agent selection | Compare the other two frozen algorithms on their pooled data; more unique discovered measurements wins, ties use smaller source index | Held-out study only, at 0.05/3 |",
    "| Original agent cycle | Fixed routes 1 to 2, 2 to 3, and 3 to 1, without pooled algorithm selection | Each receiving study only, at 0.05/3 |",
    "| Standard comparator | Two-sided Welch on every measurement; Holm for FWER or BH for FDR separately within each study | All three studies analyzed separately, each at 0.05/3, then aggregated |",
    "| Oracle reference | Known-variance z-tests using the generator's unit variances and true effect signs; Holm/BH | Same individual studies; this truth-informed reference is not available to agents or an ordinary analyst |",
    "### Simulation context for interpreting these methods",
    "m is the number of measurements, n is the sample size per exposed/control arm within each study, and c is the sample-size planning target (0.2, 0.6 or 0.9), not the FDR level or the recovery score. The dense regime has 60% all-null outcomes and the sparse regime 90%; the regimes also change how often effects are shared across studies. Active magnitudes are drawn separately across studies, rather than imposing a common source-to-target magnitude ranking. Strong source evidence can inform whether effects are present, but transferring its magnitude ranking is an additional working assumption. This is a possible mechanism to inspect, not a causal explanation isolated by this experiment. All nonzero generated effects are positive; agents were not told this.",
    "The oracle is a truth-informed reference, not a pointwise upper bound on realized discoveries.",
    "### Scope of error-control claims",
    "The FWER/FDR label specifies the requested study-level criterion. Replicability counts follow the document\'s agreed aggregation unchanged. Study-level FDR control alone does not establish FDR control for the collection of replicability claims; dedicated replicability procedures address that separate problem. See [Bogomolov and Heller (2023), Section 5.1](https://arxiv.org/pdf/2210.00522). These realized tables do not independently certify such a guarantee.",
    "All routes use the same prescribed discovery and count summaries. Pooled selection counts are exploratory. Standard two-sided and agent directional claims have different content, so sign errors are not assigned to the standard comparator. Historical comparisons use matching dense data only and compare workflows, not a prompt-only causal effect.")
}

#' Produce a reviewed portable report without rewriting the sealed original run or ZIPs.
#' @param run_dir Completed live run root.
#' @param destination New directory under deliverables.
review_live_report <- function(run_dir, destination) {
  run_dir <- normalizePath(run_dir)
  stopifnot(!isTRUE(read_json(file.path(run_dir, "run.json"))$offline), doc_package_valid(run_dir))
  if (dir.exists(destination)) stop("Reviewed report destination exists")
  structure <- review_family_structure(run_dir)
  detail <- review_direction_eligibility(run_dir)
  eligibility <- review_eligibility_table(detail)
  secondary <- review_secondary(run_dir)
  marker <- read_json(file.path(run_dir, "package-complete.json"))
  staging <- ensure_dir(tempfile("review-copy-"))
  on.exit(unlink(staging, recursive = TRUE))
  utils::unzip(marker$share, exdir = staging)
  ensure_dir(dirname(destination))
  stopifnot(file.rename(file.path(staging, basename(run_dir)), destination))
  destination <- normalizePath(destination)
  lines <- readLines(file.path(destination, "report.Rmd"), warn = FALSE)
  lines <- review_main_layout(lines, run_dir)
  position <- which(lines == "## Compared procedures")[1]
  stopifnot(!is.na(position))
  lines <- append(lines, review_findings(run_dir, structure), after = position-1L)
  failures <- review_failures(run_dir)
  position <- which(lines == "## Failures and resource use")[1]
  stopifnot(!is.na(position))
  lines <- append(lines, failures$lines, after = position)
  index <- grep("^## Appendix:", lines)[1]
  if (is.na(index)) index <- length(lines)+1L
  lines <- append(lines, c(review_interpretation(structure, eligibility), review_secondary_text(secondary)), after = index-1L)
  writeLines(review_markdown_spacing(lines), file.path(destination, "report.Rmd"))
  write_csv(structure, file.path(destination, "family-structure.csv"))
  write_csv(detail, file.path(destination, "direction-eligibility.csv"))
  write_csv(failures$table, file.path(destination, "source-failures.csv"))
  write_csv(secondary, file.path(destination, "all-route-comparisons.csv"))
  write_json(list(original_run = run_dir, original_share_sha256 = marker$share_sha256,
    diagnostic = "Post-run truth-based eligibility; no agent feedback, refitting, or new data"), file.path(destination, "review-provenance.json"))
  review_plots(destination, run_dir)
  rmarkdown::render(file.path(destination, "report.Rmd"), quiet = TRUE, envir = new.env(parent = baseenv()))
  review_guide(destination)
  review_package(destination)
}

#' Plot only existing settings, marking genuine zero differences explicitly.
#' @param destination Reviewed report root.
#' @param run_dir Immutable live results root.
review_plots <- function(destination, run_dir) {
  pairs <- doc_pairs(read_csv(file.path(run_dir,"summary.csv")))
  pairs <- pairs[order(pairs$m,pairs$c),]
  labels <- paste0("m=",pairs$m,", c=",pairs$c)
  pairs$setting <- factor(labels,levels=unique(labels))
  plot <- ggplot2::ggplot(pairs,ggplot2::aes(replicability_difference,setting)) +
    ggplot2::geom_vline(xintercept=0,colour="grey50") +
    ggplot2::geom_col(fill="#31688e",orientation="y") +
    ggplot2::geom_point(colour="#18354a",size=2) +
    ggplot2::facet_wrap(ggplot2::vars(regime,criterion),ncol=2,scales="free") +
    ggplot2::labs(x="True replicability discoveries: agents minus standard Welch",y=NULL,
      caption="Dots at zero indicate equal counts. Only complete paired settings are plotted.") +
    ggplot2::theme_minimal(base_size=11)
  ggplot2::ggsave(file.path(destination,"figures","replicability.png"),plot,width=10,height=7,dpi=160)
}

#' Explain the portable bundle without requiring familiarity with the repository.
#' @param destination Reviewed report root.
review_guide <- function(destination) {
  writeLines(c("# Updated-prompt live experiment: directory guide", "",
    "Start with report.html. It contains the findings, matched standard comparisons and expandable original agent explanations. report.Rmd is the editable R Markdown source; it does not require model calls to render.", "",
    "- summary.csv: all scenarios and approaches, including incomplete results. paired-comparisons.csv: complete matched pooled-agent/Welch comparisons only.",
    "- all-route-comparisons.csv: six-count totals and mean recovery for pooled agents, cyclic agents, standard Welch and oracle, restricted to the same complete paired settings.",
    "- agent-index.md and agent-methods.csv: find an agent's original rationale, frozen R code and exact recorded exploration. Proposed designs and selected target uses are counted separately.",
    "- scenarios/<setting>/agent-<1,2,3>/frozen/: analysis.R is the self-contained procedure; report.md is the agent's explanation; exploration.md records executed R and output. Failed sessions retain their audit records but have no accepted frozen design.",
    "- scenarios/<setting>/: selection-candidates.csv and selection-decisions.csv explain each target choice. Method subdirectories contain outcomes.csv, target-results.json and applicable directional metrics. evaluations/ contains execution audits and cache outputs.",
    "- selected-algorithms.csv: source-to-target routing, ties, degraded comparisons and hashes. source-failures.csv and failures.csv distinguish source-session from planning failures. usage.csv and planning.csv contain execution and sample-size details.",
    "- family-structure.csv and direction-eligibility.csv: post-run diagnostics, described in the report; these did not influence agents or selection.",
    "- figures/: exported plots. historical-comparison/: prior-workflow outputs, not current-prompt designs. Prompt previews and provenance record exactly what agents could see.",
    "- SHA256.csv: integrity index for this reviewed bundle. review-provenance.json identifies the immutable original live archive.", "",
    "Raw observations, private truth matrices and mutable workspaces are omitted. The complete local archive preserves reproducibility inputs. Historical runs and their ZIPs were not changed. All results are realized outcomes from one iteration."),
    file.path(destination, "README.md"))
}

#' Package the portable reviewed copy with its own integrity index.
#' @param destination Reviewed report directory.
#' @param archive_name Optional new archive stem to preserve a previously shared ZIP.
review_package <- function(destination, archive_name = basename(destination)) {
  files <- list.files(destination, recursive = TRUE, full.names = TRUE)
  files <- files[!file.info(files)$isdir & basename(files) != "SHA256.csv"]
  write_csv(data.frame(path = substring(files, nchar(destination)+2), sha256 = vapply(files, file_hash, character(1))), file.path(destination, "SHA256.csv"))
  zip <- file.path(project_root, "exports", paste0(archive_name, "-share.zip"))
  if (file.exists(zip)) stop("Reviewed archive exists")
  old <- setwd(dirname(destination))
  on.exit(setwd(old))
  utils::zip(zip, basename(destination), flags = "-qr")
}

#' Keep resource details in appendices and report only observed aggregate usage up front.
#' @param lines Controlled report Markdown; agent-authored appendices are preserved.
#' @param run_dir Original live run root.
review_main_layout <- function(lines, run_dir) {
  lines <- review_recovery_layout(lines, run_dir)
  boundary <- grep("^## Appendix:", lines)[1]
  if (is.na(boundary)) boundary <- length(lines)+1L
  details <- which(lines == "### usage.csv")[1]
  if (!is.na(details) && details < boundary) {
    moved <- lines[seq.int(details, boundary-1L)]
    usage <- read_csv(file.path(run_dir, "usage.csv"))
    timing <- read_json(file.path(run_dir, "run.json"))
    end <- read_json(file.path(run_dir, "completion.json"))
    duration <- as.numeric(difftime(as.POSIXct(end$completed, format="%Y-%m-%dT%H:%M:%SZ", tz="UTC"),
      as.POSIXct(timing$started, format="%Y-%m-%dT%H:%M:%SZ", tz="UTC"), units="mins"))
    concise <- sprintf("Elapsed wall time from launch through evaluation was %.1f hours, with %d recorded model API attempts. Returned-response usage totals %s input tokens and %s output tokens. These token totals may omit usage from failed HTTP attempts. Per-session details and sample-size planning are in the execution appendix.",
      duration/60, sum(usage$physical_api_attempts), format(sum(usage$input_tokens,na.rm=TRUE),big.mark=","),
      format(sum(usage$output_tokens,na.rm=TRUE),big.mark=","))
    lines <- c(lines[seq_len(details-1L)], concise, lines[seq.int(boundary,length(lines))],
      "## Appendix: execution and sample-size planning", moved)
  }
  boundary <- grep("^## Appendix:",lines)[1]
  if (is.na(boundary)) boundary <- length(lines)+1L
  main <- seq_len(boundary-1L)
  labels <- c(agent_pooled_select="Pooled agents",welch_two_sided="Standard Welch",
    study_claims="Study claims",correct_count_credit="Correct count credit",
    global_total_true="Global total (true)",replicability_total_true="Replicability total (true)",
    paired_scenarios="Paired settings",agent_higher="Agent higher",agent_lower="Agent lower",
    mean_difference_percentage_points="Mean change (percentage points)")
  for (name in names(labels)) lines[main] <- gsub(name,labels[[name]],lines[main],fixed=TRUE)
  lines
}

#' Round descriptive differences and remove redundant generated table row names.
#' @param lines Original controlled report Markdown.
#' @param run_dir Live results root.
review_recovery_layout <- function(lines, run_dir) {
  start <- which(lines == "## Paired recovery comparisons")[1]
  end <- grep("^!\\[Paired study-count recovery\\]", lines)[1]
  stopifnot(!is.na(start), !is.na(end), start < end)
  table <- doc_pair_table(doc_pairs(read_csv(file.path(run_dir, "summary.csv"))))
  table$mean_difference_percentage_points <- round(table$mean_difference_percentage_points,2)
  c(lines[seq_len(start)], knitr::kable(table,row.names=FALSE), lines[seq.int(end,length(lines))])
}

#' Separate generated Markdown blocks while leaving original literal agent text intact.
#' @param lines Report text including escaped literal pre blocks.
review_markdown_spacing <- function(lines) {
  output <- character()
  raw <- previous_table <- FALSE
  for (line in lines) {
    if (!raw && line=="" && length(output) && tail(output,1)=="") next
    opening <- grepl("<pre>",line,fixed=TRUE)
    closing <- grepl("</pre>",line,fixed=TRUE)
    table <- !raw && !opening && startsWith(line,"|")
    heading <- !raw && !opening && grepl("^#{1,6} ",line)
    image <- !raw && !opening && startsWith(line,"![")
    boundary <- !raw && (opening || heading || image || table != previous_table)
    if (boundary && length(output) && tail(output,1)!="") output <- c(output,"")
    output <- c(output,line)
    if (heading || image || closing) output <- c(output,"")
    raw <- (raw || opening) && !closing
    previous_table <- table
  }
  stopifnot(!raw)
  output
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  review_live_report(cli_value(args, "--run-dir", "results/document-live-20261115"),
    cli_value(args, "--output", "deliverables/document-live-20261115-reviewed"))
}
