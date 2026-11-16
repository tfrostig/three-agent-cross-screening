source(file.path(project_root, "R/document_pipeline.R"))

testthat::test_that("document grid, planning and old stream assignments are stable", {
  cfg <- yaml::read_yaml(file.path(project_root, "config/document-pilot.yml"))
  doc_config(cfg)
  grid <- doc_grid(cfg)
  testthat::expect_equal(nrow(grid), 24)
  testthat::expect_equal(length(unique(grid$data_id)), 18)
  testthat::expect_equal(setting_stream_ids(cfg), setting_stream_ids(load_config(file.path(project_root, "config/pilot.yml"))))
  testthat::expect_error(smallest_sample(matrix(0, 3, 2), .2, .05), "undefined_power")
})

testthat::test_that("all count combinations use document lower-bound credit", {
  ids <- c("v0001", "v0002")
  for (r in 0:3) for (claimed in 0:3) {
    effects <- matrix(0, 3, 2, dimnames = list(NULL, ids))
    if (r) effects[seq_len(r), 1] <- 1
    targets <- lapply(1:3, function(j) list(outcome_results = data.frame(measurement_id = ids,
      adjusted_p_value = c(if (j <= claimed) .001 else 1, 1), reject = c(j <= claimed, FALSE))))
    scored <- doc_scores(effects, targets)
    testthat::expect_equal(scored$summary$claimed_studies, claimed)
    testthat::expect_equal(scored$summary$correct_lower_bound_credit, if (claimed <= r) claimed else 0)
    testthat::expect_equal(scored$table$claimed_count[1], claimed)
    if (r) testthat::expect_equal(scored$summary$study_count_recovery, if (claimed <= r) claimed/r else 0)
    else testthat::expect_true(is.na(scored$summary$study_count_recovery))
  }
})

testthat::test_that("missing targets do not receive complete aggregate scores", {
  effects <- matrix(1, 3, 1, dimnames = list(NULL, "v0001"))
  fit <- list(outcome_results = data.frame(measurement_id="v0001",adjusted_p_value=.001,reject=TRUE))
  result <- doc_scores(effects, list(fit, NULL, fit))
  testthat::expect_false(as.logical(result$summary$complete))
  testthat::expect_true(is.na(result$summary$replicability_discoveries))
})

testthat::test_that("submission inspection does not apply the analysis", {
  script <- tempfile(fileext=".R")
  writeLines(c('hypotheses <- data.frame(measurement_id="v0001",direction=1L)',
    'analyze <- function(exposed, unexposed, alpha) stop("must not execute")'), script)
  scope <- doc_definitions(script, "v0001")
  testthat::expect_true(is.function(scope$analyze))
  testthat::expect_error(doc_family(data.frame(measurement_id="v0001",direction=1),"v0001"))
})

testthat::test_that("both-direction results are validated without inventing combination", {
  h <- data.frame(measurement_id=c("v0001","v0001"),direction=c(1L,-1L))
  d <- data.frame(h,p_value=c(.001,.999),adjusted_p_value=c(.002,1),reject=c(TRUE,FALSE))
  o <- data.frame(measurement_id=c("v0001","v0002"),adjusted_p_value=c(.002,1),reject=c(TRUE,FALSE))
  fit <- list(directional_results=d,outcome_results=o)
  testthat::expect_silent(doc_result(fit,h,c("v0001","v0002"),.05/3))
  fit$outcome_results$reject[1] <- FALSE
  testthat::expect_error(doc_result(fit,h,c("v0001","v0002"),.05/3))
  testthat::expect_equal(choose_candidate(data.frame(source=c(2,1),status="ok",discoveries=2))$source,1)
})

testthat::test_that("selection uses only pooled non-target inputs and handles failures", {
  directory <- tempfile("selection-test-")
  ensure_dir(directory)
  observations <- lapply(1:3, function(j) list(exposed=matrix(j,2,1,dimnames=list(NULL,"v0001")),
    unexposed=matrix(0,2,1,dimnames=list(NULL,"v0001"))))
  original <- doc_evaluate
  on.exit(assign("doc_evaluate", original, envir=.GlobalEnv))
  assign("doc_evaluate", function(config,pair,frozen,cache) {
    source <- as.integer(sub(".*agent-([123])/frozen$","\\1",frozen))
    if (source == 2) stop("synthetic candidate failure")
    list(outcome_results=data.frame(measurement_id="v0001",adjusted_p_value=.001,reject=TRUE),
      directional_results=data.frame(measurement_id="v0001",direction=1L,p_value=.001,
        adjusted_p_value=.001,reject=TRUE))
  }, envir=.GlobalEnv)
  doc_select(list(),observations,directory)
  before <- read_csv(file.path(directory,"selection-decisions.csv"))
  observations[[1]]$exposed[,] <- 999
  doc_select(list(),observations,directory)
  after <- read_csv(file.path(directory,"selection-decisions.csv"))
  testthat::expect_equal(before$source[1],3)
  testthat::expect_true(before$degraded[1])
  testthat::expect_equal(before[1,],after[1,])
  for (target in 1:3) testthat::expect_equal(nrow(pool_non_target(observations,target)$exposed),4)
  testthat::expect_equal(choose_candidate(data.frame(source=1:2,status="failed",discoveries=NA))$status,"failed")
})

testthat::test_that("count recovery does not conceal directional errors", {
  effects <- matrix(c(1,0,0),3,1,dimnames=list(NULL,"v0001"))
  empty <- list(outcome_results=data.frame(measurement_id="v0001",adjusted_p_value=1,reject=FALSE))
  wrong <- list(outcome_results=data.frame(measurement_id="v0001",adjusted_p_value=.001,reject=TRUE),
    directional_results=data.frame(measurement_id="v0001",direction=-1L,p_value=.001,
      adjusted_p_value=.001,reject=TRUE))
  targets <- list(empty,wrong,empty)
  testthat::expect_equal(doc_scores(effects,targets)$summary$study_count_recovery,1)
  testthat::expect_equal(doc_directional(effects,targets)$false_discoveries,1)
  testthat::expect_equal(doc_scores(effects,targets)$summary$global_discoveries,1)
  testthat::expect_equal(doc_scores(effects,targets)$summary$replicability_discoveries,0)
})

testthat::test_that("empty families and weighted adjusted values are valid", {
  h <- data.frame(measurement_id=character(),direction=integer())
  d <- data.frame(h,p_value=numeric(),adjusted_p_value=numeric(),reject=logical())
  o <- data.frame(measurement_id="v0001",adjusted_p_value=1,reject=FALSE)
  testthat::expect_silent(doc_result(list(directional_results=d,outcome_results=o),h,"v0001",.05/3))
  h <- data.frame(measurement_id="v0001",direction=1L)
  d <- data.frame(h,p_value=.02,adjusted_p_value=.01,reject=TRUE)
  o$adjusted_p_value <- .01
  o$reject <- TRUE
  testthat::expect_silent(doc_result(list(directional_results=d,outcome_results=o),h,"v0001",.05/3))
})

testthat::test_that("frozen integrity checks reject changed or linked designs", {
  directory <- ensure_dir(tempfile("integrity-test-"))
  script <- file.path(directory,"analysis.R")
  writeLines("x <- 1",script)
  write_json(list(protocol="document-v2",hashes=list(analysis.R=file_hash(script))),file.path(directory,"frozen.json"))
  testthat::expect_silent(doc_frozen(directory))
  writeLines("x <- 2",script)
  testthat::expect_error(doc_frozen(directory))
})

testthat::test_that("baseline is two-sided per-study Welch with Holm or BH", {
  set.seed(123)
  pair <- list(exposed=matrix(rnorm(20),10,2,dimnames=list(NULL,c("v0001","v0002"))),
    unexposed=matrix(rnorm(20),10,2,dimnames=list(NULL,c("v0001","v0002"))))
  p <- vapply(1:2,function(i)t.test(pair$exposed[,i],pair$unexposed[,i],alternative="two.sided")$p.value,numeric(1))
  for (criterion in c("FWER","FDR")) {
    result <- doc_baseline(list(alpha=.05),rep(list(pair),3),criterion)
    testthat::expect_equal(result[[1]]$raw_p,p)
    testthat::expect_equal(result[[1]]$outcome_results$adjusted_p_value,p.adjust(p,if(criterion=="FWER")"holm" else "BH"))
    testthat::expect_null(result[[1]]$directional_results)
  }
})
