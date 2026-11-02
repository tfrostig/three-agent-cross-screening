#' Private bridge used by RRunner: positional request.json and result.json. Never pass
#'   untrusted shell commands or invoke generated R on the host.

source("R/bootstrap.R")
args <- commandArgs(trailingOnly = TRUE)
request <- read_json(args[1])
result <- tryCatch(execute_sandbox(request), error = function(error) {
  list(status = "failed", error = conditionMessage(error))
})
write_json(result, args[2])
