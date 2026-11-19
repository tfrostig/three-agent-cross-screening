#' Reconcile document measures with saved target outputs and private simulation truth.
if (!exists("project_root")) source("R/bootstrap.R")

#' Recompute counts without calling the production scoring function.
#' @param row One saved method/scenario summary.
#' @param run_dir Sealed results directory.
#' @param truth Outcome identifiers and true nonzero-study counts.
audit_measure_row <- function(row, run_dir, truth) {
  directory <- file.path(run_dir, "scenarios", row$id, row$method)
  targets <- jsonlite::read_json(file.path(directory, "target-results.json"))
  stopifnot(length(targets) == 3, row$complete == 1)
  q <- sapply(targets, function(target) {
    outcomes <- do.call(rbind, lapply(target$outcome_results, as.data.frame))
    stopifnot(!anyDuplicated(outcomes$measurement_id), setequal(outcomes$measurement_id, truth$ids))
    outcomes$adjusted_p_value[match(truth$ids, outcomes$measurement_id)]
  })
  lower <- rowSums(q <= .05/3)
  r <- truth$count
  global <- pmin(1, apply(q, 1, min)*3)
  repl <- pmin(1, apply(q, 1, function(x) sort(x)[2])*3)
  stopifnot(identical(global <= .05, lower > 0), identical(repl <= .05, lower > 1))
  computed <- c(claimed_studies = sum(lower),
    correct_lower_bound_credit = sum(lower[lower <= r]),
    global_discoveries = sum(lower > 0), true_global_discoveries = sum(lower > 0 & r > 0),
    replicability_discoveries = sum(lower > 1), true_replicability_discoveries = sum(lower > 1 & r > 1))
  stopifnot(identical(as.numeric(row[names(computed)]), as.numeric(computed)))
  saved <- read_csv(file.path(directory, "outcomes.csv"))
  saved <- saved[match(truth$ids, saved$measurement_id), ]
  stopifnot(identical(as.numeric(saved$true_count), as.numeric(r)),
    identical(as.numeric(saved$claimed_count), as.numeric(lower)),
    isTRUE(all.equal(as.matrix(saved[c("q1", "q2", "q3")]), q, check.attributes=FALSE, tolerance=1e-13)))
  data.frame(row[c("id", "regime", "criterion", "m", "c", "method")],
    as.list(computed), positive_correct_bound_outcomes = sum(lower > 0 & lower <= r),
    zero_bound_outcomes = sum(lower == 0), overclaimed_outcomes = sum(lower > r), verified = TRUE)
}

#' Load truth once per dataset and audit every complete method/scenario result.
#' @param run_dir Sealed completed live run.
#' @param output_dir Directory receiving independent verification and alternative counts.
audit_measures <- function(run_dir, output_dir) {
  stopifnot(doc_package_valid(run_dir))
  summary <- read_csv(file.path(run_dir, "summary.csv"))
  grid <- read_csv(file.path(run_dir, "scenarios.csv"))
  data_ids <- unique(grid$data_id[match(summary$id, grid$id)])
  truth <- setNames(lapply(data_ids, function(id) {
    setting <- readRDS(file.path(run_dir, "private", paste0(id, ".rds")))
    list(ids = colnames(setting$observations[[1]]$exposed), count = colSums(setting$effects != 0))
  }), data_ids)
  rows <- lapply(seq_len(nrow(summary)), function(i) {
    row <- summary[i, ]
    if (row$complete != 1) return(NULL)
    audit_measure_row(row, run_dir, truth[[grid$data_id[match(row$id, grid$id)]]])
  })
  table <- do.call(rbind, rows)
  write_csv(table, file.path(output_dir, "six-measure-verification.csv"))
  alternative <- table[c("id", "regime", "criterion", "m", "c", "method",
    "correct_lower_bound_credit", "positive_correct_bound_outcomes", "zero_bound_outcomes", "overclaimed_outcomes")]
  names(alternative)[names(alternative) == "correct_lower_bound_credit"] <- "weighted_correct_lower_bound_total"
  write_csv(alternative, file.path(output_dir, "lower-bound-alignment-counts.csv"))
  cat("Independently verified all six scores for", nrow(table), "complete method/scenario results.\n")
  invisible(table)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  audit_measures(normalizePath(cli_value(args, "--run-dir"), mustWork = TRUE),
    ensure_dir(cli_value(args, "--output")))
}
