#' CLI: --run-dir DIR. Export exact R source from existing audit requests; never execute the
#'   extracted snippets.

source("R/bootstrap.R")

#' Export exact submitted R bytes without replacing different content
#'
#' @param code Exact exploratory R source submitted to run_r.
#' @param output Destination directory or file, as indicated in the description.
#' @return Creates output or verifies identical existing source; stops on a mismatch.
write_exploration_source <- function(code, output) {
  bytes <- charToRaw(enc2utf8(code))
  if (file.exists(output)) {
    existing <- readBin(output, "raw", n = file.info(output)$size)
    if (!identical(existing, bytes)) stop("Existing R source differs from request: ", output)
  } else {
    ensure_dir(dirname(output))
    writeBin(bytes, output)
  }
}

#' Convert one recorded explore request into an R file and index row
#'
#' @param path Input or destination filesystem path, as indicated in the description.
#' @param run_dir Saved run directory containing metadata, scenarios, scores, and host-private
#'   inputs.
#' @return One-row metadata data frame, or NULL for non-exploration modes.
export_exploration_request <- function(path, run_dir) {
  request <- read_json(path)
  if (!identical(request$mode, "explore")) return(NULL)
  stopifnot(is.character(request$code), length(request$code) == 1L)
  execution <- tools::file_path_sans_ext(basename(path))
  output <- file.path(dirname(path), "exploration", paste0(execution, ".R"))
  write_exploration_source(request$code, output)
  relative <- function(x) substring(x, nchar(run_dir) + 2L)
  agent <- dirname(dirname(path))
  result <- file.path(dirname(path), paste0(execution, "-result.json"))
  status <- if (file.exists(result)) read_json(result)$status %||% "unknown" else "missing"
  data.frame(scenario = basename(dirname(agent)), agent = basename(agent), execution = execution,
    code_file = relative(output), request_file = relative(path),
    result_file = if (file.exists(result)) relative(result) else "",
    execution_seed = request$execution_seed, sha256 = file_hash(output), status = status)
}

#' Describe how archived exploratory snippets depend on their original setup
#'
#' @return Character lines for exploration-README.md.
exploration_readme <- function() {
  c("# Archived exploratory R code", "",
    "exploration-index.csv lists every exported exploration call, its source file, original request, result, execution seed, and SHA-256 digest. Paths are relative to this run directory.", "",
    "Each agent's code is under scenarios/<scenario>/agent-<number>/audit/exploration/execution-<number>.R. These files contain the exact submitted source, without added headers or replay code. Failed attempts are retained too.", "",
    "The corresponding audit/execution-<number>-result.json contains the recorded output and errors. audit/messages.json records the tool exchanges returned to the agent.", "",
    "Each call originally ran in a fresh R container with exposed and unexposed matrices already loaded and its execution seed initialized. The snippets are not standalone scripts: they depend on that setup, and some write design artifacts. Exporting does not execute them.", "",
    "Original JSON records, source data, frozen designs, and scores are unchanged. Future exploration calls automatically save the same .R files before execution, including attempts that subsequently fail.", "",
    "From the project root, rebuild the index without model calls or R exploration execution:", "",
    "```sh", "Rscript --vanilla scripts/export_exploration.R --run-dir results/live-first", "```")
}

#' Export saved exploration calls and build their index
#'
#' @param run_dir Saved run directory containing metadata, scenarios, scores, and host-private
#'   inputs.
#' @return Writes .R copies, exploration-index.csv, and a reading guide without executing R
#'   snippets or calling models.
export_exploration <- function(run_dir) {
  run_dir <- normalizePath(run_dir, mustWork = TRUE)
  paths <- sort(list.files(file.path(run_dir, "scenarios"),
    pattern = "^execution-[0-9]+\\.json$", recursive = TRUE, full.names = TRUE))
  rows <- Filter(Negate(is.null), lapply(paths, export_exploration_request, run_dir = run_dir))
  if (!length(rows)) stop("No recorded exploration calls found")
  index <- do.call(rbind, rows)
  write_csv(index, file.path(run_dir, "exploration-index.csv"))
  writeLines(exploration_readme(), file.path(run_dir, "exploration-README.md"), useBytes = TRUE)
  message("Saved ", nrow(index), " exploration scripts across ",
    length(unique(paste(index$scenario, index$agent))), " sessions: ", run_dir)
  invisible(index)
}

if (sys.nframe() == 0L) {
  export_exploration(cli_value(commandArgs(trailingOnly = TRUE), "--run-dir", "results/live-first"))
}
