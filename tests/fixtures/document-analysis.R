hypotheses <- data.frame(measurement_id = sprintf("v%04d", seq_len(MEASUREMENT_COUNT)),
                         direction = rep(1L, MEASUREMENT_COUNT))
analyze <- function(exposed, unexposed, alpha) {
  p <- vapply(seq_len(ncol(exposed)), function(i)
    stats::t.test(exposed[, i], unexposed[, i], alternative = "greater")$p.value, numeric(1))
  q <- stats::p.adjust(p, "CORRECTION")
  d <- data.frame(measurement_id = colnames(exposed), direction = rep(1L, ncol(exposed)),
    p_value = p, adjusted_p_value = q, reject = q <= alpha)
  o <- d[c("measurement_id", "adjusted_p_value", "reject")]
  list(directional_results = d, outcome_results = o)
}
