source("/opt/runner/contracts.R")

write_failure <- function(error) {
  jsonlite::write_json(list(status = "failed", error = conditionMessage(error)),
                       "/output/status.json", auto_unbox = TRUE)
}

load_pair <- function() {
  exposed <- readRDS("/input/exposed.rds")
  unexposed <- readRDS("/input/unexposed.rds")
  validate_matrices(exposed, unexposed)
  list(exposed = exposed, unexposed = unexposed)
}

run_exploration <- function(pair) {
  scope <- new.env(parent = globalenv())
  scope$exposed <- pair$exposed
  scope$unexposed <- pair$unexposed
  scope$n <- nrow(pair$exposed)
  scope$m <- ncol(pair$exposed)
  sys.source("/control/code.R", envir = scope)
}

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
