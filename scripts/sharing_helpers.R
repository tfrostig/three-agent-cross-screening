#' Allowlisted copy, path-sanitization and heuristic secret checks for public source and
#'   review bundles. These checks never read .env.

#' Define heuristic credential patterns for publication review
#'
#' @return PCRE pattern; this is a format check, not a guarantee that arbitrary secrets are
#'   absent.
publication_secret_pattern <- function() {
  paste(c("(?<![A-Za-z0-9_-])sk-(?:proj-)?[A-Za-z0-9_-]{20,}",
    "(?<![A-Za-z0-9_])gh[pousr]_[A-Za-z0-9]{20,}",
    "(?<![A-Za-z0-9_])github_pat_[A-Za-z0-9_]{20,}", "-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----",
    "(?i:authorization)[\"']?\\s*[:=]\\s*[\"']?(?i:bearer)\\s+[A-Za-z0-9._-]{16,}",
    "https?://[^/[:space:]:]+:[^/@[:space:]]+@"), collapse = "|")
}

#' Identify generated or private paths that must not be staged
#'
#' @param paths Character vector of filesystem paths or names to inspect.
#' @return Logical vector aligned to paths; a plain .env.example is permitted outside blocked
#'   directories.
publication_private_path <- function(paths) {
  blocked <- "(^|/)(results|exports|deliverables|private|secrets|\\.venv|\\.git|__pycache__|\\.pytest_cache)(/|$)|(^|/)renv/(library|cache|staging|python)/"
  files <- "(^|/)(\\.env($|\\.)|\\.envrc$|credentials\\.json$|service-account[^/]*\\.json$|id_(rsa|ed25519)[^/]*$)"
  binary <- "\\.(pem|key|p12|pfx|rds|rda|zip|pdf|docx|log)$|\\.tar\\.gz$"
  grepl(blocked, paths, perl = TRUE) | grepl(binary, paths, ignore.case = TRUE) |
    (grepl(files, paths, perl = TRUE) & !grepl("(^|/)\\.env\\.example$", paths))
}

#' Read bounded text for publication review
#'
#' @param path Input or destination filesystem path, as indicated in the description.
#' @return File content as a character scalar; refuses files larger than 20 MiB.
publication_read_text <- function(path) {
  size <- file.info(path)$size
  if (is.na(size) || size > 20 * 1024^2) stop("Unexpected file size: ", path)
  readChar(path, nchars = size, useBytes = TRUE)
}

#' Reject common credential formats without reading private key files
#'
#' @param paths Character vector of filesystem paths or names to inspect.
#' @return TRUE invisibly; on a match reports filenames only, never matching secret text.
publication_scan <- function(paths) {
  suspect <- vapply(paths, function(path) {
    text <- publication_read_text(path)
    grepl(publication_secret_pattern(), text, perl = TRUE)
  }, logical(1))
  if (any(suspect)) stop("Possible credentials in: ", paste(paths[suspect], collapse = ", "))
  invisible(TRUE)
}

#' Write exact UTF-8 export content
#'
#' @param text Character text to escape, sanitize, or write.
#' @param path Input or destination filesystem path, as indicated in the description.
#' @return Creates parent directories and writes bytes without an added newline.
publication_write_text <- function(text, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeBin(charToRaw(enc2utf8(text)), path)
}

#' Replace local project, home, and temporary paths in export text
#'
#' @param text Character text to escape, sanitize, or write.
#' @return Sanitized character text; the original source file is not changed.
publication_sanitize_paths <- function(text) {
  text <- gsub(project_root, "[PROJECT_ROOT]", text, fixed = TRUE)
  text <- gsub(utils::URLencode(project_root), "[PROJECT_ROOT]", text, fixed = TRUE)
  text <- gsub(path.expand("~"), "[HOME]", text, fixed = TRUE)
  gsub("/private/(?:var/folders|tmp)/[^\"'<>[:space:]]+", "[TEMP_PATH]", text, perl = TRUE)
}

#' Copy an export file and optionally sanitize local paths
#'
#' @param source Existing regular source file; symbolic links are rejected.
#' @param target Export destination file path, never the original source path.
#' @param immutable Logical; forbid sanitization or alteration of copied artifact bytes.
#' @return Invisible disposition: unchanged or path-sanitized. Immutable artifacts must be
#'   byte-identical or copying stops.
publication_copy <- function(source, target, immutable = FALSE) {
  if (nzchar(Sys.readlink(source))) stop("Refusing linked file: ", source)
  dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
  ext <- tolower(tools::file_ext(source))
  text_file <- ext %in% c("r", "rmd", "md", "json", "csv", "txt", "html", "yml")
  text <- if (text_file) publication_read_text(source) else NULL
  clean <- if (text_file) publication_sanitize_paths(text) else NULL
  changed <- text_file && !identical(text, clean)
  if (immutable && changed) stop("Frozen/source artifact contains a local path: ", source)
  if (changed) publication_write_text(clean, target)
  else if (!file.copy(source, target, copy.mode = FALSE)) stop("Cannot copy: ", source)
  if (!changed && !identical(file_hash(source), file_hash(target))) stop("Copy mismatch: ", source)
  invisible(if (changed) "path-sanitized" else "unchanged")
}
