#' Count-based recovery of nonnull studies, with separate directional error accounting.

#' Collapse directional rejections into one claim per measurement per study.
#' @param hypotheses Frozen directional family.
#' @param result Validated per-hypothesis output.
#' @return Character vector of discovered measurement IDs, without duplicates.
discovered_measurements <- function(hypotheses, result) {
  validate_result(result, hypotheses)
  rejected <- result$reject[match(hypotheses$hypothesis_id, result$hypothesis_id)]
  unique(hypotheses$measurement_id[rejected])
}

#' Evaluate all measurements under the count-only recovery definition.
#' @param effects Three-by-m truth matrix with measurement column names.
#' @param claims List of three measurement-ID vectors, or NULL for missing target outputs.
#' @return Per-measurement counts, credit, and overclaim indicators; incomplete credit is NA.
study_count_scores <- function(effects, claims) {
  stopifnot(nrow(effects) == 3L, !is.null(colnames(effects)), length(claims) == 3L)
  ids <- colnames(effects)
  valid <- vapply(claims, function(x) !is.null(x), logical(1))
  for (claim in claims[valid]) stopifnot(all(claim %in% ids))
  true <- colSums(effects != 0)
  observed <- matrix(vapply(claims, function(x) ids %in% x, logical(length(ids))), nrow = length(ids), ncol = 3L)
  estimated <- if (all(valid)) rowSums(observed) else rep(NA_integer_, length(ids))
  credit <- ifelse(true == 0 | is.na(estimated), NA_real_,
    ifelse(estimated > true, 0, estimated / pmax(true, 1)))
  data.frame(measurement_id = ids, true_study_count = unname(true),
    claimed_study_count = estimated, study_count_recovery = credit,
    overclaimed = estimated > true, all_null = true == 0,
    observed_claims = rowSums(observed), evaluable_studies = sum(valid), complete = all(valid))
}

#' Summarize recovery with equal weight for every nonnull measurement.
#' @param table Per-measurement output from study_count_scores().
#' @return One-row summary; all-null measurements are excluded, and incomplete methods are NA.
summarize_study_counts <- function(table) {
  complete <- all(table$complete)
  eligible <- table$true_study_count > 0
  data.frame(complete = complete, evaluable_groups = table$evaluable_studies[1],
    eligible_measurements = sum(eligible),
    study_count_recovery = if (complete && any(eligible)) mean(table$study_count_recovery[eligible]) else NA_real_,
    overclaimed_measurements = if (complete) sum(table$overclaimed) else NA_integer_,
    all_null_discoveries = if (complete) sum(table$all_null & table$claimed_study_count > 0) else NA_integer_,
    discovered_measurements = if (complete) sum(table$claimed_study_count > 0) else NA_integer_)
}

#' Score a method across held-out studies using the saved evaluation ledger.
#' @param setting Host-private generated setting.
#' @param ledger Three target records with status and artifact/result file paths.
#' @param directory Scenario directory against which ledger paths are resolved.
#' @return Per-measurement table; missing or failed target records remain missing.
score_study_ledger <- function(setting, ledger, directory) {
  ids <- colnames(setting$observations[[1]]$exposed)
  effects <- setting$effects
  colnames(effects) <- ids
  claims <- lapply(1:3, function(target) {
    row <- ledger[ledger$target == target, , drop = FALSE]
    if (nrow(row) != 1L || row$status != "ok") return(NULL)
    h <- read_hypothesis_table(file.path(directory, row$hypotheses_file))
    r <- read_result_table(file.path(directory, row$result_file))
    discovered_measurements(h, r)
  })
  study_count_scores(effects, claims)
}

#' Write primary recovery and secondary directional summaries for a completed run.
#' @param scores Per-target directional scores.
#' @param run_dir Run directory with scenario ledgers and private settings.
#' @return Writes global-scores.csv and, for pooled runs, study-count summaries/tables.
write_run_summaries <- function(scores, run_dir) {
  global <- global_scores(scores)
  if (!file.exists(file.path(run_dir, "scenarios.csv"))) return(invisible(NULL))
  scenarios <- read_csv(file.path(run_dir, "scenarios.csv"))
  summaries <- list()
  for (i in seq_len(nrow(scenarios))) {
    scenario <- scenarios[i, ]
    directory <- file.path(run_dir, "scenarios", scenario$id)
    path <- file.path(directory, "evaluation-ledger.csv")
    if (!file.exists(path)) next
    ledger <- read_csv(path)
    setting <- readRDS(file.path(run_dir, "private", paste0(scenario$data_id, ".rds")))
    tables <- lapply(unique(ledger$method), function(method) {
      table <- score_study_ledger(setting, ledger[ledger$method == method, ], directory)
      write_csv(table, file.path(directory, "study-counts", paste0(method, ".csv")))
      cbind(data.frame(scenario = scenario$id, method = method), summarize_study_counts(table))
    })
    summaries <- c(summaries, tables)
  }
  if (length(summaries)) {
    counts <- do.call(rbind, summaries)
    write_csv(counts, file.path(run_dir, "study-count-summary.csv"))
    global <- merge(global, counts[, !names(counts) %in% c("complete", "evaluable_groups")],
      by = c("scenario", "method"), all = TRUE, sort = FALSE)
  }
  write_csv(global, file.path(run_dir, "global-scores.csv"))
}
