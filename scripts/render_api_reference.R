#' Regenerate the R Markdown API reference by statically reading source documentation.
#' Run from the project root; parses functions without sourcing CLI/analysis entry points.
source("R/bootstrap.R")

#' Convert one adjacent roxygen-style block into a reference entry.
#' @param expression Parsed named function assignment.
#' @param location Source reference identifying its definition line.
#' @param text Source file lines.
#' @param path Project-relative source path.
#' @return Markdown lines documenting the name, parameters, return/effects, and source link.
reference_entry_lines <- function(expression, location, text, path) {
  last <- as.integer(location[1]) - 1L
  first <- last
  while (first > 1L && startsWith(text[first - 1L], "#'")) first <- first - 1L
  block <- sub("^#' ?", "", text[first:last])
  if (!startsWith(text[last], "#'")) stop("Missing function documentation: ", path)
  joined <- character()
  for (line in block) {
    if (grepl("^  ", line) && length(joined)) joined[length(joined)] <- paste(joined[length(joined)], trimws(line))
    else joined <- c(joined, line)
  }
  params <- joined[startsWith(joined, "@param ")]
  returns <- sub("^@return ", "", joined[startsWith(joined, "@return ")])
  c("", paste0("### `", as.character(expression[[2]]), "`"), "", joined[1], "",
    paste0("[Source](../", path, ")"), "",
    sub("^@param ([^ ]+) (.*)$", "- `\\1`: \\2", params), "",
    paste0("**Returns / effects:** ", returns))
}

#' Enumerate named function assignments without evaluating their bodies.
#' @param path Project-relative R source file.
#' @return Markdown file section containing documented top-level functions.
reference_file_lines <- function(path) {
  text <- readLines(path, warn = FALSE)
  parsed <- parse(path, keep.source = TRUE)
  locations <- attr(parsed, "srcref")
  result <- c("", paste0("## `", path, "`"))
  for (i in seq_along(parsed)) {
    x <- parsed[[i]]
    if (!is.call(x) || !identical(x[[1]], as.name("<-")) || !is.call(x[[3]]) ||
        !identical(x[[3]][[1]], as.name("function"))) next
    result <- c(result, reference_entry_lines(x, locations[[i]], text, path))
  }
  result
}

paths <- unlist(lapply(c("R", "scripts", "analyses", "docker", "fixtures"), function(directory)
  list.files(directory, pattern = "[.]R$", full.names = TRUE)))
header <- c("# R function reference", "", "Source documentation is authoritative. This is a sourced-script project; roxygen2 is not required. See the [developer walkthrough](developer-guide.md) and [pooled-selection guide](pooled-selection.md).")
lines <- c(header, unlist(lapply(paths, reference_file_lines), use.names = FALSE))
writeLines(c(lines[nzchar(lines) | seq_along(lines) < length(lines)]), "docs/r-api.md", useBytes = TRUE)
