#' Image-build-only pinned package installer. Network is required during build and disabled
#'   during agent execution.

versions <- c(zoo = "1.9-1", TH.data = "1.1-5", sandwich = "3.1-3",
              matrixStats = "1.5.0", modeltools = "0.2-25", mvtnorm = "1.4-2",
              libcoin = "1.0-13", multcomp = "1.4-32", jsonlite = "2.0.0",
              data.table = "1.18.6.1", coin = "1.4-6", boot = "1.3-32")

#' Install a pinned R package while building the image
#'
#' @param package R package name.
#' @param version Exact package version to install and verify.
#' @return Downloads from CRAN or its archive and verifies the installed version; build-time
#'   network only.
install_exact <- function(package, version) {
  if (requireNamespace(package, quietly = TRUE) &&
      utils::packageVersion(package) == package_version(version)) return(invisible(NULL))
  name <- paste0(package, "_", version, ".tar.gz")
  urls <- paste0("https://cloud.r-project.org/src/contrib/",
                 c(name, paste0("Archive/", package, "/", name)))
  destination <- tempfile(fileext = ".tar.gz")
  on.exit(unlink(destination))
  downloaded <- FALSE
  for (url in urls) {
    downloaded <- tryCatch({
      utils::download.file(url, destination, quiet = TRUE)
      TRUE
    }, error = function(error) FALSE)
    if (downloaded) break
  }
  if (!downloaded) stop("Cannot download pinned package ", name)
  utils::install.packages(destination, repos = NULL, type = "source")
  stopifnot(utils::packageVersion(package) == package_version(version))
}

for (package in names(versions)) install_exact(package, versions[[package]])
installed <- installed.packages()[, c("Package", "Version", "Priority"), drop = FALSE]
jsonlite::write_json(as.data.frame(installed), "/opt/runner/packages.json", pretty = TRUE)
