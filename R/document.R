#' Document-v2 orchestration, preserving the historical reader and pipeline.
source(file.path(project_root, "R/document_contracts.R"))
source(file.path(project_root, "R/document_sandbox.R"))

#' Expand regimes while preserving the historical dataset stream ordering.
#' @param config Document configuration.
doc_grid <- function(config) {
  do.call(rbind, lapply(names(config$regimes), function(regime) {
    grid <- scenario_grid(config)
    grid$regime <- regime
    grid$id <- paste(regime, grid$id, sep = "_")
    grid$data_id <- paste(regime, grid$data_id, sep = "_")
    grid
  }))
}

#' Recover typed rows from JSON, including empty families.
#' @param rows Unsimplified JSON array of records.
#' @param columns Named prototype vectors.
doc_rows <- function(rows, columns) {
  if (!length(rows)) return(as.data.frame(columns))
  result <- do.call(rbind, lapply(rows, as.data.frame, stringsAsFactors = FALSE))
  if ("direction" %in% names(result)) result$direction <- as.integer(result$direction)
  result
}

#' Read an embedded hypothesis family.
#' @param rows Unsimplified JSON records.
doc_hypotheses <- function(rows) {
  doc_rows(rows, list(measurement_id = character(), direction = integer()))
}

#' Validate artifact integrity and recover the frozen metadata.
#' @param directory Frozen design directory.
doc_frozen <- function(directory) {
  record <- jsonlite::read_json(safe_file(file.path(directory, "frozen.json"), directory))
  stopifnot(record$protocol == "document-v2")
  for (name in names(record$hashes)) stopifnot(
    file_hash(safe_file(file.path(directory, name), directory)) == record$hashes[[name]])
  record
}

#' Generate/import one setting, never redrawing undefined power.
#' @param config Document configuration.
#' @param row Dataset setting row.
#' @param index Fixed stream slot.
#' @param streams Preallocated independent RNG streams.
#' @param run_dir Destination run root.
#' @param historical Optional historical run for dense observations only.
doc_data <- function(config, row, index, streams, run_dir, historical) {
  path <- file.path(run_dir, "private", paste0(row$data_id, ".rds"))
  ensure_dir(dirname(path))
  if (file.exists(path)) return(doc_existing_data(path))
  if (!is.null(historical) && file.exists(file.path(historical, "private", paste0(row$data_id, ".rds"))))
    return(doc_import_snapshot(config, row, path, index, historical))
  origin <- "generated"
  old_id <- sub("^dense_", "", row$data_id)
  old <- if (!is.null(historical)) file.path(historical, "private", paste0(old_id, ".rds")) else ""
  if (row$regime == "dense" && file.exists(old)) {
    prior <- read_json(file.path(historical, "run.json"))$config
    for (field in c("seed", "alpha", "delta", "tau_squared", "max_n", "max_dataset_cells"))
      stopifnot(isTRUE(all.equal(prior[[field]], config[[field]], check.attributes = FALSE)))
    stopifnot(isTRUE(all.equal(prior$state_probabilities, config$regimes$dense, check.attributes = FALSE)))
    digest <- file_hash(old)
    stopifnot(file.copy(old, path), file_hash(path) == digest)
    setting <- readRDS(path)
    origin <- normalizePath(old)
  } else {
    cfg <- config
    cfg$state_probabilities <- config$regimes[[row$regime]]
    setting <- tryCatch(generate_setting(cfg, row$m, row$c,
      streams[(3*index-2):(3*index)]), error = function(e) list(error = conditionMessage(e)))
    saveRDS(setting, path, version = 3)
  }
  if (is.null(setting$error)) {
    expected <- smallest_sample(setting$effects, row$c, config$alpha, config$max_n)
    stopifnot(identical(expected$n, setting$planning$n))
  }
  write_json(list(origin = origin, sha256 = file_hash(path), stream_index = index,
    error = setting$error), sub(".rds$", "-provenance.json", path))
  if (is.null(setting$error)) colnames(setting$effects) <- colnames(setting$observations[[1]]$exposed)
  setting
}

#' Launch one fresh source session via Poetry; no evaluator results are supplied.
#' @param config Document configuration with resolved image.
#' @param scenario Scenario row.
#' @param setting Generated observations.
#' @param directory Scenario directory.
#' @param source Study index.
#' @param offline Whether to use the deterministic provider.
doc_session_execute <- function(config, scenario, setting, directory, source, offline) {
  base <- ensure_dir(file.path(directory, paste0("agent-", source)))
  input <- ensure_dir(file.path(base, "input"))
  write_pair(setting$observations[[source]], input)
  session <- list(session_id = paste0("session-", source), m = scenario$m, n = setting$planning$n,
    criterion = scenario$criterion, alpha = config$alpha/3, model = config$openai$model,
    input_dir = input, workspace = ensure_dir(file.path(base, "work")),
    audit_dir = ensure_dir(file.path(base, "audit")), project_root = project_root,
    sandbox = config$sandbox, limits = config$agent, openai = config$openai)
  path <- file.path(base, "session-config.json")
  write_json(session, path)
  args <- c("run", "python", "-m", "agents.document", "--session", path)
  if (offline) args <- c(args, "--offline")
  execution <- processx::run("poetry", args, wd = project_root, error_on_status = FALSE,
    timeout = config$openai$request_limit * config$openai$api_timeout_seconds +
      (config$agent$max_r_executions + config$agent$max_contract_repairs)*config$sandbox$timeout_seconds + 600,
    cleanup_tree = TRUE)
  writeLines(c(execution$stdout, execution$stderr), file.path(base, "controller.log"))
  file.exists(file.path(base, "frozen", "frozen.json"))
}

#' Execute or reuse one verified frozen design/input combination.
#' @param config Document configuration.
#' @param pair Observations, excluding simulation truth.
#' @param frozen Frozen artifact directory.
#' @param cache Run-local cache directory.
doc_evaluate <- function(config, pair, frozen, cache) {
  record <- doc_frozen(frozen)
  key <- object_hash(list(protocol = "document-v2", record$hashes, pair, config$alpha/3, config$sandbox))
  seed <- as.integer(strtoi(substr(key, 1, 7), 16))
  path <- file.path(cache, paste0(key, ".json"))
  if (file.exists(path) && file.exists(paste0(path, ".sha256"))) {
    log <- jsonlite::read_json(path)
    integrity <- read_json(paste0(path, ".sha256"))
    stopifnot(integrity$sha256 == file_hash(path))
  } else {
    input <- ensure_dir(tempfile("document-input-"))
    on.exit(unlink(input, recursive = TRUE))
    write_pair(pair, input)
    log <- doc_sandbox(list(mode = "document-evaluate", workspace = frozen, input_dir = input,
      measurements = colnames(pair$exposed), alpha = config$alpha/3,
      execution_seed = seed, sandbox = config$sandbox))
    doc_atomic(log, path)
    doc_atomic(list(sha256 = file_hash(path), seed = seed), paste0(path, ".sha256"))
  }
  doc_frozen(frozen)
  if (log$status != "ok") stop(log$error %||% "Execution failed")
  h <- doc_hypotheses(log$payload$hypotheses)
  stopifnot(identical(h, doc_hypotheses(record$hypotheses)))
  raw <- log$payload$result
  d <- doc_rows(raw$directional_results, list(measurement_id = character(), direction = integer(),
    p_value = numeric(), adjusted_p_value = numeric(), reject = logical()))
  o <- doc_rows(raw$outcome_results, list(measurement_id = character(), adjusted_p_value = numeric(), reject = logical()))
  result <- list(directional_results = d, outcome_results = o)
  doc_result(result, h, colnames(pair$exposed), config$alpha/3)
  result
}

#' Evaluate candidates and held-out targets without reading truth.
#' @param config Document configuration.
#' @param observations Three observation pairs only.
#' @param directory Scenario output directory.
#' @return Target results for pooled and cyclic routes; selection audit is saved.
doc_select <- function(config, observations, directory) {
  outputs <- list(agent_pooled_select = vector("list", 3), agent_cycle = vector("list", 3))
  candidates <- decisions <- list()
  cache <- ensure_dir(file.path(directory, "evaluations"))
  evaluate <- function(source, pair) tryCatch(doc_evaluate(config, pair,
    file.path(directory, paste0("agent-", source), "frozen"), cache), error = function(e) {
      writeLines(conditionMessage(e), file.path(cache, paste0("failure-", source, "-", substr(object_hash(pair),1,12), ".txt")))
      NULL
    })
  for (target in 1:3) {
    other <- setdiff(1:3, target)
    pooled <- pool_non_target(observations, target)
    fits <- lapply(other, evaluate, pair = pooled)
    rows <- do.call(rbind, lapply(seq_along(other), function(k) data.frame(target = target,
      source = other[k], status = if (is.null(fits[[k]])) "failed" else "ok",
      discoveries = if (is.null(fits[[k]])) NA_integer_ else sum(fits[[k]]$outcome_results$reject),
      directional_conflicts = if (is.null(fits[[k]])) NA_integer_ else
        sum(table(fits[[k]]$directional_results$measurement_id[fits[[k]]$directional_results$reject]) > 1))))
    winner <- choose_candidate(rows)
    decisions[[target]] <- data.frame(target = target, source = winner$source, tie = winner$tie,
      degraded = winner$degraded, status = winner$status,
      artifact_hash = doc_source_hash(directory, winner$source))
    candidates[[target]] <- rows
    if (!is.na(winner$source)) outputs$agent_pooled_select[target] <- list(evaluate(winner$source, observations[[target]]))
    outputs$agent_cycle[target] <- list(evaluate(if (target == 1) 3 else target-1, observations[[target]]))
  }
  write_csv(do.call(rbind, candidates), file.path(directory, "selection-candidates.csv"))
  write_csv(do.call(rbind, decisions), file.path(directory, "selection-decisions.csv"))
  outputs
}

#' Apply the document's nondirectional baseline to each study separately.
#' @param config Document configuration.
#' @param observations Three observation pairs.
#' @param criterion FWER or FDR.
doc_baseline <- function(config, observations, criterion) {
  lapply(observations, function(pair) {
    p <- vapply(seq_len(ncol(pair$exposed)), function(i)
      t.test(pair$exposed[, i], pair$unexposed[, i], alternative = "two.sided")$p.value, numeric(1))
    q <- p.adjust(p, if (criterion == "FWER") "holm" else "BH")
    list(outcome_results = data.frame(measurement_id = colnames(pair$exposed),
      adjusted_p_value = q, reject = q <= config$alpha/3), raw_p = p)
  })
}

#' Compute the six document totals and secondary count recovery.
#' @param effects Three-by-m truth matrix, used only after evaluation.
#' @param targets Three validated results, with NULL for failures.
#' @param alpha Overall level.
#' @return Per-outcome table and scalar summaries.
doc_scores <- function(effects, targets, alpha = 0.05) {
  ids <- colnames(effects)
  r <- colSums(effects != 0)
  complete <- all(vapply(targets, Negate(is.null), logical(1)))
  q <- sapply(targets, function(x) if (is.null(x)) rep(NA_real_, length(ids)) else
    x$outcome_results$adjusted_p_value[match(ids, x$outcome_results$measurement_id)])
  q <- matrix(q, nrow = length(ids), ncol = 3)
  lower <- rowSums(q <= alpha/3)
  global <- pmin(1, 3*apply(q, 1, min))
  repl <- pmin(1, 3*apply(q, 1, function(x) sort(x, na.last = TRUE)[2]))
  credit <- ifelse(r > 0, ifelse(lower <= r, lower/pmax(r, 1), 0), NA_real_)
  claims <- q <= alpha/3
  wrong <- colSums(t(claims) & effects == 0)
  table <- data.frame(measurement_id = ids, true_count = r, claimed_count = lower,
    wrong_study_count = wrong, complete = complete,
    recovery = credit, overclaim = lower > r, global_adjusted = global, replicability_adjusted = repl,
    q1 = q[, 1], q2 = q[, 2], q3 = q[, 3])
  totals <- c(claimed_studies = sum(lower), correct_lower_bound_credit = sum(lower*(lower <= r)),
    global_discoveries = sum(global <= alpha), true_global_discoveries = sum(global <= alpha & r > 0),
    replicability_discoveries = sum(repl <= alpha), true_replicability_discoveries = sum(repl <= alpha & r >= 2),
    study_count_recovery = if (any(r > 0)) mean(credit[r > 0]) else NA_real_,
    wrong_study_discoveries = sum(wrong),
    overclaimed_measurements = sum(lower > r), all_null_discoveries = sum(lower > 0 & r == 0))
  if (!complete) totals[] <- NA_real_
  list(table = table, summary = as.data.frame(as.list(c(complete = complete, totals))))
}

#' Truth-informed known-variance comparator, never available to source agents.
#' @param config Document configuration.
#' @param observations Three observation pairs.
#' @param effects True effects used only for this labeled oracle.
#' @param criterion FWER or FDR.
doc_oracle <- function(config, observations, effects, criterion) {
  lapply(1:3, function(j) {
    pair <- observations[[j]]
    direction <- ifelse(effects[j, ] < 0, -1L, 1L)
    z <- (colMeans(pair$exposed)-colMeans(pair$unexposed))/sqrt(2/nrow(pair$exposed))
    p <- pnorm(-z*direction)
    q <- p.adjust(p, if (criterion == "FWER") "holm" else "BH")
    d <- data.frame(measurement_id=colnames(pair$exposed),direction=as.integer(direction),
      p_value=p,adjusted_p_value=q,reject=q<=config$alpha/3)
    list(directional_results=d,outcome_results=d[c("measurement_id","adjusted_p_value","reject")])
  })
}
