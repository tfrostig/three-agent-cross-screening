#' Private bridge used by RRunner: positional request.json and result.json. Never pass
#'   untrusted shell commands or invoke generated R on the host.

source("R/bootstrap.R")
args <- commandArgs(trailingOnly = TRUE)
request <- read_json(args[1])
source("R/document_sandbox.R")
result <- tryCatch({
  stopifnot(request$mode %in% c("explore", "document-inspect", "document-evaluate"))
  if (request$mode == "explore") execute_sandbox(request) else doc_sandbox(request)
}, error = function(error) {
  list(status = "failed", error = conditionMessage(error))
})
write_json(result, args[2])
