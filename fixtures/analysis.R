#' Deterministic offline statistical fixture. FIXTURE_CORRECTION is supplied by
#'   fixture_design(); this is not a live-agent analysis.

#' Calculate one directional Welch p-value for an offline fixture
#'
#' @param exposed Numeric n by m exposed matrix with unique measurement column names.
#' @param unexposed Numeric n by m independent control matrix with the same dimensions and
#'   names.
#' @param measurement One existing measurement column name.
#' @param direction Frozen sign: +1 for a higher exposed population mean, -1 for a lower mean.
#' @return Numeric p-value; not a model-designed scientific method.
fixture_pvalue <- function(exposed, unexposed, measurement, direction) {
  if (nrow(exposed) < 2L) stop("Fixture Welch analysis requires n >= 2")
  alternative <- if (direction == 1L) "greater" else "less"
  stats::t.test(exposed[, measurement], unexposed[, measurement],
                alternative = alternative)$p.value
}

#' Execute the deterministic fixture analysis under the artifact contract
#'
#' @param exposed Numeric n by m exposed matrix with unique measurement column names.
#' @param unexposed Numeric n by m independent control matrix with the same dimensions and
#'   names.
#' @param hypotheses Frozen table with hypothesis_id, measurement_id, and integer direction
#'   (-1 or +1).
#' @param alpha Family level used directly; callers supply config$alpha/3 for target testing.
#' @return Typed per-hypothesis result data frame using FIXTURE_CORRECTION injected by
#'   fixture_design.
analyze <- function(exposed, unexposed, hypotheses, alpha) {
  if (!nrow(hypotheses)) {
    return(data.frame(hypothesis_id = character(), p_value = numeric(),
                      reject = logical(), adjusted_p_value = numeric()))
  }
  p <- vapply(seq_len(nrow(hypotheses)), function(i) {
    fixture_pvalue(exposed, unexposed, hypotheses$measurement_id[i], hypotheses$direction[i])
  }, numeric(1))
  adjusted <- stats::p.adjust(p, FIXTURE_CORRECTION)
  data.frame(hypothesis_id = hypotheses$hypothesis_id, p_value = p,
             reject = adjusted <= alpha, adjusted_p_value = adjusted)
}
