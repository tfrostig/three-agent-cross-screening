reference_pack_path <- function(config) {
  path <- config$reference_pack %||% "references/agent-pack"
  if (!grepl("^/", path)) path <- file.path(project_root, path)
  normalizePath(path, mustWork = TRUE)
}

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

reference_pack_record <- function(config) {
  list(path = reference_pack_path(config), digest = reference_pack_digest(config))
}
