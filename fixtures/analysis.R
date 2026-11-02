fixture_pvalue <- function(exposed, unexposed, measurement, direction) {
  if (nrow(exposed) < 2L) stop("Fixture Welch analysis requires n >= 2")
  alternative <- if (direction == 1L) "greater" else "less"
  stats::t.test(exposed[, measurement], unexposed[, measurement],
                alternative = alternative)$p.value
}

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
