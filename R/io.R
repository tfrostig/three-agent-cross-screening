#' Controller-side serialization, audit timestamps, safe artifact paths, and byte/object
#'   hashes.

#' Create a directory and resolve its absolute path
#'
#' @param path Input or destination filesystem path, as indicated in the description.
#' @return Normalized existing directory path.
ensure_dir <- function(path) {
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  normalizePath(path, mustWork = TRUE)
}

#' Write controller metadata with stable JSON settings
#'
#' @param value R value to serialize or hash.
#' @param path Destination JSON file; its parent directories are created.
#' @return Writes UTF-8 JSON, creating parent directories; NULL and NA serialize as null.
write_json <- function(value, path) {
  ensure_dir(dirname(path))
  jsonlite::write_json(value, path, pretty = TRUE, auto_unbox = TRUE,
                       null = "null", na = "null", digits = 17)
}

#' Read controller JSON with simplified vectors
#'
#' @param path Existing controller-owned JSON file.
#' @return Parsed R value from jsonlite; malformed input raises a parse error.
read_json <- function(path) jsonlite::read_json(path, simplifyVector = TRUE)

#' Hash a file's bytes for artifact integrity
#'
#' @param path Input or destination filesystem path, as indicated in the description.
#' @return SHA-256 hexadecimal string; no content is interpreted.
file_hash <- function(path) digest::digest(file = path, algo = "sha256")

#' Hash an R object for internal cache identity
#'
#' @param value R value to serialize or hash.
#' @return SHA-256 string based on R serialization, not a portable content-file checksum.
object_hash <- function(value) digest::digest(value, algo = "sha256")

#' Write a results table with full numeric precision
#'
#' @param value Data frame to serialize as a CSV table.
#' @param path Input or destination filesystem path, as indicated in the description.
#' @return Writes CSV without row names, representing NA as empty cells; restores global
#'   digits afterward.
write_csv <- function(value, path) {
  ensure_dir(dirname(path))
  old <- options(digits = 17)
  on.exit(options(old))
  utils::write.csv(value, path, row.names = FALSE, na = "")
}

#' Read a results table without altering column names
#'
#' @param path Input or destination filesystem path, as indicated in the description.
#' @return Data frame with strings kept as character values.
read_csv <- function(path) {
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
}

#' Read the value following a named CLI option
#'
#' @param args Character vector of command-line arguments.
#' @param name Named CLI flag, including its leading --.
#' @param default Fallback returned when the requested value is absent.
#' @return Character option value or default; stops if a present option has no value.
cli_value <- function(args, name, default = NULL) {
  index <- match(name, args)
  if (is.na(index)) return(default)
  if (index == length(args) || startsWith(args[index + 1L], "--")) {
    stop("Missing value for ", name)
  }
  args[index + 1L]
}

#' Format the current instant for audit metadata
#'
#' @return UTC timestamp in ISO-like YYYY-MM-DDTHH:MM:SSZ form.
timestamp <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

#' Require an existing regular artifact within its trusted root
#'
#' @param path Existing artifact path to validate without following a linked final component.
#' @param root Existing trusted root that must contain the resolved regular file.
#' @return Resolved path; rejects a linked final path, directories, or paths outside root.
safe_file <- function(path, root) {
  if (!file.exists(path) || nzchar(Sys.readlink(path))) stop("Missing or linked artifact")
  resolved <- normalizePath(path, mustWork = TRUE)
  prefix <- paste0(normalizePath(root, mustWork = TRUE), .Platform$file.sep)
  if (!startsWith(resolved, prefix) || dir.exists(resolved)) stop("Unsafe artifact path")
  resolved
}

#' Publish an RDS file through a same-directory temporary file
#'
#' @param value R value to serialize or hash.
#' @param path Input or destination filesystem path, as indicated in the description.
#' @return Writes path.partial and renames it to path; stops if publication fails.
atomic_rds <- function(value, path) {
  tmp <- paste0(path, ".partial")
  saveRDS(value, tmp, version = 3)
  if (!file.rename(tmp, path)) stop("Cannot publish artifact: ", path)
}
