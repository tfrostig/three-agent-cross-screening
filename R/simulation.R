#' Trusted-host simulation and planning only. These functions and their latent effects must
#'   never be exposed to agents.

#' Allocate independent L'Ecuyer-CMRG random-number streams
#'
#' @param seed Integer master simulation seed.
#' @param count Number of independent RNG streams to allocate.
#' @return List of RNG states. Sets the process RNG kind and initial state.
seed_streams <- function(seed, count) {
  RNGkind("L'Ecuyer-CMRG")
  set.seed(seed)
  streams <- vector("list", count)
  current <- .Random.seed
  for (i in seq_len(count)) {
    streams[[i]] <- current
    current <- parallel::nextRNGStream(current)
  }
  streams
}

#' Evaluate an operation under a supplied RNG state
#'
#' @param stream One saved L'Ecuyer-CMRG RNG state.
#' @param operation Zero-argument function evaluated under the supplied RNG state.
#' @return The operation's result; restores the prior .Random.seed on exit.
with_stream <- function(stream, operation) {
  previous <- if (exists(".Random.seed", .GlobalEnv)) get(".Random.seed", .GlobalEnv) else NULL
  on.exit(if (is.null(previous)) rm(".Random.seed", envir = .GlobalEnv)
          else assign(".Random.seed", previous, .GlobalEnv))
  assign(".Random.seed", stream, .GlobalEnv)
  operation()
}

#' Sample shared three-subgroup signal-presence patterns
#'
#' @param m Number of measurement columns.
#' @param probabilities Named probabilities for the eight three-subgroup bit patterns.
#' @return A 3 by m integer matrix of zero/one indicators.
draw_states <- function(m, probabilities) {
  labels <- names(probabilities)
  sampled <- sample(labels, m, replace = TRUE, prob = unlist(probabilities))
  matrix(as.integer(unlist(strsplit(sampled, "", fixed = TRUE))), nrow = 3L)
}

#' Generate positive effect magnitudes for active states
#'
#' @param states A 3 by m zero/one signal-presence matrix.
#' @param delta Mean of the normal draw before taking its absolute value.
#' @param tau_squared Variance of the normal draw before taking its absolute value.
#' @return A 3 by m numeric effect matrix; inactive entries remain zero.
draw_effects <- function(states, delta, tau_squared) {
  states * matrix(abs(stats::rnorm(length(states), delta, sqrt(tau_squared))), nrow = 3L)
}

#' Evaluate the specified known-variance planning formula
#'
#' @param n Number of independent observations per exposed/control arm in each subgroup.
#' @param effects A 3 by m effect matrix for generation/planning, or a named target-effect
#'   vector for scoring.
#' @param alpha Overall planning level; the formula internally uses alpha/m, not the
#'   target-testing alpha/3.
#' @return Three average powers over positive effects, with NA for an empty-signal subgroup.
planning_power <- function(n, effects, alpha) {
  cutoff <- stats::qnorm(1 - alpha / ncol(effects))
  apply(effects, 1L, function(effect) {
    signals <- effect[effect > 0]
    if (!length(signals)) return(NA_real_)
    mean(stats::pnorm(sqrt(n / 2) * signals - cutoff))
  })
}

#' Find the smallest integer n passing all subgroup power targets
#'
#' @param effects A 3 by m effect matrix for generation/planning, or a named target-effect
#'   vector for scoring.
#' @param target Planning power target c.
#' @param alpha Overall planning level passed to planning_power(), which applies alpha/m.
#' @param max_n Largest permitted integer sample size.
#' @return List with n, power at n, and previous_power at n-1 (NULL for n=1). Stops on empty
#'   signals or the resource ceiling.
smallest_sample <- function(effects, target, alpha, max_n = 100000L) {
  if (any(rowSums(effects > 0) == 0)) stop("undefined_power: subgroup has no signals")
  passes <- function(n) min(planning_power(n, effects, alpha)) > target
  upper <- 1L
  while (!passes(upper)) {
    if (upper >= max_n) stop("infeasible: max_n reached")
    upper <- min(2L * upper, max_n)
  }
  lower <- 1L
  while (lower < upper) {
    middle <- floor((lower + upper) / 2)
    if (passes(middle)) upper <- middle else lower <- middle + 1L
  }
  list(n = lower, power = planning_power(lower, effects, alpha),
       previous_power = if (lower > 1) planning_power(lower - 1L, effects, alpha) else NULL)
}

#' Generate independent exposed and control matrices for each subgroup
#'
#' @param n Number of independent observations per exposed/control arm in each subgroup.
#' @param effects A 3 by m effect matrix for generation/planning, or a named target-effect
#'   vector for scoring.
#' @return List of three pairs; each named matrix is n by m, with identity population
#'   covariance.
draw_observations <- function(n, effects) {
  m <- ncol(effects)
  names <- sprintf("v%04d", seq_len(m))
  lapply(seq_len(3L), function(j) {
    exposed <- sweep(matrix(stats::rnorm(n * m), n, m), 2L, effects[j, ], "+")
    unexposed <- matrix(stats::rnorm(n * m), n, m)
    colnames(exposed) <- colnames(unexposed) <- names
    list(exposed = exposed, unexposed = unexposed)
  })
}

#' Generate one reusable setting using separate state, effect, and data streams
#'
#' @param config Validated configuration list from load_config(), unless a SessionConfig is
#'   explicitly noted.
#' @param m Number of measurement columns.
#' @param target Planning power target c.
#' @param streams Three saved RNG states for states, effects, and observations, in that order.
#' @return List containing states, effects, planning, observations, streams, m, and target;
#'   stops on resource limits.
generate_setting <- function(config, m, target, streams) {
  states <- with_stream(streams[[1]], function() draw_states(m, config$state_probabilities))
  effects <- with_stream(streams[[2]], function() draw_effects(states, config$delta, config$tau_squared))
  planning <- smallest_sample(effects, target, config$alpha, config$max_n)
  if (6 * planning$n * m > config$max_dataset_cells) stop("infeasible: max_dataset_cells reached")
  observations <- with_stream(streams[[3]], function() draw_observations(planning$n, effects))
  list(states = states, effects = effects, planning = planning,
       observations = observations, streams = streams, m = m, target = target)
}
