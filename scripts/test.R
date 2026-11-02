#' Run host-side testthat suites from the project root; no OpenAI calls or live scientific
#'   runs.

source("R/bootstrap.R")
testthat::test_dir("tests/testthat", stop_on_failure = TRUE)
