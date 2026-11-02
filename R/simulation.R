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

with_stream <- function(stream, operation) {
  previous <- if (exists(".Random.seed", .GlobalEnv)) get(".Random.seed", .GlobalEnv) else NULL
  on.exit(if (is.null(previous)) rm(".Random.seed", envir = .GlobalEnv)
          else assign(".Random.seed", previous, .GlobalEnv))
  assign(".Random.seed", stream, .GlobalEnv)
  operation()
}

draw_states <- function(m, probabilities) {
  labels <- names(probabilities)
  sampled <- sample(labels, m, replace = TRUE, prob = unlist(probabilities))
  matrix(as.integer(unlist(strsplit(sampled, "", fixed = TRUE))), nrow = 3L)
}

draw_effects <- function(states, delta, tau_squared) {
  states * matrix(abs(stats::rnorm(length(states), delta, sqrt(tau_squared))), nrow = 3L)
}

planning_power <- function(n, effects, alpha) {
  cutoff <- stats::qnorm(1 - alpha / ncol(effects))
  apply(effects, 1L, function(effect) {
    signals <- effect[effect > 0]
    if (!length(signals)) return(NA_real_)
    mean(stats::pnorm(sqrt(n / 2) * signals - cutoff))
  })
}

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

generate_setting <- function(config, m, target, streams) {
  states <- with_stream(streams[[1]], function() draw_states(m, config$state_probabilities))
  effects <- with_stream(streams[[2]], function() draw_effects(states, config$delta, config$tau_squared))
  planning <- smallest_sample(effects, target, config$alpha, config$max_n)
  if (6 * planning$n * m > config$max_dataset_cells) stop("infeasible: max_dataset_cells reached")
  observations <- with_stream(streams[[3]], function() draw_observations(planning$n, effects))
  list(states = states, effects = effects, planning = planning,
       observations = observations, streams = streams, m = m, target = target)
}
