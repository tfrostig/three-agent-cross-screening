#' CLI: --run-dir DIR. Rebuild the full saved-run HTML report; needs local private setting
#'   files, never calls agents.

source("R/bootstrap.R")
args <- commandArgs(trailingOnly = TRUE)
directory <- cli_value(args, "--run-dir")
if (is.null(directory)) stop("Provide --run-dir")
render_pilot_report(directory)
