ensure_dir <- function(path) {
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  normalizePath(path, mustWork = TRUE)
}

write_json <- function(value, path) {
  ensure_dir(dirname(path))
  jsonlite::write_json(value, path, pretty = TRUE, auto_unbox = TRUE,
                       null = "null", na = "null", digits = 17)
}

read_json <- function(path) jsonlite::read_json(path, simplifyVector = TRUE)

file_hash <- function(path) digest::digest(file = path, algo = "sha256")

object_hash <- function(value) digest::digest(value, algo = "sha256")

write_csv <- function(value, path) {
  ensure_dir(dirname(path))
  old <- options(digits = 17)
  on.exit(options(old))
  utils::write.csv(value, path, row.names = FALSE, na = "")
}

read_csv <- function(path) {
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}

cli_value <- function(args, name, default = NULL) {
  index <- match(name, args)
  if (is.na(index)) return(default)
  if (index == length(args) || startsWith(args[index + 1L], "--")) {
    stop("Missing value for ", name)
  }
  args[index + 1L]
}

timestamp <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

safe_file <- function(path, root) {
  if (!file.exists(path) || nzchar(Sys.readlink(path))) stop("Missing or linked artifact")
  resolved <- normalizePath(path, mustWork = TRUE)
  prefix <- paste0(normalizePath(root, mustWork = TRUE), .Platform$file.sep)
  if (!startsWith(resolved, prefix) || dir.exists(resolved)) stop("Unsafe artifact path")
  resolved
}

atomic_rds <- function(value, path) {
  tmp <- paste0(path, ".partial")
  saveRDS(value, tmp, version = 3)
  if (!file.rename(tmp, path)) stop("Cannot publish artifact: ", path)
}
