#' CLI: --config FILE and --offline. Check dependencies, Pandoc, reference digest, Docker
#'   image, and (unless offline) private credential availability.

source("R/bootstrap.R")
args <- commandArgs(trailingOnly = TRUE)
config <- read_pilot_config(args)
offline <- "--offline" %in% args
doc_preflight(config, offline)
