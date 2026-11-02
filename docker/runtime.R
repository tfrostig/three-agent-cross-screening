#' Entrypoint inside the restricted image, not a host script. Receives only mounted
#'   observations and code; writes status/result under /output.

source("/opt/runner/contracts.R")

#' Record a container-side analysis error
#'
#' @param error Caught R condition whose message is written to the container status file.
#' @return Writes /output/status.json with failed status and the exception message.
write_failure <- function(error) {
  jsonlite::write_json(list(status = "failed", error = conditionMessage(error)),
                       "/output/status.json", auto_unbox = TRUE)
}

#' Load and validate only the observation matrices mounted into a container
#'
#' @return List containing exposed and unexposed; has no access to simulation truth.
load_pair <- function() {
  exposed <- readRDS("/input/exposed.rds")
  unexposed <- readRDS("/input/unexposed.rds")
  validate_matrices(exposed, unexposed)
  list(exposed = exposed, unexposed = unexposed)
}

#' Evaluate exploratory R code in a fresh scope inside the container
#'
#' @param pair List with exposed and unexposed numeric observation matrices.
#' @return Executes /control/code.R with matrices and n/m; files in /work may be written.
run_exploration <- function(pair) {
  scope <- new.env(parent = globalenv())
  scope$exposed <- pair$exposed
  scope$unexposed <- pair$unexposed
  scope$n <- nrow(pair$exposed)
  scope$m <- ncol(pair$exposed)
  sys.source("/control/code.R", envir = scope)
}

#' Execute the staged reusable analysis and validate its output
#'
#' @param pair List with exposed and unexposed numeric observation matrices.
#' @param alpha Family level used directly; callers supply config$alpha/3 for target testing.
#' @return Writes /output/result.csv; checks the declared frozen family and result schema.
run_analysis <- function(pair, alpha) {
  hypotheses <- read_hypothesis_table("/design/hypotheses.csv")
  validate_hypotheses(hypotheses, colnames(pair$exposed))
  scope <- new.env(parent = globalenv())
  sys.source("/design/analysis.R", envir = scope)
  if (!is.function(scope$analyze)) stop("analysis.R must define analyze")
  result <- scope$analyze(pair$exposed, pair$unexposed, hypotheses, alpha)
  validate_result(result, hypotheses)
  utils::write.csv(result, "/output/result.csv", row.names = FALSE, na = "")
}

#' Dispatch container mode, seed execution, and write success status
#'
#' @param args Container arguments: mode, alpha, and execution seed, in that order.
#' @return Writes /output/status.json; the top-level handler records errors and exits nonzero.
main <- function(args) {
  setwd("/work")
  set.seed(as.integer(args[3]))
  pair <- load_pair()
  if (args[1] == "explore") run_exploration(pair)
  else run_analysis(pair, as.numeric(args[2]))
  jsonlite::write_json(list(status = "ok"), "/output/status.json", auto_unbox = TRUE)
}

tryCatch(main(commandArgs(trailingOnly = TRUE)), error = function(error) {
  write_failure(error)
  quit(status = 1L)
})
