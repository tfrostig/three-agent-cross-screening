source("R/bootstrap.R")

welch_screen <- function(pair, reference, ranking) {
  ids <- colnames(pair$exposed)
  fits <- lapply(ids, function(id) stats::t.test(pair$exposed[, id], pair$unexposed[, id]))
  scores <- if (ranking == "p_value") vapply(fits, function(x) x$p.value, numeric(1)) else
    -abs(vapply(fits, function(x) unname(x$statistic), numeric(1)))
  count <- length(unique(reference$measurement_id))
  selected <- ids[order(scores, ids)[seq_len(count)]]
  multiplicities <- table(reference$measurement_id)
  stopifnot(all(multiplicities == 1L) || all(multiplicities == 2L))
  if (all(multiplicities == 2L)) return(directional_family(selected))
  differences <- colMeans(pair$exposed) - colMeans(pair$unexposed)
  result <- data.frame(measurement_id = selected,
                       direction = as.integer(sign(differences[selected])))
  stopifnot(all(result$direction %in% c(-1L, 1L)))
  result$hypothesis_id <- paste0(result$measurement_id, ifelse(result$direction == 1, "_pos", "_neg"))
  result[c("hypothesis_id", "measurement_id", "direction")]
}

family_keys <- function(hypotheses) paste(hypotheses$measurement_id, hypotheses$direction)

welch_on_family <- function(pair, hypotheses, scenario, alpha) {
  p <- baseline_pvalues(pair$exposed, pair$unexposed, hypotheses)
  adjusted <- stats::p.adjust(p, method = if (scenario$criterion == "FWER") "holm" else "BY")
  data.frame(hypothesis_id = hypotheses$hypothesis_id, p_value = p,
             reject = adjusted <= alpha, adjusted_p_value = adjusted)
}

check_existing_baseline <- function(setting, scenario, original, alpha) {
  expected <- original[original$scenario == scenario$id & original$method == "welch", ]
  for (target in seq_len(3L)) {
    pair <- setting$observations[[target]]
    fit <- baseline_analysis(pair$exposed, pair$unexposed, scenario$criterion, alpha)
    effects <- stats::setNames(setting$effects[target, ], colnames(pair$exposed))
    actual <- score_claims(fit$hypotheses, fit$result, effects)
    saved <- expected[expected$target == target, names(actual), drop = FALSE]
    stopifnot(isTRUE(all.equal(unname(unlist(actual)), unname(unlist(saved)), tolerance = 1e-12)))
  }
}

compare_design <- function(setting, scenario, source, context) {
  frozen <- file.path(context$run, "scenarios", scenario$id, paste0("agent-", source), "frozen")
  verify_frozen(frozen)
  reference <- read_hypothesis_table(file.path(frozen, "hypotheses.csv"))
  design_pair <- setting$observations[[source]]
  automatic <- welch_screen(design_pair, reference, "p_value")
  t_screen <- welch_screen(design_pair, reference, "t_statistic")
  target <- source %% 3L + 1L
  pair <- setting$observations[[target]]
  effects <- stats::setNames(setting$effects[target, ], colnames(pair$exposed))
  families <- list(agent_shortlist_welch = reference, welch_screen_welch = automatic)
  rows <- lapply(names(families), function(method) {
    family <- families[[method]]
    result <- welch_on_family(pair, family, scenario, context$alpha)
    prefix <- file.path(context$output, "evaluations", scenario$id, paste0("agent-", source, "-", method))
    write_csv(family, paste0(prefix, "-hypotheses.csv"))
    write_csv(result, paste0(prefix, "-results.csv"))
    score_row(scenario, method, source, target, "ok", metrics = score_claims(family, result, effects))
  })
  overlap <- data.frame(scenario = scenario$id, source = source, target = target,
    selected_measurements = length(unique(reference$measurement_id)),
    selected_hypotheses = nrow(reference), both_directions = anyDuplicated(reference$measurement_id) > 0L,
    identical_absolute_t_screen = setequal(family_keys(reference), family_keys(t_screen)),
    identical_p_value_screen = setequal(family_keys(reference), family_keys(automatic)),
    shared_p_value_screen_hypotheses = length(intersect(family_keys(reference), family_keys(automatic))))
  verify_frozen(frozen)
  list(scores = do.call(rbind, rows), overlap = overlap)
}

run_comparison <- function() {
  run <- normalizePath("results/live-first", mustWork = TRUE)
  output <- ensure_dir("results/welch-method-comparison")
  identity <- read_json(file.path(run, "run.json"))
  scenarios <- read_csv(file.path(run, "scenarios.csv"))
  original <- read_csv(file.path(run, "scores.csv"))
  context <- list(run = run, output = output, alpha = identity$config$alpha / 3)
  comparisons <- lapply(seq_len(nrow(scenarios)), function(i) {
    scenario <- scenarios[i, ]
    setting <- readRDS(file.path(run, "private", paste0(scenario$data_id, ".rds")))
    check_existing_baseline(setting, scenario, original, context$alpha)
    lapply(seq_len(3L), function(j) compare_design(setting, scenario, j, context))
  }) |> unlist(recursive = FALSE)
  scores <- do.call(rbind, lapply(comparisons, function(x) x$scores))
  overlap <- do.call(rbind, lapply(comparisons, function(x) x$overlap))
  existing <- original[original$method %in% c("agent", "welch"), ]
  combined <- rbind(existing, scores)
  write_csv(combined, file.path(output, "scores.csv"))
  write_csv(global_scores(combined), file.path(output, "global-scores.csv"))
  write_csv(overlap, file.path(output, "screen-overlap.csv"))
  input_files <- c(file.path(run, c("run.json", "scores.csv", "scenarios.csv")),
    list.files(file.path(run, "private"), pattern = "\\.rds$", full.names = TRUE),
    list.files(file.path(run, "scenarios"), pattern = "frozen.json$", recursive = TRUE, full.names = TRUE))
  write_json(list(created_at = timestamp(), original_run_signature = identity$signature,
    source_sha256 = file_hash("analyses/compare_welch.R"), input_sha256 = as.list(vapply(input_files, file_hash, character(1))),
    additional_simulation_draws = 0L, additional_agent_calls = 0L,
    selection = "Same number of coordinates and one/both-direction policy per original design; rank source two-sided Welch p-values. Shortlist sizes are inherited, not independently prespecified.",
    checks = "All 24 original Welch baseline scores reproduced; all frozen hashes verified before and after comparison."),
    file.path(output, "comparison.json"))
  print(global_scores(combined), row.names = FALSE)
  print(overlap, row.names = FALSE)
}

run_comparison()
