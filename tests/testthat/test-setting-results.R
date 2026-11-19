local({
  previous <- setwd(project_root)
  on.exit(setwd(previous))
  source("analyses/restructure_document_report.R")
})

setting_fixture_directory <- function(root) {
  config <- read_pilot_config(character())
  grid <- doc_grid(config)
  failed <- c("sparse_fwer_m20_c20","sparse_fwer_m20_c90")
  done <- grid[!grid$id %in% failed,]
  methods <- c("agent_pooled_select","agent_cycle","welch_two_sided","oracle_z_secondary")
  values <- list(c(3,3,2,2,1,1),c(2,2,1,1,1,1),c(4,4,2,2,1,1),c(5,5,3,3,2,2))
  summary <- do.call(rbind,lapply(seq_len(nrow(done)),function(i) do.call(rbind,
    lapply(seq_along(methods),function(j) data.frame(done[i,c("id","regime","criterion","m","c")],
      method=methods[j],complete=1,as.list(setNames(values[[j]],names(reader_measure_names()))))))))
  write_json(list(config=config),file.path(root,"run.json"))
  write_csv(grid,file.path(root,"scenarios.csv"))
  write_csv(data.frame(scenario=failed,error="undefined_power: subgroup has no signals"),file.path(root,"failures.csv"))
  write_csv(data.frame(data_id=unique(grid$data_id),n=40),file.path(root,"planning.csv"))
  write_csv(summary,file.path(root,"summary.csv"))
  write_csv(done[c("id","regime","criterion","m","c")],file.path(root,"paired-comparisons.csv"))
  for(i in seq_len(nrow(done))) for(method in methods[methods!="agent_cycle"]) {
    outcomes <- data.frame(measurement_id=sprintf("v%04d",seq_len(done$m[i])),
      true_count=c(3,2,1,rep(0,done$m[i]-3)))
    write_csv(outcomes,file.path(root,"scenarios",done$id[i],method,"outcomes.csv"))
  }
  root
}

testthat::test_that("Cartesian results distinguish planned, undefined and unplanned cells", {
  root <- setting_fixture_directory(ensure_dir(tempfile("settings-fixture-")))
  data <- setting_result_data(root)
  testthat::expect_equal(nrow(data$grid),36)
  testthat::expect_equal(sum(data$grid$planned),24)
  testthat::expect_equal(sum(data$grid$status=="complete"),22)
  testthat::expect_equal(sum(data$grid$status=="undefined_planning"),2)
  testthat::expect_equal(sum(data$grid$status=="not_planned"),12)
  missing <- data$grid[data$grid$status!="complete",]
  testthat::expect_true(all(is.na(missing$n_per_arm)))
  for(i in seq_len(nrow(missing))) {
    rows <- setting_measure_rows(missing[i,],data)
    testthat::expect_true(all(is.na(as.matrix(rows[c(data$methods,"maximum_true_discoveries")]))))
  }
  row <- data$grid[data$grid$id=="dense_fwer_m20_c20",]
  rows <- setting_measure_rows(row,data)
  testthat::expect_equal(rows$agent_pooled_select,c(3,3,2,2,1,1))
  testthat::expect_equal(rows$welch_two_sided,c(4,4,2,2,1,1))
  testthat::expect_equal(rows$oracle_z_secondary,c(5,5,3,3,2,2))
  testthat::expect_equal(rows$maximum_true_discoveries,c(NA,6,NA,3,NA,2))
  testthat::expect_equal(nrow(do.call(rbind,lapply(seq_len(nrow(data$grid)),
    function(i) setting_measure_rows(data$grid[i,],data)))),216)
})
