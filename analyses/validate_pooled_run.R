#' Verify a completed pooled run directly against raw outputs and historical provenance.
#' CLI: --run-dir DIR, --reuse-run DIR, and optional --original-hashes FILE.
#' Reads saved artifacts only; does not rerun agents, analyses, or scientific simulations.
source("R/bootstrap.R")

#' Independently reconstruct count credit from per-target result files.
#' @param setting Trusted setting providing the true effect matrix.
#' @param rows Three successful evaluation-ledger rows for one method.
#' @param directory Scenario output directory.
#' @return List with recovery, overclaims and all-null discoveries.
reconstruct_count_credit <- function(setting, rows, directory) {
  stopifnot(nrow(rows) == 3L, setequal(rows$target, 1:3), all(rows$status == "ok"))
  ids <- colnames(setting$observations[[1]]$exposed)
  claims <- matrix(FALSE, length(ids), 3L)
  for (target in 1:3) {
    row <- rows[rows$target == target, ]
    h <- read_hypothesis_table(file.path(directory, row$hypotheses_file))
    r <- read_result_table(file.path(directory, row$result_file))
    validate_result(r, h)
    ids_rejected <- h$measurement_id[match(r$hypothesis_id[r$reject], h$hypothesis_id)]
    claims[, target] <- ids %in% ids_rejected
  }
  true <- colSums(setting$effects != 0)
  count <- rowSums(claims)
  eligible <- true > 0
  credit <- count[eligible] / true[eligible]
  credit[count[eligible] > true[eligible]] <- 0
  list(recovery = if (any(eligible)) mean(credit) else NA_real_,
    overclaims = sum(count > true), all_null = sum(count > 0 & true == 0))
}

#' Check selection counts and routes against actual pooled output files.
#' @param directory Scenario directory with candidate/decision tables.
#' @return NULL; stops on a mismatched count, winner, tie, or source route.
validate_pooled_decisions <- function(directory) {
  candidates <- read_csv(file.path(directory, "selection-candidates.csv"))
  decisions <- read_csv(file.path(directory, "selection-decisions.csv"))
  for (target in 1:3) {
    rows <- candidates[candidates$target == target, ]
    stopifnot(nrow(rows) == 2L, setequal(rows$source, setdiff(1:3, target)))
    for (i in which(rows$status == "ok")) {
      source <- rows$source[i]
      h <- read_hypothesis_table(file.path(directory, paste0("agent-", source), "frozen/hypotheses.csv"))
      prefix <- file.path(directory, "selection", paste0("target-", target, "-source-", source))
      r <- read_result_table(paste0(prefix, "-result.csv"))
      rejected <- h$measurement_id[match(r$hypothesis_id[r$reject], h$hypothesis_id)]
      stopifnot(length(unique(rejected)) == rows$discoveries[i],
        sum(table(rejected) > 1L) == rows$directional_conflicts[i],
        file_hash(paste0(prefix, "-result.csv")) == rows$result_hash[i])
    }
    good <- rows[rows$status == "ok", ]
    good <- good[order(-good$discoveries, good$source), ]
    decision <- decisions[decisions$target == target, ]
    stopifnot(nrow(decision) == 1L, abs(decision$alpha - .05/3) < 1e-14,
      decision$selected_source == good$source[1],
      decision$tie == (sum(good$discoveries == good$discoveries[1]) > 1L),
      decision$degraded == (nrow(good) < 2L))
  }
}

#' Validate all score definitions, frozen files, and original cyclic comparator values.
#' @param run_dir Completed new run.
#' @param reuse_run Original revised run used for imports.
#' @return TRUE invisibly; checks every method against independently reconstructed counts.
validate_pooled_outputs <- function(run_dir, reuse_run) {
  scenarios <- read_csv(file.path(run_dir, "scenarios.csv"))
  counts <- read_csv(file.path(run_dir, "study-count-summary.csv"))
  scores <- read_csv(file.path(run_dir, "scores.csv"))
  historical <- read_csv(file.path(reuse_run, "scores.csv"))
  stopifnot(nrow(scenarios) == 12L, nrow(scores) == 180L, all(scores$status == "ok"))
  for (i in seq_len(nrow(scenarios))) {
    s <- scenarios[i, ]
    directory <- file.path(run_dir, "scenarios", s$id)
    setting <- readRDS(file.path(run_dir, "private", paste0(s$data_id, ".rds")))
    validate_pooled_decisions(directory)
    for (source in 1:3) verify_frozen(file.path(directory, paste0("agent-", source), "frozen"))
    ledger <- read_csv(file.path(directory, "evaluation-ledger.csv"))
    for (method in unique(ledger$method)) {
      actual <- reconstruct_count_credit(setting, ledger[ledger$method == method, ], directory)
      saved <- counts[counts$scenario == s$id & counts$method == method, ]
      stopifnot(nrow(saved) == 1L, saved$complete,
        isTRUE(all.equal(actual$recovery, saved$study_count_recovery)),
        actual$overclaims == saved$overclaimed_measurements, actual$all_null == saved$all_null_discoveries)
    }
    if (s$c < .9) {
      old <- historical[historical$scenario == s$id, ]
      new <- scores[scores$scenario == s$id & scores$method != "agent_pooled_select", ]
      new$method[new$method == "agent_cycle"] <- "agent"
      keys <- function(x) paste(x$method, x$target)
      old <- old[match(keys(new), keys(old)), ]
      fields <- c("selected", "rejected", "false", "correct_coordinates", "nonnull", "fdp", "power")
      stopifnot(isTRUE(all.equal(new[fields], old[fields], check.attributes = FALSE)))
    }
  }
  invisible(TRUE)
}

#' Verify imported bytes, c=.9 planning minimality, and new/historical usage separation.
#' @param run_dir Completed new run.
#' @param reuse_run Historical source run.
#' @return NULL; stops on altered imports or unexpected design/accounting counts.
validate_pooled_provenance <- function(run_dir, reuse_run) {
  old <- list.files(file.path(reuse_run, "private"), pattern = "[.]rds$", full.names = TRUE)
  for (path in old) stopifnot(file_hash(path) == file_hash(file.path(run_dir, "private", basename(path))))
  old <- list.files(file.path(reuse_run, "scenarios"), pattern = "frozen.json$", recursive = TRUE, full.names = TRUE)
  for (path in old) {
    relative <- substring(dirname(path), nchar(reuse_run) + 2L)
    for (name in c("analysis.R", "hypotheses.csv", "report.md", "frozen.json"))
      stopifnot(file_hash(file.path(dirname(path), name)) == file_hash(file.path(run_dir, relative, name)))
  }
  usage <- read_csv(file.path(run_dir, "usage.csv"))
  imported <- usage$origin == "imported"
  stopifnot(nrow(usage) == 36L, sum(imported) == 24L, sum(!imported) == 12L,
    all(usage$api_attempts[imported] == 0L), all(usage$seconds[imported] == 0),
    all(usage$api_attempts[!imported] > 0L & usage$api_attempts[!imported] <= 16L))
  paths <- list.files(file.path(run_dir, "private"), pattern = "c90[.]rds$", full.names = TRUE)
  for (path in paths) {
    setting <- readRDS(path)
    stopifnot(min(planning_power(setting$planning$n, setting$effects, .05)) > .9,
      min(planning_power(setting$planning$n - 1L, setting$effects, .05)) <= .9)
  }
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  run_dir <- normalizePath(cli_value(args, "--run-dir", "results/live-pooled-20261104"), mustWork = TRUE)
  reuse <- normalizePath(cli_value(args, "--reuse-run", "results/live-revised-20261101"), mustWork = TRUE)
  validate_pooled_outputs(run_dir, reuse)
  validate_pooled_provenance(run_dir, reuse)
  snapshot <- cli_value(args, "--original-hashes")
  if (!is.null(snapshot)) {
    original <- read_json(snapshot)
    stopifnot(all(vapply(names(original), file_hash, character(1)) == unlist(original)))
  }
  message("Validated all 12 scenarios, 180 evaluations, raw count scores, 24 imports, and 12 new sessions.")
}
