#' Static per-setting reports covering the full Cartesian index without new experiments.

#' Enumerate every combination of configured factor levels, including unplanned cells.
#' @param config Saved run configuration.
setting_cartesian_grid <- function(config) {
  grid <- expand.grid(regime=names(config$regimes),criterion=c("FWER","FDR"),
    m=as.integer(config$measurements),c=as.numeric(config$power_targets),stringsAsFactors=FALSE)
  grid <- grid[order(match(grid$regime,names(config$regimes)),
    match(grid$criterion,c("FWER","FDR")),grid$m,grid$c),]
  grid$id <- sprintf("%s_%s_m%d_c%02d",grid$regime,tolower(grid$criterion),grid$m,as.integer(round(100*grid$c)))
  grid$data_id <- sprintf("%s_m%d_c%02d",grid$regime,grid$m,as.integer(round(100*grid$c)))
  grid$pi000 <- vapply(grid$regime,function(x) as.numeric(config$regimes[[x]][["000"]]),numeric(1))
  rownames(grid) <- NULL
  grid
}

#' Join coverage and planning status without converting absent results to zeros.
#' @param directory Portable result directory.
setting_result_data <- function(directory) {
  config <- read_json(file.path(directory,"run.json"))$config
  grid <- setting_cartesian_grid(config)
  planned <- read_csv(file.path(directory,"scenarios.csv"))
  failures <- read_csv(file.path(directory,"failures.csv"))
  planning <- read_csv(file.path(directory,"planning.csv"))
  summary <- read_csv(file.path(directory,"summary.csv"))
  methods <- c("agent_pooled_select","agent_cycle","welch_two_sided","oracle_z_secondary")
  grid$planned <- grid$id %in% planned$id
  grid$n_per_arm <- planning$n[match(grid$data_id,planning$data_id)]
  grid$status <- ifelse(grid$planned,"incomplete_evaluation","not_planned")
  grid$reason <- ifelse(grid$planned,"At least one method has no complete result.","Not included in the configured experiment; no result was generated.")
  for(i in which(grid$planned)) {
    failed <- match(grid$id[i],failures$scenario)
    rows <- summary[summary$id==grid$id[i],]
    if(!is.na(failed)) {
      grid$status[i] <- "undefined_planning"
      grid$reason[i] <- failures$error[failed]
    } else if(all(methods %in% rows$method) && all(rows$complete[match(methods,rows$method)]==1)) {
      grid$status[i] <- "complete"
      grid$reason[i] <- ""
    }
  }
  grid$n_per_arm[grid$status %in% c("not_planned","undefined_planning")] <- NA_real_
  list(grid=grid,summary=summary,ceilings=reader_truth_ceiling(directory),methods=methods)
}

#' Place six saved measures and compatible truth ceilings side by side for one cell.
#' @param row One Cartesian grid row.
#' @param data Saved results and coverage from setting_result_data().
setting_measure_rows <- function(row, data) {
  fields <- names(reader_measure_names())
  keys <- c("id","pi000","criterion","m","c","n_per_arm","planned","status","reason")
  table <- data.frame(row[rep(1,length(fields)),keys],measure=unname(reader_measure_names()),
    csv_field=fields,row.names=NULL,check.names=FALSE)
  for(method in data$methods) {
    result <- data$summary[data$summary$id==row$id & data$summary$method==method,]
    stopifnot(nrow(result)<=1)
    table[[method]] <- if(isTRUE(row$planned) && nrow(result)==1 && result$complete==1)
      as.numeric(result[fields]) else rep(NA_real_,length(fields))
  }
  table$maximum_true_discoveries <- NA_real_
  truth <- data$ceilings[data$ceilings$id==row$id,]
  if(isTRUE(row$planned) && nrow(truth)==1) table$maximum_true_discoveries[c(2,4,6)] <-
    as.numeric(truth[c("available_true_study_effects","available_global_alternatives","available_replicable_outcomes")])
  table
}

#' Format a single six-measure comparison without mixing missing values and zero counts.
#' @param rows Six exported measure rows.
setting_comparison_table <- function(rows) {
  keys <- c("agent_pooled_select","agent_cycle","welch_two_sided","oracle_z_secondary","maximum_true_discoveries")
  table <- rows[c("measure",keys)]
  names(table) <- c("Measure","Agents (winner)","Agents (cycle)","Welch","Oracle (realized)","Maximum true discoveries")
  for(name in names(table)[-1]) table[[name]] <- ifelse(is.na(table[[name]]),"—",
    format(table[[name]],big.mark=",",trim=TRUE,scientific=FALSE))
  knitr::kable(table,row.names=FALSE,align=c("l",rep("r",5)))
}

#' Provide a navigable index of every planned or unplanned factor combination.
#' @param grid Cartesian coverage table.
setting_index_table <- function(grid) {
  labels <- c(complete="Complete",undefined_planning="Undefined planning",
    not_planned="Not planned",incomplete_evaluation="Incomplete evaluation")
  targets <- ifelse(grid$planned,paste0("#",grid$id),"#not-planned-combinations")
  table <- data.frame(`Π(0,0,0)`=grid$pi000,Criterion=grid$criterion,m=grid$m,c=grid$c,
    `n per arm`=ifelse(is.na(grid$n_per_arm),"—",format(grid$n_per_arm,big.mark=",",trim=TRUE)),
    Status=sprintf("[%s](%s)",unname(labels[grid$status]),targets),check.names=FALSE)
  knitr::kable(table,row.names=FALSE)
}

#' Present each planned setting with its own sample size, status and six-measure table.
#' @param data Saved results and coverage.
#' @param rows Exported measure rows.
setting_detail_text <- function(data, rows) {
  grid <- data$grid[data$grid$planned,]
  lines <- character()
  previous <- ""
  for(i in seq_len(nrow(grid))) {
    row <- grid[i,]
    group <- paste(row$regime,row$criterion)
    if(group!=previous) {
      lines <- c(lines,sprintf("## Π(0,0,0) = %g; %s",row$pi000,row$criterion),"")
      previous <- group
    }
    lines <- c(lines,sprintf("### m = %d; c = %g {#%s}",row$m,row$c,row$id),"")
    if(row$status=="undefined_planning") {
      lines <- c(lines,"**No analysis: sample-size planning is undefined.** A simulated study has no true effects, so the specified average planning power has an empty denominator. No observations were redrawn or agent sessions run for this setting; the missing result is not zero discoveries.","")
      next
    }
    lines <- c(lines,sprintf("Sample size: **n = %s exposed and n = %s unexposed per study**, with three independent studies. Status: %s.",
      format(row$n_per_arm,big.mark=",",trim=TRUE),format(row$n_per_arm,big.mark=",",trim=TRUE),
      if(row$status=="complete")"complete" else "incomplete evaluation"),"",
      setting_comparison_table(rows[rows$id==row$id,]),"",
      sprintf("[Saved study/measurement outputs](scenarios/%s/) · [Selection decisions](scenarios/%s/selection-decisions.csv) · [Back to index](#cartesian-index)",row$id,row$id),"")
  }
  lines
}

#' Render static HTML/R Markdown and CSVs; no agent or generated analysis is executed.
#' @param directory Portable artifact directory, modified only by adding presentation files.
setting_write_results <- function(directory) {
  data <- setting_result_data(directory)
  grid <- data$grid
  rows <- do.call(rbind,lapply(seq_len(nrow(grid)),function(i) setting_measure_rows(grid[i,],data)))
  write_csv(grid,file.path(directory,"per-setting-index.csv"))
  write_csv(rows,file.path(directory,"per-setting-results.csv"))
  lines <- c("---","title: 'Results for every setting'","output:","  html_document:",
    "    toc: true","    toc_depth: 2","---","",
    "[Main report](report.html) · [Definitions and oracle](supplement.html#a-measures-and-worked-examples) · [Download all six measures by setting (CSV)](per-setting-results.csv) · [Coverage index (CSV)](per-setting-index.csv)","",
    "Each evaluated setting has its own table below. Counts aggregate the three studies **within that setting only**, without summing across m, c, error criteria or hypothesis-state distributions. Agents (winner) is the pooled-selection method; Agents (cycle) is the secondary fixed-route comparator.","",
    "m is the number of measurements; c is the sample-size planning target; n is the number of exposed and unexposed observations per study. Π(0,0,0) is the probability that an outcome has no effect in any study; the full hypothesis-state distributions are given in the main report.","",
    sprintf("The full Cartesian product contains **%d combinations**: %d planned, %d complete, %d with undefined planning, and %d not planned. No new experiments were run to create these tables.",
      nrow(grid),sum(grid$planned),sum(grid$status=="complete"),sum(grid$status=="undefined_planning"),sum(!grid$planned)),"",
    "The six row names and scoring conventions match Section 4 of the main report. The oracle uses true signs and known variances, then Holm/BH at 0.05/3 per study; its realized result is not a maximum. Maximum true discoveries uses simulation truth for the three correct totals. Dashes in the maximum column mark raw totals that can include errors. Other missing cells indicate unavailable results, never zero-filled values. Secondary recovery and error measures for every evaluated method/setting remain in [summary.csv](summary.csv).","",
    "## Full Cartesian index {#cartesian-index}","",setting_index_table(grid),"",
    setting_detail_text(data,rows),
    "## Combinations not planned {#not-planned-combinations}","",
    "The original experiment includes FWER with m=20 or 100, and FDR with m=100 or 1000, under both distributions and all three c values. FWER with m=1000 and FDR with m=20 were outside that design. Their Cartesian index rows have no reported discoveries because those agent experiments were not run. They are separate from the two planned settings with undefined sample-size planning.","",
    "One iteration was used for every evaluated setting. These are realized results, not estimates of long-run FWER or FDR.")
  path <- file.path(directory,"per-setting-results.Rmd")
  writeLines(lines,path)
  rmarkdown::render(path,quiet=TRUE,envir=new.env(parent=baseenv()))
  invisible(list(index=grid,measures=rows))
}
