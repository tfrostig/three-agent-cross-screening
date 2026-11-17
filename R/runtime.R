#' Shared current-run serialization and source identities.
#' Create source-only sessions, verify frozen artifacts, and bind cached designs to exact
#'   input/source identities.

#' Serialize one observation pair for a session-specific mount
#'
#' @param pair List with exposed and unexposed numeric observation matrices.
#' @param directory Filesystem directory holding the relevant inputs or outputs.
#' @return Writes exposed.rds and unexposed.rds in directory; contains observations, never
#'   truth.
write_pair <- function(pair, directory) {
  ensure_dir(directory)
  saveRDS(pair$exposed, file.path(directory, "exposed.rds"), version = 3)
  saveRDS(pair$unexposed, file.path(directory, "unexposed.rds"), version = 3)
}


#' Fingerprint implementation files used in strict resume checks
#'
#' @return Hash covering R/Python scripts, fixtures, Docker source, prompts, and lockfiles.
#'   Documentation edits inside those source files also change it.
source_fingerprint <- function() {
  directories <- c("agents", "R", "scripts", "tests/fixtures", "docker")
  files <- unlist(lapply(directories, function(x) {
    list.files(file.path(project_root, x), pattern = "\\.(R|py)$", recursive = TRUE, full.names = TRUE)
  }))
  files <- c(files, file.path(project_root, c("poetry.lock", "renv.lock", "docker/Dockerfile")),
             list.files(file.path(project_root, "prompts"), full.names = TRUE))
  object_hash(vapply(sort(files), file_hash, character(1)))
}
