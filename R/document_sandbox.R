#' Execute generated document-protocol code with the existing restricted wrapper.
#' @param request Trusted request including measurement names and sandbox settings.
#' @return Bounded execution log and optional structured payload.
doc_sandbox <- function(request) {
  stage <- ensure_dir(tempfile("document-stage-"))
  output <- ensure_dir(tempfile("document-output-"))
  on.exit(unlink(c(stage, output), recursive = TRUE))
  Sys.chmod(c(stage, output), "0777")
  source <- safe_file(file.path(request$workspace, "analysis.R"), request$workspace)
  stopifnot(file.info(source)$size <= 262144)
  file.copy(source, file.path(stage, "analysis.R"))
  jsonlite::write_json(request$measurements, file.path(stage, "measurements.json"))
  Sys.chmod(list.files(stage, full.names = TRUE), "0444")
  name <- paste0("document-", substr(object_hash(stage), 1, 16))
  args <- sandbox_args(request, stage, output, name)
  if (request$mode == "document-inspect") {
    index <- match(mount_arg(request$input_dir, "/input")[2], args)
    args <- args[-c(index - 1L, index)]
  }
  args[length(args)-1L] <- sprintf("%.17g", request$alpha)
  log <- run_container(args, request$sandbox$timeout_seconds, output, name)
  log$status <- "failed"
  path <- file.path(output, "status.json")
  if (file.exists(path)) {
    status <- read_json(safe_file(path, output))
    log$error <- status$error
    if (identical(log$exit_code, 0L) && identical(status$status, "ok")) log$status <- "ok"
  }
  if (log$status != "ok") return(log)
  path <- safe_file(file.path(output, "document.json"), output)
  stopifnot(file.info(path)$size <= 2*1024^2)
  log$payload <- jsonlite::read_json(path, simplifyVector = FALSE)
  log
}
