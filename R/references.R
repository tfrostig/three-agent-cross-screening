#' Resolve and hash approved methodological context without exposing original PDFs or
#'   arbitrary host files.

#' Resolve the curated reference library configured for the run
#'
#' @param config Validated configuration list from load_config(), unless a SessionConfig is
#'   explicitly noted.
#' @return Absolute existing pack path, defaulting to references/agent-pack.
reference_pack_path <- function(config) {
  path <- config$reference_pack %||% "references/agent-pack"
  if (!grepl("^/", path)) path <- file.path(project_root, path)
  normalizePath(path, mustWork = TRUE)
}

#' Verify approved payload hashes and lock the catalog identity
#'
#' @param config Validated configuration list from load_config(), unless a SessionConfig is
#'   explicitly noted.
#' @return SHA-256 catalog hash; stops on traversal, stale payloads, or mid-run digest
#'   changes.
reference_pack_digest <- function(config) {
  root <- reference_pack_path(config)
  catalog_path <- safe_file(file.path(root, "catalog.json"), root)
  catalog <- read_json(catalog_path)
  stopifnot(catalog$version == 1L, catalog$brief_file %in% names(catalog$files))
  for (name in names(catalog$files)) {
    if (grepl("(^/|(^|/)\\.\\.(/|$))", name)) stop("Invalid reference filename")
    path <- safe_file(file.path(root, name), root)
    if (!identical(file_hash(path), catalog$files[[name]])) stop("Reference catalog is stale: ", name)
  }
  digest <- file_hash(catalog_path)
  if (!is.null(config$reference_digest) && !identical(digest, config$reference_digest)) {
    stop("Reference pack changed during this run")
  }
  digest
}

#' Record the reference path and verified catalog identity
#'
#' @param config Validated configuration list from load_config(), unless a SessionConfig is
#'   explicitly noted.
#' @return List with path and digest for cache/run provenance.
reference_pack_record <- function(config) {
  list(path = reference_pack_path(config), digest = reference_pack_digest(config))
}
