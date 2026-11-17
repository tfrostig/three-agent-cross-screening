testthat::test_that("current CLI configuration is the default and legacy selection is explicit", {
  current <- read_pilot_config(character())
  testthat::expect_identical(current$protocol, "document-v2")
  testthat::expect_identical(current$scientific_prompt, "prompts/document-20261111.txt")
  legacy <- read_pilot_config(c("--config", "config/pilot.yml"))
  testthat::expect_null(legacy$protocol)
  testthat::expect_silent(validate_config(legacy))
})

testthat::test_that("the actual default CLI dry run chooses the current three-subgroup protocol", {
  result <- processx::run("Rscript", c("--vanilla", "scripts/run_pilot.R", "--dry-run"),
    wd = project_root, error_on_status = FALSE)
  testthat::expect_identical(result$status, 0L)
  testthat::expect_match(result$stdout, "dense_fdr_m100_c20", fixed = TRUE)
  testthat::expect_match(result$stdout, "sparse_fwer_m100_c90", fixed = TRUE)
  testthat::expect_match(result$stdout, "Source designs: 72", fixed = TRUE)
  legacy <- processx::run("Rscript", c("--vanilla", "scripts/run_pilot.R", "--config", "config/pilot.yml", "--dry-run"),
    wd = project_root, error_on_status = FALSE)
  testthat::expect_identical(legacy$status, 0L)
  testthat::expect_match(legacy$stdout, "Source designs: 36", fixed = TRUE)
})
