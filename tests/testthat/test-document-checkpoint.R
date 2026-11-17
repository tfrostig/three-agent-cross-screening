source(file.path(project_root,"R/document_pipeline.R"))

testthat::test_that("committed source checkpoints skip the model and interrupted sources do not restart", {
  root <- ensure_dir(tempfile("source-checkpoint-"))
  frozen <- ensure_dir(file.path(root,"agent-1","frozen"))
  writeLines("x <- 1",file.path(frozen,"analysis.R"))
  write_json(list(protocol="document-v2",hashes=list(analysis.R=file_hash(file.path(frozen,"analysis.R")))),file.path(frozen,"frozen.json"))
  write_json(list(frozen_sha256=file_hash(file.path(frozen,"frozen.json"))),file.path(frozen,"complete.json"))
  testthat::expect_true(doc_session(NULL,NULL,NULL,root,1,TRUE))
  testthat::expect_equal(read_json(file.path(root,"agent-1/checkpoint.json"))$status,"frozen")
  base <- ensure_dir(file.path(root,"agent-2"))
  write_json(list(status="running"),file.path(base,"checkpoint.json"))
  testthat::expect_false(doc_session(NULL,NULL,NULL,root,2,TRUE))
  testthat::expect_equal(read_json(file.path(base,"checkpoint.json"))$status,"failed")
  testthat::expect_equal(read_json(file.path(base,"audit/session.json"))$physical_api_attempts,0)
})

testthat::test_that("resume refuses changed configuration and modified input preview", {
  config <- yaml::read_yaml(file.path(project_root,"config/pilot.yml"))
  grid <- doc_grid(config)
  options <- list(run_dir=tempfile("resume-test-"),resume=FALSE,offline=TRUE)
  original <- doc_preview
  assign("doc_preview",function(path) writeLines("technical interface",path),envir=.GlobalEnv)
  on.exit(assign("doc_preview",original,envir=.GlobalEnv))
  run <- doc_initialize(config,options,grid)
  options$resume <- TRUE
  testthat::expect_equal(doc_initialize(config,options,grid),run)
  changed <- config
  changed$openai$model <- "different-model"
  testthat::expect_error(doc_initialize(changed,options,grid))
  writeLines("modified",file.path(run,"prompt-preview.md"))
  testthat::expect_error(doc_initialize(config,options,grid))
})

testthat::test_that("dataset seals reject changed bytes", {
  root <- ensure_dir(tempfile("dataset-seal-"))
  ensure_dir(file.path(root,"private"))
  path <- file.path(root,"private/a.rds")
  saveRDS(list(a=1),path)
  doc_seal_data(root,"a")
  testthat::expect_silent(doc_seal_data(root,"a"))
  saveRDS(list(a=2),path)
  testthat::expect_error(doc_seal_data(root,"a"))
})

testthat::test_that("scenario checkpoints reject tampered score files", {
  root <- ensure_dir(tempfile("scenario-checkpoint-"))
  scores <- data.frame(method="fixture",complete=1)
  doc_commit_scenario(root,scores)
  testthat::expect_equal(doc_scenario_checkpoint(root),scores)
  write_csv(data.frame(method="changed",complete=0),file.path(root,"scenario-summary.csv"))
  testthat::expect_error(doc_scenario_checkpoint(root))
})
