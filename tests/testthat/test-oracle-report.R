local({
  previous <- setwd(project_root)
  on.exit(setwd(previous))
  source("analyses/restructure_document_report.R")
  source("analyses/audit_oracle.R")
})

testthat::test_that("truth ceilings count all true effects independently of reported discoveries", {
  root <- ensure_dir(tempfile("truth-ceilings-"))
  pairs <- data.frame(id="fixture",regime="dense",criterion="FWER",m=4,c=.6)
  write_csv(pairs,file.path(root,"paired-comparisons.csv"))
  outcomes <- data.frame(measurement_id=paste0("v",1:4),true_count=0:3,q1=1)
  for(method in c("agent_pooled_select","welch_two_sided","oracle_z_secondary"))
    write_csv(outcomes,file.path(root,"scenarios/fixture",method,"outcomes.csv"))
  truth <- reader_truth_ceiling(root)
  testthat::expect_equal(truth$available_true_study_effects,6)
  testthat::expect_equal(truth$available_global_alternatives,3)
  testthat::expect_equal(truth$available_replicable_outcomes,2)
  outcomes$q1 <- .0001
  path <- file.path(root,"scenarios/fixture/welch_two_sided/outcomes.csv")
  write_csv(outcomes,path)
  testthat::expect_equal(reader_truth_ceiling(root),truth)
  outcomes$true_count[4] <- 2
  write_csv(outcomes,path)
  testthat::expect_error(reader_truth_ceiling(root))
})

testthat::test_that("oracle uses known variances, true signs and every outcome including nulls", {
  ids <- paste0("v",1:3)
  pair <- list(exposed=matrix(rep(c(2,-2,.4),each=4),4,3,dimnames=list(NULL,ids)),
    unexposed=matrix(0,4,3,dimnames=list(NULL,ids)))
  setting <- list(observations=rep(list(pair),3),effects=matrix(rep(c(1,-1,0),each=3),3,3))
  for(criterion in c("FWER","FDR")) {
    fits <- doc_oracle(list(alpha=.05),setting$observations,setting$effects,criterion)
    targets <- jsonlite::fromJSON(jsonlite::toJSON(fits,dataframe="rows",auto_unbox=TRUE,digits=17),simplifyVector=FALSE)
    row <- data.frame(id="fixture",regime="dense",criterion=criterion,m=3,c=.6)
    result <- audit_oracle_study(row,setting,targets[[1]],1)
    testthat::expect_true(result$verified)
    testthat::expect_equal(result$tested_outcomes,3)
    testthat::expect_equal(result$true_nulls_tested,1)
    testthat::expect_equal(fits[[1]]$directional_results$direction,c(1L,-1L,1L))
    targets[[1]]$directional_results[[1]]$direction <- -1L
    testthat::expect_error(audit_oracle_study(row,setting,targets[[1]],1))
  }
})
