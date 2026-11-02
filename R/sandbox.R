#' Trusted Docker wrapper for untrusted R; only explicit source/target inputs and staged
#'   artifacts cross the container boundary.

#' Resolve a locally available Docker image to its immutable ID
#'
#' @param image Docker image tag or immutable image identifier.
#' @return Image SHA-256 identifier; stops if Docker cannot inspect the image.
docker_info <- function(image) {
  result <- processx::run("docker", c("image", "inspect", image), error_on_status = FALSE)
  if (result$status != 0) stop("Docker image unavailable; run scripts/build_image.R")
  info <- jsonlite::fromJSON(result$stdout, simplifyVector = FALSE)[[1]]
  info$Id
}

#' Build a validated Docker bind-mount argument
#'
#' @param source Existing host directory to bind into the container.
#' @param target Absolute container mount path.
#' @param readonly Logical; append Docker's read-only mount option when TRUE.
#' @return Two CLI arguments; rejects source paths containing commas.
mount_arg <- function(source, target, readonly = TRUE) {
  source <- normalizePath(source, mustWork = TRUE)
  if (grepl(",", source, fixed = TRUE)) stop("Mount paths cannot contain commas")
  c("--mount", paste0("type=bind,source=", source, ",target=", target,
                        if (readonly) ",readonly" else ""))
}

#' Construct the restricted R-container invocation
#'
#' @param request Trusted request list with mode, input_dir, workspace, alpha, execution_seed,
#'   and sandbox settings.
#' @param stage Temporary directory containing only code or staged analysis artifacts.
#' @param output Destination directory or file, as indicated in the description.
#' @param name Unique Docker container name for this execution.
#' @return Character vector of Docker arguments with mounts, resource limits, no network, and
#'   a non-root user.
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

#' Stage exploration code or the two executable design files
#'
#' @param request Trusted request list with mode, input_dir, workspace, alpha, execution_seed,
#'   and sandbox settings.
#' @param stage Temporary directory containing only code or staged analysis artifacts.
#' @return Writes read-only files in stage; report text and host-private files are never
#'   staged.
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

#' Read at most a fixed number of captured output bytes
#'
#' @param path Input or destination filesystem path, as indicated in the description.
#' @param limit Maximum number of output bytes to read.
#' @return Character output, or an empty string for a missing file.
bounded_text <- function(path, limit) {
  if (!file.exists(path)) return("")
  connection <- file(path, "rb")
  on.exit(close(connection))
  rawToChar(readBin(connection, "raw", n = limit), multiple = FALSE)
}

#' Run Docker with wall-time and output-volume safeguards
#'
#' @param args Docker CLI arguments from sandbox_args().
#' @param timeout Maximum permitted wall-clock seconds.
#' @param directory Filesystem directory holding the relevant inputs or outputs.
#' @param name Unique container name used for forced removal at resource limits.
#' @return List containing exit_code, timed_out, bounded stdout/stderr, and truncated.
#'   timed_out also marks the combined-output ceiling.
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

#' Stage, execute, and validate one untrusted R request
#'
#' @param request Trusted request list with mode, input_dir, workspace, alpha, execution_seed,
#'   and sandbox settings.
#' @return Bounded execution metadata; optionally publishes a validated result CSV. Temporary
#'   stage/output directories are removed on exit.
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
