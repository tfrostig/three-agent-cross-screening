source(file.path(project_root, "analyses/audit_measures.R"))

testthat::test_that("independent measure audit distinguishes bound units from correct outcomes", {
  root <- ensure_dir(tempfile("measure-audit-"))
  ids <- c("v0001", "v0002", "v0003")
  effects <- cbind(c(1,1,0), c(0,0,1), c(0,0,0))
  colnames(effects) <- ids
  decisions <- cbind(c(TRUE,FALSE,TRUE), c(TRUE,TRUE,FALSE), c(FALSE,TRUE,FALSE))
  targets <- lapply(1:3, function(j) {
    p <- ifelse(decisions[j, ], .001, 1)
    list(raw_p=p, outcome_results=data.frame(measurement_id=ids, adjusted_p_value=p, reject=decisions[j, ]))
  })
  setting <- list(effects=effects)
  scenario <- data.frame(id="fixture",regime="dense",m=3,c=.6,criterion="FWER")
  row <- doc_save_method("fixture",targets,setting,scenario,ensure_dir(file.path(root,"scenarios/fixture")))
  truth <- list(ids=ids,count=colSums(effects != 0))
  result <- audit_measure_row(row,root,truth)
  testthat::expect_equal(result$claimed_studies,5)
  testthat::expect_equal(result$correct_lower_bound_credit,2)
  testthat::expect_equal(result$positive_correct_bound_outcomes,1)
  testthat::expect_equal(result$true_replicability_discoveries,1)
  row$global_discoveries <- row$global_discoveries+1
  testthat::expect_error(audit_measure_row(row,root,truth))
})
