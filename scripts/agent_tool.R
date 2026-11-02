source("R/bootstrap.R")
args <- commandArgs(trailingOnly = TRUE)
request <- read_json(args[1])
result <- tryCatch(execute_sandbox(request), error = function(error) {
  list(status = "failed", error = conditionMessage(error))
})
write_json(result, args[2])
