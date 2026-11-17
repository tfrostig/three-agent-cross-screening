#' Deterministic selection on combined non-target observations.
#' Frozen-algorithm selection on pooled non-target observations, entirely in trusted R.

#' Pool only the two non-target observation pairs.
#' @param observations List of three exposed/control pairs.
#' @param target Held-out study index.
#' @return Exposed/control matrices with aligned columns and 2n rows per arm.
pool_non_target <- function(observations, target) {
  stopifnot(target %in% 1:3, length(observations) == 3L)
  other <- setdiff(1:3, target)
  ids <- colnames(observations[[other[1]]]$exposed)
  for (i in other) validate_matrices(observations[[i]]$exposed, observations[[i]]$unexposed)
  for (i in other) stopifnot(identical(colnames(observations[[i]]$exposed), ids))
  list(exposed = do.call(rbind, lapply(observations[other], `[[`, "exposed")),
    unexposed = do.call(rbind, lapply(observations[other], `[[`, "unexposed")))
}


#' Choose the most discoveries, breaking ties by smaller source index.
#' @param candidates Table containing source, status, and discoveries.
#' @return Selection record; failed candidates are excluded rather than scored zero.
choose_candidate <- function(candidates) {
  good <- candidates[candidates$status == "ok", , drop = FALSE]
  if (!nrow(good)) return(list(source = NA_integer_, status = "failed", tie = FALSE, degraded = TRUE))
  good <- good[order(-good$discoveries, good$source), , drop = FALSE]
  list(source = good$source[1], status = "ok", tie = sum(good$discoveries == good$discoveries[1]) > 1,
    degraded = nrow(good) < nrow(candidates))
}
