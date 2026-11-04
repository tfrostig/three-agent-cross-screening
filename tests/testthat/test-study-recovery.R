testthat::test_that("count recovery covers every true and claimed count from zero to three", {
  for (r in 0:3) for (k in 0:3) {
    effects <- matrix(as.integer(1:3 <= r), 3, 1, dimnames = list(NULL, "a"))
    claims <- lapply(1:3, function(i) if (i <= k) "a" else character())
    table <- study_count_scores(effects, claims)
    expected <- if (r == 0) NA_real_ else if (k > r) 0 else k/r
    testthat::expect_equal(table$study_count_recovery, expected)
    testthat::expect_equal(table$claimed_study_count, k)
    testthat::expect_identical(table$overclaimed, k > r)
  }
})

testthat::test_that("recovery is macro averaged and missing targets are never zero", {
  effects <- cbind(a = c(1,0,0), b = c(1,1,1), null = c(0,0,0))
  table <- study_count_scores(effects, list(c("a","b","null"), character(), character()))
  summary <- summarize_study_counts(table)
  testthat::expect_equal(summary$study_count_recovery, mean(c(1,1/3)))
  testthat::expect_equal(summary$all_null_discoveries, 1L)
  testthat::expect_equal(summary$overclaimed_measurements, 1L)
  missing <- summarize_study_counts(study_count_scores(effects, list("a", NULL, character())))
  testthat::expect_false(missing$complete)
  testthat::expect_true(is.na(missing$study_count_recovery))
  testthat::expect_true(is.na(missing$overclaimed_measurements))
})

testthat::test_that("count-only credit can coexist with wrong study and directional errors", {
  effects <- matrix(c(1,0,0),3,1,dimnames=list(NULL,"a"))
  table <- study_count_scores(effects,list(character(),"a",character()))
  testthat::expect_equal(table$study_count_recovery,1)
  h <- data.frame(hypothesis_id=c("up","down"),measurement_id=c("a","a"),direction=c(1L,-1L))
  result <- data.frame(hypothesis_id=c("down","up"),p_value=c(.001,.001),reject=c(TRUE,TRUE),adjusted_p_value=c(.002,.002))
  testthat::expect_equal(discovered_measurements(h,result),"a")
  testthat::expect_equal(score_claims(h,result,c(a=0))$false,2L)
  testthat::expect_equal(score_claims(h,result,c(a=1))$false,1L)
})

testthat::test_that("pool routes exclude each held-out study and preserve aligned independent arms", {
  observations <- lapply(1:3,function(i) list(
    exposed=matrix(i,2,2,dimnames=list(NULL,c("a","b"))),
    unexposed=matrix(-i,2,2,dimnames=list(NULL,c("a","b")))))
  for(target in 1:3) {
    pooled <- pool_non_target(observations,target)
    testthat::expect_equal(nrow(pooled$exposed),4L)
    testthat::expect_setequal(unique(as.vector(pooled$exposed)),setdiff(1:3,target))
    testthat::expect_equal(pooled$unexposed,-pooled$exposed)
    changed <- observations
    changed[[target]]$exposed[,] <- 999
    testthat::expect_identical(pooled,pool_non_target(changed,target))
  }
})

testthat::test_that("selection handles ties, empty families, failures and input order", {
  candidates <- data.frame(source=c(2L,1L),status=c("ok","ok"),discoveries=c(0L,0L))
  testthat::expect_equal(choose_candidate(candidates)$source,1L)
  testthat::expect_true(choose_candidate(candidates)$tie)
  candidates$discoveries <- c(5L,2L)
  testthat::expect_equal(choose_candidate(candidates)$source,2L)
  testthat::expect_identical(choose_candidate(candidates),choose_candidate(candidates[2:1,]))
  candidates$status[1] <- "failed"
  testthat::expect_equal(choose_candidate(candidates)$source,1L)
  testthat::expect_true(choose_candidate(candidates)$degraded)
  candidates$status[] <- "failed"
  testthat::expect_true(is.na(choose_candidate(candidates)$source))
  testthat::expect_equal(choose_candidate(candidates)$status,"failed")
  h <- data.frame(hypothesis_id=character(),measurement_id=character(),direction=integer())
  testthat::expect_identical(discovered_measurements(h,empty_result()),character())
})

testthat::test_that("legacy streams and byte data are preserved when c=.9 is appended", {
  config <- load_config(file.path(project_root,"config/pilot.yml"))
  old <- config
  old$power_targets <- c(.2,.6)
  old_ids <- unique(scenario_grid(old)$data_id)
  testthat::expect_identical(setting_stream_ids(config)[1:6],old_ids)
  testthat::expect_equal(length(setting_stream_ids(config)),9L)
  old_streams <- seed_streams(config$seed,18L)
  new_streams <- seed_streams(config$seed,27L)
  testthat::expect_identical(old_streams,new_streams[1:18])
  effects <- matrix(c(.2,.5,1,1.4,0,.9,.8,1,.1),3)
  plan <- smallest_sample(effects,.9,.05)
  testthat::expect_gt(min(plan$power),.9)
  testthat::expect_lte(min(plan$previous_power),.9)
})

testthat::test_that("source reuse rejects changed snapshot bytes", {
  root <- ensure_dir(tempfile("reuse-snapshot-"))
  on.exit(unlink(root,recursive=TRUE))
  path <- file.path(root,"artifact.txt")
  writeLines("original",path)
  config <- list(reuse=list(path=root,files=list(artifact.txt=file_hash(path))))
  testthat::expect_identical(reuse_file(config,"artifact.txt"),normalizePath(path))
  writeLines("changed",path)
  testthat::expect_error(reuse_file(config,"artifact.txt"),"changed")
  testthat::expect_null(reuse_file(config,"missing.txt"))
})

testthat::test_that("candidate counts ignore truth and collapse conflicting directions", {
  h <- data.frame(hypothesis_id=c("up","down"),measurement_id=c("a","a"),direction=c(1L,-1L))
  r <- data.frame(hypothesis_id=c("up","down"),p_value=c(.001,.001),reject=c(TRUE,TRUE),adjusted_p_value=c(.002,.002))
  evaluate <- evaluate_candidate
  environment(evaluate) <- list2env(list(execute_frozen_pair=function(...) {
    list(hypotheses=h,result=r,hashes=list(analysis.R="fixture"),result_hash="fixture")
  }),parent=environment(evaluate_candidate))
  row <- evaluate(list(alpha=.05),list(),tempdir(),1L,3L)
  testthat::expect_identical(row$status,"ok")
  testthat::expect_equal(row$discoveries,1L)
  testthat::expect_equal(row$directional_conflicts,1L)
  testthat::expect_false("setting" %in% names(formals(evaluate_candidate)))
})

testthat::test_that("the run entrypoint forwards reuse mode before creating a run", {
  config <- load_config(file.path(project_root,"config/pilot.yml"))
  run <- run_pilot
  captured <- new.env(parent=emptyenv())
  environment(run) <- list2env(list(
    require_packages=function(...) NULL,
    validate_live_config=function(...) NULL,
    docker_info=function(...) "fixture-image",
    reference_pack_digest=function(...) "fixture-reference",
    prepare_reuse=function(config,path,offline) {
      captured$path<-path; captured$offline<-offline; stop("entrypoint_mode_checked")
    }),parent=environment(run_pilot))
  options <- list(scenario=NULL,dry_run=FALSE,offline=TRUE,reuse_run="fixture-source")
  testthat::expect_error(run(config,options),"entrypoint_mode_checked")
  testthat::expect_identical(captured$path,"fixture-source")
  testthat::expect_true(captured$offline)
})
