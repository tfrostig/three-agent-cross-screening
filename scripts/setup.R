#' CLI: --restore restores renv.lock; default installs missing host packages and refreshes the
#'   lockfile. Requires package-download network access.

library_directory <- file.path(getwd(), "renv", "library", "local")
dir.create(library_directory, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(library_directory, .libPaths()))
source("R/bootstrap.R")
args <- commandArgs(trailingOnly = TRUE)
if ("--restore" %in% args) {
  renv::restore(lockfile = "renv.lock", library = library_directory, prompt = FALSE)
} else {
  missing <- r_packages()[!vapply(r_packages(), requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) install.packages(missing, lib = library_directory, repos = "https://cloud.r-project.org")
  require_packages(r_packages())
  renv::snapshot(lockfile = "renv.lock", packages = r_packages(), library = .libPaths(), prompt = FALSE)
}
