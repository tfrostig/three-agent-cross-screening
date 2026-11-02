docker_info <- function(image) {
  result <- processx::run("docker", c("image", "inspect", image), error_on_status = FALSE)
  if (result$status != 0) stop("Docker image unavailable; run scripts/build_image.R")
  info <- jsonlite::fromJSON(result$stdout, simplifyVector = FALSE)[[1]]
  info$Id
}

mount_arg <- function(source, target, readonly = TRUE) {
  source <- normalizePath(source, mustWork = TRUE)
  if (grepl(",", source, fixed = TRUE)) stop("Mount paths cannot contain commas")
  c("--mount", paste0("type=bind,source=", source, ",target=", target,
                        if (readonly) ",readonly" else ""))
}

sandbox_args <- function(request, stage, output, name) {
  common <- c("run", "--rm", "--name", name, "--network=none", "--read-only",
              "--cap-drop=ALL", "--security-opt=no-new-privileges", "--pids-limit=128",
              "--memory", request$sandbox$memory, "--cpus", as.character(request$sandbox$cpus),
              "--user", "65534:65534", "--tmpfs", "/tmp:rw,nosuid,nodev,size=128m")
  args <- c(common, mount_arg(request$input_dir, "/input"),
            mount_arg(output, "/output", FALSE))
  if (request$mode == "explore") {
    args <- c(args, mount_arg(stage, "/control"), mount_arg(request$workspace, "/work", FALSE))
  } else args <- c(args, mount_arg(stage, "/design"), "--tmpfs", "/work:rw,nosuid,nodev,size=128m")
  c(args, request$sandbox$image, request$mode, as.character(request$alpha),
    as.character(request$execution_seed))
}

prepare_stage <- function(request, stage) {
  if (request$mode == "explore") {
    writeLines(request$code, file.path(stage, "code.R"), useBytes = TRUE)
  } else {
    for (name in c("analysis.R", "hypotheses.csv")) {
      path <- safe_file(file.path(request$workspace, name), request$workspace)
      file.copy(path, file.path(stage, name), overwrite = FALSE)
    }
  }
  Sys.chmod(list.files(stage, full.names = TRUE), "0444")
}

bounded_text <- function(path, limit) {
  if (!file.exists(path)) return("")
  connection <- file(path, "rb")
  on.exit(close(connection))
  rawToChar(readBin(connection, "raw", n = limit), multiple = FALSE)
}

run_container <- function(args, timeout, directory, name) {
  stdout <- file.path(directory, "stdout.log")
  stderr <- file.path(directory, "stderr.log")
  process <- processx::process$new("docker", args, stdout = stdout, stderr = stderr)
  on.exit(if (process$is_alive()) process$kill())
  started <- Sys.time()
  timed_out <- FALSE
  while (process$is_alive()) {
    elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
    sizes <- file.info(c(stdout, stderr))$size
    if (elapsed > timeout || sum(sizes, na.rm = TRUE) > 1024 * 1024) {
      timed_out <- TRUE
      processx::run("docker", c("rm", "-f", name), error_on_status = FALSE)
      process$kill()
      break
    }
    process$wait(100)
  }
  list(exit_code = process$get_exit_status(), timed_out = timed_out,
       stdout = bounded_text(stdout, 32768), stderr = bounded_text(stderr, 32768),
       truncated = any(file.info(c(stdout, stderr))$size > 32768, na.rm = TRUE))
}

execute_sandbox <- function(request) {
  stage <- ensure_dir(tempfile("stage-"))
  output <- ensure_dir(tempfile("output-"))
  on.exit(unlink(c(stage, output), recursive = TRUE))
  Sys.chmod(c(stage, output), "0777")
  prepare_stage(request, stage)
  name <- paste0("cross-screen-", substr(object_hash(list(Sys.time(), stage)), 1, 16))
  args <- sandbox_args(request, stage, output, name)
  result <- run_container(args, request$sandbox$timeout_seconds, output, name)
  result$status <- "failed"
  status_file <- file.path(output, "status.json")
  if (file.exists(status_file) && !nzchar(Sys.readlink(status_file))) {
    status <- read_json(status_file)
    result$status <- if (identical(result$exit_code, 0L)) status$status else "failed"
    result$error <- status$error %||% NULL
  }
  result_file <- file.path(output, "result.csv")
  if (request$mode != "explore" && result$status == "ok") {
    safe_file(result_file, output)
    if (file.info(result_file)$size > 2 * 1024 * 1024) stop("Result file exceeds 2 MiB")
    result$result <- read_result_table(result_file)
    exposed <- readRDS(file.path(request$input_dir, "exposed.rds"))
    hypotheses <- read_hypothesis_table(file.path(stage, "hypotheses.csv"))
    validate_hypotheses(hypotheses, colnames(exposed))
    validate_result(result$result, hypotheses)
    if (!is.null(request$result_file)) write_csv(result$result, request$result_file)
  }
  result$result <- NULL
  result
}
