source("R/bootstrap.R")
source("scripts/sharing_helpers.R")

check_staged_public_files <- function() {
  paths <- system2("git", c("diff", "--cached", "--name-only", "--diff-filter=ACMRT"), stdout = TRUE)
  if (!is.null(attr(paths, "status"))) stop("Could not inspect the Git index")
  if (!length(paths)) stop("No staged files to check")
  blocked <- publication_private_path(paths)
  if (any(blocked)) stop("Private/generated files staged: ", paste(paths[blocked], collapse = ", "))
  for (path in paths) {
    stage <- system2("git", c("ls-files", "--stage", "--", shQuote(path)), stdout = TRUE)
    if (!length(stage) || !startsWith(stage, "100644 ")) stop("Unexpected file mode: ", path)
    blob <- tempfile("staged-public-file-")
    status <- system2("git", c("show", shQuote(paste0(":", path))), stdout = blob)
    if (status != 0L) stop("Cannot inspect staged file: ", path)
    tryCatch(publication_scan(blob), error = function(error) stop("Staged content check failed: ", path))
    unlink(blob)
  }
  message("Public content check passed for ", length(paths), " staged files; .env was not read.")
}

check_staged_public_files()
