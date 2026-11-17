testthat::test_that("the sole default configuration uses the approved prompt", {
  config <- read_pilot_config(character())
  testthat::expect_identical(config$protocol, "document-v2")
  testthat::expect_identical(config$scientific_prompt, "prompts/system.txt")
  testthat::expect_silent(doc_config(config))
  testthat::expect_equal(read_pilot_config(c("--config", file.path(project_root,"config/pilot.yml"))), config)
})

testthat::test_that("the default CLI dry run needs no output directory, credentials or Docker", {
  result <- processx::run("Rscript", c("--vanilla", "scripts/run_pilot.R", "--dry-run"),
    wd = project_root, error_on_status = FALSE)
  testthat::expect_identical(result$status, 0L)
  testthat::expect_match(result$stdout, "dense_fdr_m100_c20", fixed = TRUE)
  testthat::expect_match(result$stdout, "sparse_fwer_m100_c90", fixed = TRUE)
  testthat::expect_match(result$stdout, "Source designs: 72", fixed = TRUE)
})
