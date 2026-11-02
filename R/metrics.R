#' Conventional target baselines and truth-aware scoring; keep latent effects exclusively on
#'   the trusted host.

#' Enumerate both directional alternatives for every measurement
#'
#' @param measurements Character vector of valid measurement column names.
#' @return Data frame with 2m rows and stable _pos/_neg hypothesis IDs.
directional_family <- function(measurements) {
  grid <- expand.grid(measurement_id = measurements, direction = c(1L, -1L),
                      stringsAsFactors = FALSE)
  grid$hypothesis_id <- paste0(grid$measurement_id, ifelse(grid$direction == 1, "_pos", "_neg"))
  grid[c("hypothesis_id", "measurement_id", "direction")]
}

#' Calculate raw directional Welch or known-variance z p-values
#'
#' @param exposed Numeric n by m exposed matrix with unique measurement column names.
#' @param unexposed Numeric n by m independent control matrix with the same dimensions and
#'   names.
#' @param hypotheses Frozen table with hypothesis_id, measurement_id, and integer direction
#'   (-1 or +1).
#' @param known_variance Logical; use the generator's unit population variance for an oracle z
#'   reference.
#' @return Numeric vector aligned to hypotheses; Welch fails for fewer than two observations
#'   per arm.
baseline_pvalues <- function(exposed, unexposed, hypotheses, known_variance = FALSE) {
  vapply(seq_len(nrow(hypotheses)), function(i) {
    column <- hypotheses$measurement_id[i]
    direction <- hypotheses$direction[i]
    x <- exposed[, column]
    y <- unexposed[, column]
    if (known_variance) {
      z <- direction * (mean(x) - mean(y)) / sqrt(1 / length(x) + 1 / length(y))
      return(stats::pnorm(z, lower.tail = FALSE))
    }
    if (length(x) < 2 || length(y) < 2) stop("Welch baseline requires n >= 2")
    alternative <- if (direction == 1) "greater" else "less"
    stats::t.test(x, y, alternative = alternative)$p.value
  }, numeric(1))
}

#' Test the full directional family with a specified correction
#'
#' @param exposed Numeric n by m exposed matrix with unique measurement column names.
#' @param unexposed Numeric n by m independent control matrix with the same dimensions and
#'   names.
#' @param criterion Character scalar FWER or FDR.
#' @param alpha Family level used directly; callers supply config$alpha/3 for target testing.
#' @param known_variance Logical; use the generator's unit population variance for an oracle z
#'   reference.
#' @param fdr_method BH or BY; ignored for Holm FWER correction.
#' @return List containing hypotheses and result. Uses Holm for FWER, the requested BH/BY for
#'   FDR.
baseline_analysis <- function(exposed, unexposed, criterion, alpha, known_variance = FALSE,
                              fdr_method = "BY") {
  stopifnot(criterion %in% c("FWER", "FDR"), length(fdr_method) == 1L, fdr_method %in% c("BH", "BY"))
  hypotheses <- directional_family(colnames(exposed))
  p <- baseline_pvalues(exposed, unexposed, hypotheses, known_variance)
  adjusted <- stats::p.adjust(p, method = if (criterion == "FWER") "holm" else fdr_method)
  result <- data.frame(hypothesis_id = hypotheses$hypothesis_id, p_value = p,
                       reject = adjusted <= alpha, adjusted_p_value = adjusted)
  list(hypotheses = hypotheses, result = result)
}

#' Score frozen directional rejections using trusted target effects
#'
#' @param hypotheses Frozen table with hypothesis_id, measurement_id, and integer direction
#'   (-1 or +1).
#' @param result Per-hypothesis table with hypothesis_id, p_value, reject, and
#'   adjusted_p_value.
#' @param effects A 3 by m effect matrix for generation/planning, or a named target-effect
#'   vector for scoring.
#' @return One-row data frame of counts, FDP, any_false, and power. Zero or opposite-sign
#'   effects are false claims; power counts unique correct coordinates.
score_claims <- function(hypotheses, result, effects) {
  validate_hypotheses(hypotheses, names(effects))
  validate_result(result, hypotheses)
  result <- result[match(hypotheses$hypothesis_id, result$hypothesis_id), , drop = FALSE]
  theta <- effects[hypotheses$measurement_id]
  false <- hypotheses$direction * theta <= 0
  rejected <- result$reject
  discoveries <- unique(hypotheses$measurement_id[rejected & !false])
  nonnull <- sum(effects != 0)
  rejections <- sum(rejected)
  errors <- sum(rejected & false)
  data.frame(selected = nrow(hypotheses), rejected = rejections, false = errors,
             correct_coordinates = length(discoveries), nonnull = nonnull,
             fdp = errors / max(rejections, 1), any_false = as.integer(errors > 0),
             power = if (nonnull) length(discoveries) / nonnull else NA_real_)
}

#' Combine successful target evaluations within scenario and method
#'
#' @param scores Per-target scores.csv data frame including method, status, and discovery
#'   metrics.
#' @return Data frame of totals. Global FDP/power require exactly three successful target
#'   rows; incomplete groups receive NA.
global_scores <- function(scores) {
  good <- scores[scores$status == "ok", , drop = FALSE]
  groups <- split(good, interaction(good$scenario, good$method, drop = TRUE))
  rows <- lapply(groups, function(x) {
    complete <- nrow(x) == 3L
    data.frame(scenario = x$scenario[1], method = x$method[1], evaluable_groups = nrow(x),
               complete = complete, rejected = sum(x$rejected), false = sum(x$false),
               realized_fdp = if (complete) sum(x$false) / max(sum(x$rejected), 1) else NA_real_,
               any_false = if (complete) as.integer(any(x$false > 0)) else NA_integer_,
               power = if (complete) sum(x$correct_coordinates) / sum(x$nonnull) else NA_real_)
  })
  if (!length(rows)) return(data.frame())
  do.call(rbind, rows)
}
