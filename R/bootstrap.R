#' Load the project modules into the calling environment; run from the project root or set
#'   CROSS_SCREENING_ROOT. No model calls occur during sourcing.

project_root <- normalizePath(Sys.getenv("CROSS_SCREENING_ROOT", "."), mustWork = TRUE)
.libPaths(c(file.path(project_root, "renv", "library", "local"), .libPaths()))
for (module in c("io", "config", "references", "simulation", "contracts", "metrics", "sandbox",
                 "designs", "pipeline", "report")) {
  source(file.path(project_root, "R", paste0(module, ".R")))
}
