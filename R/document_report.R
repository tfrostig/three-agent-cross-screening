#' Escape untrusted text for literal inclusion in an R Markdown report.
#' @param text Untrusted agent text.
doc_escape <- function(text) {
  text <- gsub("&", "&amp;", text, fixed = TRUE)
  text <- gsub("<", "&lt;", text, fixed = TRUE)
  text <- gsub(">", "&gt;", text, fixed = TRUE)
  gsub("`", "&#96;", text, fixed = TRUE)
}

#' Export the document table with raw directional entries and combined values.
#' @param targets Three target results.
#' @param table Aggregation table.
#' @param ids Ordered measurement names.
doc_display <- function(targets, table, ids) {
  for (j in 1:3) {
    fit <- targets[[j]]
    table[[paste0("study", j)]] <- vapply(ids, function(id) {
      if (is.null(fit)) return("FAILED")
      if (is.null(fit$directional_results)) {
        i <- match(id, ids)
        return(sprintf("%.6g (%.6g; two-sided)", fit$raw_p[i], fit$outcome_results$adjusted_p_value[i]))
      }
      d <- fit$directional_results
      d <- d[d$measurement_id == id, , drop = FALSE]
      if (!nrow(d)) return("1 (1; not selected)")
      paste(sprintf("%.6g (%.6g; %s)", d$p_value, d$adjusted_p_value,
        ifelse(d$direction == 1, ">", "<")), collapse = "; ")
    }, character(1))
  }
  table
}

#' Score directional errors separately from nondirectional count credit.
#' @param effects Truth matrix.
#' @param targets Three target outputs.
doc_directional <- function(effects, targets) {
  do.call(rbind, lapply(1:3, function(j) {
    fit <- targets[[j]]
    if (is.null(fit) || is.null(fit$directional_results)) return(NULL)
    d <- fit$directional_results
    d <- d[d$reject, , drop = FALSE]
    truth <- effects[j, match(d$measurement_id, colnames(effects))]
    false <- sum(truth*d$direction <= 0)
    data.frame(target = j, discoveries = nrow(d), false_discoveries = false,
      fdp = false/max(1, nrow(d)), directional_power =
        if (sum(effects[j, ] != 0)) length(unique(d$measurement_id[truth*d$direction > 0]))/sum(effects[j, ] != 0) else NA_real_)
  }))
}

#' Render controlled R Markdown and package a portable, hash-indexed results copy.
#' @param run_dir New run root.
#' @param summary Main metric table.
#' @param failures Planning/session failures.
doc_report <- function(run_dir, summary, failures) {
  write_csv(summary, file.path(run_dir, "summary.csv"))
  write_csv(failures, file.path(run_dir, "failures.csv"))
  doc_write_results(run_dir, summary, failures)
  writeLines(c("# Results guide", "report.html: results-first report; report.Rmd: editable source.",
    "agent-index.md: every original report, R design and exploration journal. agent-methods.csv: all proposed designs and their selected targets.",
    "selected-algorithms.csv: selected source per target, ties, status and hashes. paired-comparisons.csv: complete matched agent/standard comparisons.",
    "summary.csv: all six main metrics plus recovery/errors, including incomplete cases. failures.csv: planning failures. usage.csv: actual/known usage and timing.",
    "scenarios/: frozen designs, partial-failure audits, full per-measurement tables and cached evaluations.",
    "private/: raw observations/truth for local reproducibility only. datasets.json and SHA256.csv: integrity records.",
    "The -share.zip omits raw observations, private truth and mutable workspaces. The full ZIP preserves local records."), file.path(run_dir, "README.md"))
  doc_package(run_dir)
}

#' Export planning, usage and optional historical summaries before packaging.
#' @param run_dir New run directory.
#' @param settings Named prepared datasets.
#' @param historical Optional historical source run.
doc_audits <- function(run_dir, settings, historical) {
  planning <- do.call(rbind, lapply(names(settings), function(id) {
    x <- settings[[id]]
    data.frame(data_id=id,n=if (is.null(x$error)) x$planning$n else NA_integer_,
      planning_min=if (is.null(x$error)) min(x$planning$power) else NA_real_,
      previous_min=if (is.null(x$error) && !is.null(x$planning$previous_power)) min(x$planning$previous_power) else NA_real_,
      error=x$error %||% "")
  }))
  write_csv(planning,file.path(run_dir,"planning.csv"))
  paths <- list.files(file.path(run_dir,"scenarios"),pattern="session.json$",recursive=TRUE,full.names=TRUE)
  usage <- lapply(paths,function(path) {
    x <- read_json(path)
    data.frame(session=substring(path,nchar(run_dir)+2),status=x$status,
      elapsed_seconds=x$duration_seconds %||% NA_real_,physical_api_attempts=x$physical_api_attempts %||%
        if (file.exists(file.path(dirname(path),"api-attempts.json"))) read_json(file.path(dirname(path),"api-attempts.json"))$attempts else 0,
      input_tokens=x$usage$input_tokens %||% NA_real_,output_tokens=x$usage$output_tokens %||% NA_real_)
  })
  if (length(usage)) write_csv(do.call(rbind,usage),file.path(run_dir,"usage.csv"))
  if (!is.null(historical)) {
    destination <- ensure_dir(file.path(run_dir,"historical-comparison"))
    for (name in c("study-count-summary.csv","global-scores.csv","scores.csv")) {
      path <- file.path(historical,name)
      if (file.exists(path)) {
        if (!file.exists(file.path(destination,name))) stopifnot(file.copy(path,file.path(destination,name)))
        stopifnot(file_hash(path)==file_hash(file.path(destination,name)))
      }
    }
    writeLines("Historical outputs: different prompts/contracts. Not new-protocol designs.",file.path(destination,"README.md"))
  }
}
