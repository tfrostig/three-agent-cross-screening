#' Build a sequential reader report and indexed supplement from verified live results.
source("analyses/document_live_review.R")

#' Find framework section boundaries outside literal original agent text.
#' @param lines Existing reviewed R Markdown.
reader_sections <- function(lines) {
  starts <- integer()
  raw <- FALSE
  for (i in seq_along(lines)) {
    if (!raw && startsWith(lines[i], "## Appendix:")) starts <- c(starts,i)
    raw <- (raw || grepl("<pre>",lines[i],fixed=TRUE)) && !grepl("</pre>",lines[i],fixed=TRUE)
  }
  stopifnot(!raw,length(starts)>0)
  ends <- c(starts[-1]-1L,length(lines))
  setNames(lapply(seq_along(starts),function(i) lines[seq.int(starts[i]+1L,ends[i])]),
    sub("## Appendix: ","",lines[starts],fixed=TRUE))
}

#' Copy only the existing portable artifacts into a new report version.
#' @param origin Verified portable report directory.
#' @param destination New directory.
reader_copy <- function(origin,destination) {
  if (dir.exists(destination)) stop("Choose a new report directory")
  ensure_dir(destination)
  files <- list.files(origin,recursive=TRUE,full.names=TRUE)
  relative <- substring(files,nchar(origin)+2L)
  keep <- !file.info(files)$isdir & !relative %in% c("report.Rmd","report.html","SHA256.csv")
  for (i in which(keep)) {
    path <- file.path(destination,relative[i])
    ensure_dir(dirname(path))
    stopifnot(file.copy(files[i],path))
  }
  normalizePath(destination)
}

#' Keep Section 3 measure names separate from legacy machine-readable field names.
reader_measure_names <- function() {
  c(claimed_studies="Total number of lower bounds",
    correct_lower_bound_credit="Total number of correct lower bounds",
    global_discoveries="Number of global null discoveries",
    true_global_discoveries="Number of true global null discoveries",
    replicability_discoveries="Number of replicability discoveries",
    true_replicability_discoveries="Number of true replicability discoveries")
}

#' Derive coverage from saved planning and complete paired evaluations.
#' @param directory Portable artifact directory.
reader_coverage <- function(directory) {
  grid<-read_csv(file.path(directory,"scenarios.csv"))
  failed<-read_csv(file.path(directory,"failures.csv"))
  pairs<-read_csv(file.path(directory,"paired-comparisons.csv"))
  text<-sprintf("**%d planned settings → %d plannable → %d complete agent–competitor comparisons.** Failures are retained without redrawing. Primary comparisons use complete pairs only; failure details are in Supplement H.",
    nrow(grid),nrow(grid)-nrow(failed),nrow(pairs))
  groups<-vapply(c("dense","sparse"),function(regime) sprintf("With Π(0, 0, 0) = %s, %d of %d planned settings have complete comparisons.",
    if(regime=="dense") "0.6" else "0.9",sum(pairs$regime==regime),sum(grid$regime==regime)),character(1))
  paste(c(text,groups),collapse="\n\n")
}

#' Describe observed replicability comparisons without embedding saved results in source.
#' @param directory Portable artifact directory.
reader_results_narrative <- function(directory) {
  pairs<-read_csv(file.path(directory,"paired-comparisons.csv"))
  totals<-vapply(c("FDR","FWER"),function(criterion) {
    x<-pairs[pairs$criterion==criterion,]
    sprintf("Across %s settings, agents made **%d true replicability discoveries versus %d** for the competitor.",
      criterion,sum(x$agent_true_rep),sum(x$standard_true_rep))
  },character(1))
  if(!nrow(pairs))return("No complete agent–competitor comparisons are available.")
  extremes<-unique(c(which.max(pairs$replicability_difference),which.min(pairs$replicability_difference)))
  examples<-vapply(extremes,function(i) {
    x<-pairs[i,]
    sprintf("With Π(0, 0, 0) = %s, %s, m=%d and c=%g, the number of true replicability discoveries was %d for agents and %d for the competitor.",
      if(x$regime=="dense") "0.6" else "0.9",x$criterion,x$m,x$c,x$agent_true_rep,x$standard_true_rep)
  },character(1))
  paste(c(totals,examples),collapse="\n\n")
}

#' Describe frozen hypothesis families using the post-run inventory.
#' @param directory Portable artifact directory.
reader_design_narrative <- function(directory) {
  x<-read_csv(file.path(directory,"family-structure.csv"))
  sprintf("Of %d frozen designs, %d retained every outcome. There were %d designs with one direction per retained outcome, %d with both directions throughout, %d mixing these choices, and %d with empty families. Full submitted procedures remain available in the inventory.",
    sum(x$proposed_designs),sum(x$proposed_retaining_all),sum(x$proposed_one_direction),
    sum(x$proposed_both_directions),sum(x$proposed_mixed),sum(x$proposed_empty))
}

#' Count completed source submissions independently of aggregate scenario scores.
#' @param directory Portable artifact directory.
reader_session_summary <- function(directory) {
  x<-read_csv(file.path(directory,"agent-methods.csv"))
  sprintf("Of %d agent sessions, %d produced frozen designs and %d failed. Incomplete aggregate results remain missing; original failure reasons are in Supplement H.",
    nrow(x),sum(x$status=="frozen"),sum(x$status=="failed"))
}

#' Derive timing and known returned-response usage without reading credentials.
#' @param directory Portable artifact directory.
reader_resource_text <- function(directory) {
  usage<-read_csv(file.path(directory,"usage.csv"))
  run<-read_json(file.path(directory,"run.json"))
  end<-read_json(file.path(directory,"completion.json"))
  hours<-as.numeric(difftime(as.POSIXct(end$completed,tz="UTC",format="%Y-%m-%dT%H:%M:%SZ"),
    as.POSIXct(run$started,tz="UTC",format="%Y-%m-%dT%H:%M:%SZ"),units="hours"))
  sprintf("Elapsed wall time through evaluation was %.1f hours, with %d physical API attempts and known returned-response totals of %s input tokens and %s output tokens. Failed HTTP attempts may incur usage absent from these totals. Failed or interrupted sessions do not silently receive a fresh budget.",
    hours,sum(usage$physical_api_attempts),format(sum(usage$input_tokens,na.rm=TRUE),big.mark=",",trim=TRUE),
    format(sum(usage$output_tokens,na.rm=TRUE),big.mark=",",trim=TRUE))
}

#' Explain why inventory totals can include valid targets from incomplete scenarios.
#' @param directory Portable artifact directory.
reader_inventory_context <- function(directory) {
  x<-read_csv(file.path(directory,"agent-methods.csv"))
  pairs<-read_csv(file.path(directory,"paired-comparisons.csv"))
  sprintf("This inventory covers %d frozen designs. Selected-use and eligibility diagnostics retain available target evaluations from incomplete settings as well. Primary comparisons use only the %d fully complete paired settings.",
    sum(x$status=="frozen"),nrow(pairs))
}

#' Compare the two procedures in explicit columns for each probability/criterion group.
#' @param directory Portable artifact directory.
reader_primary <- function(directory) {
  totals <- read_csv(file.path(directory,"all-route-comparisons.csv"))
  fields <- names(reader_measure_names())
  labels <- unname(reader_measure_names())
  groups <- data.frame(regime=c("dense","sparse","dense","sparse"),criterion=c("FDR","FDR","FWER","FWER"))
  pairs <- read_csv(file.path(directory,"paired-comparisons.csv"))
  lines <- character()
  for (i in 1:4) {
    g <- groups[i,]
    rows <- totals[totals$regime==g$regime & totals$criterion==g$criterion,]
    a <- rows[rows$method=="agent_pooled_select",fields]
    b <- rows[rows$method=="welch_two_sided",fields]
    n <- sum(pairs$regime==g$regime & pairs$criterion==g$criterion)
    name <- sprintf("### Π(0, 0, 0) = %s; %s — %d complete settings",if(g$regime=="dense") "0.6" else "0.9",g$criterion,n)
    table <- data.frame(Measure=labels,Agents=as.integer(a[1,]),
      `Competitor (Welch)`=as.integer(b[1,]),check.names=FALSE)
    lines <- c(lines,name,knitr::kable(table,row.names=FALSE,format.args=list(big.mark=",")))
  }
  lines
}

#' Display mean recovery and paired wins with explicit units.
#' @param directory Portable artifact directory.
reader_recovery <- function(directory) {
  pairs <- read_csv(file.path(directory,"paired-comparisons.csv"))
  rows <- lapply(split(pairs,interaction(pairs$regime,pairs$criterion,drop=TRUE)),function(x)
    data.frame(`Π(0,0,0)`=if(x$regime[1]=="dense") "0.6" else "0.9",Criterion=x$criterion[1],
      Agents=sprintf("%.1f%%",100*mean(x$agent_recovery)),Welch=sprintf("%.1f%%",100*mean(x$standard_recovery)),
      Difference=sprintf("%+.2f pp",100*mean(x$recovery_difference)),
      `Higher / tied / lower`=sprintf("%d / %d / %d",sum(x$recovery_difference>1e-12),
        sum(abs(x$recovery_difference)<=1e-12),sum(x$recovery_difference< -1e-12)),check.names=FALSE))
  knitr::kable(do.call(rbind,rows),row.names=FALSE)
}

#' Show every setting directly rather than asking readers to decode a plot.
#' @param directory Portable artifact directory.
reader_setting_comparison <- function(directory) {
  x <- read_csv(file.path(directory,"paired-comparisons.csv"))
  x <- x[order(x$criterion,x$regime,x$m,x$c),]
  table <- data.frame(`Π(0,0,0)`=ifelse(x$regime=="dense","0.6","0.9"),Criterion=x$criterion,
    m=x$m,c=x$c,Agents=x$agent_true_rep,Welch=x$standard_true_rep,
    Difference=sprintf("%+d",x$replicability_difference),check.names=FALSE)
  c("### Per-setting replicability results {#per-setting-replicability-results}",
    "Each row is one completed setting. Agents and Welch columns give the number of true replicability discoveries: outcomes discovered in at least two subsets that truly have effects in at least two subgroups. Difference = agents minus the competitor; positive values favor agents. Π(0,0,0) is the probability of no effect in any subgroup.",
    knitr::kable(table,row.names=FALSE))
}

#' Retain the exact generator and planning details outside the main narrative.
reader_simulation <- function() {
  c("### Generator and sample-size planning",
    "Using the specification's notation, the exposed vector is Y_j ~ N_m(η_j,Σ) and the unexposed vector X ~ N_m(0,Σ), with Σ=diag(1,…,1). For outcome i, h_i=(h_1i,h_2i,h_3i) gives the three hypothesis states. If h_ji=0, η_ji=0; otherwise η_ji is drawn from the absolute value of N(Δ,τ²), with Δ=1 and τ²=1. Active magnitudes are drawn separately across subgroups. Observations are independent across rows, measurements and subsets conditional on the effects; each subset has its own independent control sample. Agents were not told normality, Σ or that all nonzero effects are positive.",
    "| Three-subgroup state | Π(0,0,0)=0.6 | Π(0,0,0)=0.9 |",
    "|:--|--:|--:|","| 000 | 0.60 | 0.90 |","| 111 | 0.10 | 0.05 |",
    "| Each of 001, 010, 011, 100, 101, 110 | 0.05 | 0.05/6 |",
    "The regimes change both sparsity and sharing. Active magnitudes have no imposed common ranking across studies. Each (regime, m, c) dataset setting has its own draw; c comparisons are not a paired sample-size experiment. Matching m=100 FWER/FDR settings reuse observations, with separate agent sessions.",
    "For n exposed and n unexposed observations in each subset, the specification's planning formula is",
    "\\[\\Pi_j(n)=\\frac{1}{|\\{i:\\eta_{ji}>0\\}|}\\sum_{i:\\eta_{ji}>0}\\left[1-\\Phi\\left(z_{1-\\alpha/m}-\\sqrt{n/2}\\,\\eta_{ji}\\right)\\right].\\]",
    "Choose the smallest integer n with min_j Π_j(n)>c and verify failure at n−1. Planning uses α/m with α=0.05; application uses α/3. If a subgroup has no nonzero effects, its planning power is undefined and the setting remains failed without redrawing. Limits are n≤100,000 and 6nm≤20 million stored observation cells. Existing datasets and RNG streams were preserved and hash-verified. Actual n ranges from 6 to 9,525; every value and minimality check is in Appendix H. The specification lists c=0.2 and 0.6; c=0.9 was an agreed addition for this run.")
}

#' Explain responsibilities and checks without changing any agent instruction.
reader_architecture <- function() {
  c("### Agent and framework responsibilities",
    "PydanticAI manages independent Python sessions; statistical generation, selection, scoring and reporting run in trusted host R. The exact scientific block is supplied once as instructions=. The user message supplies only m, exposed n, unexposed n, criterion and numeric family level. There is no additional custom system/developer scientific prompt or reference brief. Tool descriptions and schemas supply the technical contract; Appendix C preserves them exactly.",
    "Agents use run_r(code), write_artifact_file(path,content), and the structured finalize_design(script_file,report_file) submission. Exploratory calls preload only that session's matrices; files persist in its workspace, while R variables do not persist between calls. analysis.R exports fixed hypotheses (measurement names and directions) and analyze(exposed,unexposed,alpha). report.md explains source evidence, hypothesis choices, the procedure, and assumptions. The framework creates exploration.md directly from executed calls and outputs.",
    "Before freezing, deterministic checks verify regular permitted files, R syntax, hypothesis names/directions/duplicates, function arguments and nonempty required Markdown sections. Definitions are inspected in a restricted container without observations; analyze() is not called during submission validation. Structural errors can be repaired within budget; no performance feedback is returned. Read-only frozen artifacts and completion markers record hashes.",
    "After execution, checks verify artifact integrity, exact required result rows, finite raw/adjusted values in [0,1], rejection decisions at the supplied level, directional/outcome agreement, and adjusted value 1 with no rejection for nonselected outcomes. The framework neither replaces an agent's correction nor invents its rule for combining directions. These are contract checks, not proofs of statistical validity.",
    "Each exploration, inspection and uncached evaluation uses a fresh restricted R container: no network, credentials, generator, truth, sibling workspace or Docker socket; read-only inputs and bounded scratch/output. Sessions have separate histories, dependencies, workspaces and audits. If one pooled candidate fails, the survivor is used and the comparison flagged; if both fail, the target is missing. Missing targets make aggregate scenario scores incomplete.",
    "| Limit | Value |","|:--|:--|","| Physical API attempts per session | 16, including transport retries |",
    "| Output tokens per response | 8,192 |","| Exploratory R calls / all tool calls | 12 / 32 |",
    "| Structural repair attempts | 2 |","| API timeout / transient retries | 120 seconds / at most 2 per request, within total budget |",
    "| R execution | 60 seconds, 2 GiB, 1 CPU, bounded processes and output |",
    "Safe checkpoints preserve partial histories and known usage. Committed sessions and complete evaluations are reused only after identity/hash checks; failed or interrupted sessions do not silently receive fresh budgets. No new model calls were made to restructure these documents.")
}

#' Collect every setting and diagnostic through a compact linked index.
#' @param directory Portable artifact directory.
reader_results_index <- function(directory) {
  s <- read_csv(file.path(directory,"scenarios.csv"))
  links <- lapply(seq_len(nrow(s)),function(i) {
    base <- paste0("scenarios/",s$id[i],"/")
    present <- file.exists(file.path(directory,base,"scenario-summary.csv"))
    data.frame(Setting=s$id[i],Summary=if(present) sprintf("[Scores](%sscenario-summary.csv)",base) else "Planning failed",
      Agents=if(present) sprintf("[Outcomes](%sagent_pooled_select/outcomes.csv)",base) else "—",
      Welch=if(present) sprintf("[Outcomes](%swelch_two_sided/outcomes.csv)",base) else "—",check.names=FALSE)
  })
  c("[summary.csv](summary.csv) includes every scenario/method and explicit incomplete scores. [paired-comparisons.csv](paired-comparisons.csv) restricts comparisons to complete pairs. [all-route-comparisons.csv](all-route-comparisons.csv) aggregates all four routes on the same matched settings.",
    "Stored scenario identifiers use dense for Π(0,0,0)=0.6 and sparse for Π(0,0,0)=0.9; these identifiers and CSV field names remain unchanged for provenance. [specification-terms.csv](specification-terms.csv) maps the six original measure names to their stored fields.",
    "Outcome tables contain true and claimed study counts, wrong-study counts, recovery, overclaims, combined global/replicability values, per-study adjusted values and displayed raw directional results. Method directories also hold target-results.json and directional-metrics.csv where applicable. Directional metrics give discoveries, false discoveries, FDP and directional power per target; they do not assign signs to the two-sided comparator.",
    "These are additional error diagnostics: a wrong-subset discovery occurs where the true effect is zero; a false directional discovery has claimed direction × true effect ≤0. Directional FDP is false directional discoveries divided by max(1,total directional discoveries); directional power is correctly discovered nonzero outcomes divided by the number of nonzero outcomes in that subset. They are separate from the six measures in Section 3.",
    "[agent-methods.csv](agent-methods.csv) distinguishes proposed designs and selected target uses. [family-structure.csv](family-structure.csv) and [direction-eligibility.csv](direction-eligibility.csv) are post-run diagnostics, not additional agent input or optimization criteria.",
    reader_setting_comparison(directory),
    knitr::kable(do.call(rbind,links),row.names=FALSE),
    "Raw observations, private truth matrices and mutable workspaces are omitted from this shareable bundle. Dataset and artifact hashes remain available. The complete original local archive preserves the raw reproducibility inputs. [README.md](README.md) is the directory guide.")
}

#' Compare additional procedures using the specification's original six names.
#' @param directory Portable artifact directory.
reader_secondary_spec <- function(directory) {
  x <- read_csv(file.path(directory,"all-route-comparisons.csv"))
  groups <- split(x,interaction(x$regime,x$criterion,drop=TRUE))
  labels <- c(agent_pooled_select="Agents (winner design)",agent_cycle="Agents (original cycle)",
    welch_two_sided="Competitor (Welch)",oracle_z_secondary="Oracle (uses truth)")
  lines <- "All four procedures use the same complete settings. The original cycle and oracle are additional comparisons; the oracle uses information unavailable to the agents or an ordinary analyst. Table columns retain the specification's six measure names."
  for (g in groups) {
    name <- sprintf("### Π(0,0,0)=%s; %s",if(g$regime[1]=="dense") "0.6" else "0.9",g$criterion[1])
    table <- data.frame(Procedure=unname(labels[g$method]),g[names(reader_measure_names())],check.names=FALSE)
    names(table)[-1] <- unname(reader_measure_names())
    lines <- c(lines,name,knitr::kable(table,row.names=FALSE))
  }
  lines
}

#' Preserve the separately agreed recovery score without attributing it to the PDF.
#' @param directory Portable artifact directory.
reader_additional <- function(directory) {
  pairs<-read_csv(file.path(directory,"paired-comparisons.csv"))
  delta<-pairs$recovery_difference
  c("## I. Additional study-count recovery {#i-additional-study-count-recovery}",
    "This score was agreed after the simulation specification. It is not one of Section 3's six measures of power, and its name is not terminology from that document.",
    "For each outcome with r>0 false null hypotheses, use L/r if its lower bound L≤r and zero if L>r. Average equally over those outcomes. Outcomes null in all subgroups are excluded from this mean; their discoveries are reported separately. A true count of 3 and lower bound of 2 earns 2/3; a true count of 2 and lower bound of 3 earns zero. The score checks counts and can reward claims in the wrong subsets or directions.",
    "The following table averages scenario scores equally within each probability/criterion group. Difference is agents minus the competitor in percentage points; the final column counts settings with higher, tied and lower agent scores.",
    reader_recovery(directory),
    sprintf("Agents had higher recovery in %d settings, tied in %d and lower in %d. True replicability totals sum outcomes; the additional recovery score equally weights normalized lower bounds and penalizes overclaims. Results for the original cycle and oracle are retained in all-route-comparisons.csv.",
      sum(delta>1e-12),sum(abs(delta)<=1e-12),sum(delta< -1e-12)))
}

#' Replace previous framework labels while preserving literal original agent content.
#' @param lines Generated report or supplement lines.
reader_document_terms <- function(lines) {
  terms <- c("Correct lower-bound credit"="Total number of correct lower bounds",
    "correct lower-bound credit"="total number of correct lower bounds",
    "Study discoveries"="Total number of lower bounds","study discoveries"="total number of lower bounds",
    "True global discoveries"="Number of true global null discoveries",
    "Global discoveries"="Number of global null discoveries",
    "global discoveries"="global null discoveries","global discovery"="global null discovery",
    "Standard comparator"="Competitor that does not use agents")
  raw <- FALSE
  for (i in seq_along(lines)) {
    opening <- grepl("<pre>",lines[i],fixed=TRUE)
    if (!raw && !opening && !startsWith(lines[i],"Stored scenario identifiers")) {
      for (term in names(terms)) lines[i] <- gsub(term,terms[[term]],lines[i],fixed=TRUE)
      table <- startsWith(lines[i],"|")
      lines[i] <- gsub("\\bdense\\b",if(table) "0.6" else "Π(0,0,0)=0.6",lines[i])
      lines[i] <- gsub("\\bsparse\\b",if(table) "0.9" else "Π(0,0,0)=0.9",lines[i])
      if(table) lines[i] <- gsub("Regime","Π(0,0,0)",lines[i],fixed=TRUE)
    }
    raw <- (raw || opening) && !grepl("</pre>",lines[i],fixed=TRUE)
  }
  stopifnot(!raw)
  lines
}

#' Reorder all prior appendix sections while preserving original literal content.
#' @param sections Named existing appendix bodies.
#' @param directory Portable artifact directory.
reader_supplement <- function(sections,directory) {
  need <- c("measures and interpretation","the different analysis routes","exact scientific prompt",
    "complete model-visible technical instructions","interpretation of the submitted designs",
    "representative hypothesis choices and code","proposed and selected designs","selected target algorithms",
    "secondary route comparisons","matched historical live-workflow comparison","execution and sample-size planning")
  stopifnot(all(need %in% names(sections)))
  c("---","title: 'Supplement: methods, agent records and complete results'","output:",
    "  html_document:","    toc: true","    toc_depth: 2","---","",
    "[Return to the main report](report.html). This supplement retains the original agent wording and complete numerical records. Agent text is displayed literally and is never executed during rendering.",
    "## A. Measures and worked examples {#a-measures-and-worked-examples}",readLines("docs/document-metrics.md",warn=FALSE)[-1],
    "### Mapping to saved numerical results",knitr::kable(data.frame(
      `Name in the specification`=unname(reader_measure_names()),`CSV field`=names(reader_measure_names()),check.names=FALSE),row.names=FALSE),
    "## B. Simulation and workflow {#b-simulation-and-workflow}",reader_simulation(),reader_architecture(),sections[[need[2]]],
    "## C. Exact instructions and interfaces {#c-exact-instructions-and-interfaces}",
    "### Scientific prompt",sections[[need[3]]],"### Complete model-visible technical record",sections[[need[4]]],
    "## D. Agent methods, code and rationales {#d-agent-methods-code-and-rationales}",
    reader_inventory_context(directory),
    "### Proposed families and post-run diagnostics",sections[[need[5]]],
    "### Representative code and explanations",sections[[need[6]]],
    "### All proposed designs and original agent reports",sections[[need[7]]],
    "## E. Selection and secondary comparisons {#e-selection-and-secondary-comparisons}",
    "### Selection rule and every selected source",sections[[need[8]]],
    "### Six specification measures for all procedures",reader_secondary_spec(directory),
    "## F. Detailed results and file guide {#f-detailed-results-and-file-guide}",reader_results_index(directory),
    "## G. Historical comparison {#g-historical-comparison}",
    "This is an additional comparison using the separately agreed study-count recovery score (Supplement I), not one of the specification's six measures.",sections[[need[10]]],
    "## H. Execution, failures and planning {#h-execution-failures-and-planning}",reader_failures(directory),sections[[need[11]]],
    reader_additional(directory))
}

#' Explain failed settings and preserve their original records.
#' @param directory Portable artifact directory.
reader_failures <- function(directory) {
  planning <- read_csv(file.path(directory,"failures.csv"))
  sources <- read_csv(file.path(directory,"source-failures.csv"))
  c(reader_coverage(directory),reader_session_summary(directory),
    "Available target evaluations are preserved for incomplete scenarios, but aggregate agent scores remain missing. Baseline results are retained for plannable settings. The following tables provide the original failure reasons.",
    "Planning failures:",knitr::kable(planning,row.names=FALSE),"Source-session failures:",knitr::kable(sources,row.names=FALSE),
    reader_resource_text(directory))
}

#' Render an editable main report and complete supplement without live calls.
#' @param directory Portable artifact directory.
reader_main <- function(directory) {
  main <- paste(readLines("analyses/document-reader-template.md",warn=FALSE),collapse="\n")
  replacements<-list(PRIMARY_TABLE=reader_primary(directory),COVERAGE=reader_coverage(directory),
    RESULTS_NARRATIVE=reader_results_narrative(directory),DESIGN_NARRATIVE=reader_design_narrative(directory),
    SESSION_SUMMARY=reader_session_summary(directory))
  for(name in names(replacements)) main<-gsub(paste0("{{",name,"}}"),paste(replacements[[name]],collapse="\n"),main,fixed=TRUE)
  if(grepl("{{",main,fixed=TRUE))stop("Unresolved report template marker")
  review_markdown_spacing(strsplit(main,"\n",fixed=TRUE)[[1]])
}

#' Give the bundle one authoritative entry point and directory map.
#' @param directory Portable artifact directory.
reader_guide <- function(directory) {
  writeLines(c("# Start here","",
    "Open report.html for the sequential main report using Section 3's six original measure names. Open supplement.html for appendices A–I and the full original records. Supplement I contains a score agreed later; it is not a measure named in the specification.","",
    "| File or directory | Contents |","|:--|:--|",
    "| report.Rmd, supplement.Rmd | Editable R Markdown sources; rendering requires no model calls |",
    "| supplement.html, Appendix D | Original agent reports, representative code, and links to frozen analyses and exploration |",
    "| scenarios/<setting>/agent-<1,2,3>/frozen/ | analysis.R: procedure; report.md: agent rationale; exploration.md: exact executed R and outputs; frozen.json/complete.json: integrity metadata |",
    "| scenarios/<setting>/<method>/ | outcomes.csv: full measurement tables; target-results.json: saved results; directional-metrics.csv where applicable |",
    "| scenarios/<setting>/selection-*.csv and evaluations/ | Candidate counts, routing, ties, degraded comparisons, execution audits and caches |",
    "| summary.csv | All scenario/method scores, including explicit incomplete results |",
    "| specification-terms.csv, specification-provenance.json | Original six measure names mapped to unchanged CSV fields; source document identity |",
    "| paired-comparisons.csv, all-route-comparisons.csv | Complete primary pairs and matched aggregates for pooled/cyclic agents, Welch and oracle |",
    "| agent-index.md, agent-methods.csv | Original records and inventory separating proposed designs from selected uses |",
    "| selected-algorithms.csv | Source chosen for every target, ties, status and hashes |",
    "| family-structure.csv, direction-eligibility.csv | Post-run diagnostics; partial valid target evaluations are included |",
    "| failures.csv, source-failures.csv, usage.csv, planning.csv | Planning failures, source timeouts, timing/API usage and sample-size checks |",
    "| historical-comparison/ | Prior-workflow results, kept separate from current-prompt findings |",
    "| figures/ | Earlier plots retained as records; the revised documents use comparison tables |",
    "| prompt-preview.md, run.json, datasets.json, *provenance.json | Model-visible instructions, run/input identities and document provenance |",
    "| SHA256.csv | Integrity index for this portable bundle |","",
    "Raw observations, private truth matrices and mutable workspaces are omitted. Original simulation results, agent artifacts and earlier report versions remain unchanged. All scientific results are realized outcomes from one iteration."),
    file.path(directory,"README.md"))
}

#' Render an editable main report and complete supplement without live calls.
#' @param origin Existing verified portable report.
#' @param destination New portable report version.
reader_build <- function(origin,destination) {
  origin <- normalizePath(origin,mustWork=TRUE)
  sections <- reader_sections(readLines(file.path(origin,"report.Rmd"),warn=FALSE))
  destination <- reader_copy(origin,destination)
  supplement <- reader_supplement(sections,destination)
  writeLines(reader_main(destination),file.path(destination,"report.Rmd"))
  writeLines(review_markdown_spacing(reader_document_terms(supplement)),file.path(destination,"supplement.Rmd"))
  for (name in c("report.Rmd","supplement.Rmd"))
    rmarkdown::render(file.path(destination,name),quiet=TRUE,envir=new.env(parent=baseenv()))
  reader_guide(destination)
  write_csv(data.frame(specification_name=unname(reader_measure_names()),csv_field=names(reader_measure_names())),
    file.path(destination,"specification-terms.csv"))
  write_json(list(source=read_json("prompts/system.provenance.json"),measures_section="3",
    additional_measure="Study-count recovery was agreed later; see Supplement I"),file.path(destination,"specification-provenance.json"))
  write_json(list(origin=origin,change="Document structure and presentation only; numerical results, prompts and agent artifacts unchanged"),
    file.path(destination,"reader-provenance.json"))
  review_package(destination)
  cat("Main report, complete supplement and indexed shareable ZIP created at",destination,"\n")
}

if (sys.nframe()==0L) {
  args <- commandArgs(trailingOnly=TRUE)
  reader_build(cli_value(args,"--source","deliverables/document-live-20261115-final"),
    cli_value(args,"--output","deliverables/document-live-20261115-guide"))
}
