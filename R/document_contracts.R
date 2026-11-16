#' Validate the document protocol's self-contained directional family.
#' @param h Declared family with natural measurement names and integer directions.
#' @param measurements Allowed matrix column names.
doc_family <- function(h, measurements) {
  stopifnot(is.data.frame(h), identical(names(h), c("measurement_id", "direction")),
    is.character(h$measurement_id), is.integer(h$direction), !anyNA(h),
    all(h$measurement_id %in% measurements), all(h$direction %in% c(-1L, 1L)),
    !anyDuplicated(h))
  invisible(TRUE)
}

#' Load definitions without applying the final design.
#' @param path Staged R script.
#' @param measurements Allowed measurement names.
#' @return Environment containing the declared family and callable analysis.
doc_definitions <- function(path, measurements) {
  parse(file = path)
  scope <- new.env(parent = globalenv())
  sys.source(path, envir = scope)
  stopifnot(exists("hypotheses", scope, inherits = FALSE),
    exists("analyze", scope, inherits = FALSE), is.function(scope$analyze),
    identical(names(formals(scope$analyze)), c("exposed", "unexposed", "alpha")))
  doc_family(scope$hypotheses, measurements)
  scope
}

#' Require bounded, nonmissing probabilities.
#' @param x Numeric vector of p-values or adjusted values.
doc_probabilities <- function(x) {
  stopifnot(is.numeric(x), all(is.finite(x)), all(x >= 0 & x <= 1))
}

#' Validate both result tables without replacing the agent's correction.
#' @param result Returned list.
#' @param h Frozen family.
#' @param measurements All measurement names.
#' @param alpha Supplied family level.
doc_result <- function(result, h, measurements, alpha) {
  stopifnot(is.list(result), identical(names(result), c("directional_results", "outcome_results")))
  d <- result$directional_results
  o <- result$outcome_results
  stopifnot(is.data.frame(d), identical(names(d),
    c("measurement_id", "direction", "p_value", "adjusted_p_value", "reject")),
    is.data.frame(o), identical(names(o), c("measurement_id", "adjusted_p_value", "reject")))
  doc_family(d[c("measurement_id", "direction")], measurements)
  key <- function(x) paste(x$measurement_id, x$direction)
  stopifnot(setequal(key(d), key(h)), nrow(d) == nrow(h),
    is.character(o$measurement_id), !anyDuplicated(o$measurement_id),
    setequal(o$measurement_id, measurements), nrow(o) == length(measurements))
  doc_probabilities(d$p_value)
  doc_probabilities(d$adjusted_p_value)
  doc_probabilities(o$adjusted_p_value)
  for (table in list(d, o)) stopifnot(is.logical(table$reject), !anyNA(table$reject),
    identical(table$reject, table$adjusted_p_value <= alpha))
  stopifnot(identical(o$reject, o$measurement_id %in% d$measurement_id[d$reject]),
    all(o$adjusted_p_value[!o$measurement_id %in% h$measurement_id] == 1))
  invisible(TRUE)
}

#' Run a document inspection or evaluation inside the restricted image.
#' @param mode document-inspect or document-evaluate.
#' @param alpha Supplied family level.
doc_runtime <- function(mode, alpha) {
  measurements <- jsonlite::read_json("/design/measurements.json", simplifyVector = TRUE)
  scope <- doc_definitions("/design/analysis.R", measurements)
  if (mode == "document-inspect") {
    jsonlite::write_json(scope$hypotheses, "/output/document.json", dataframe = "rows")
    return(invisible(NULL))
  }
  pair <- load_pair()
  stopifnot(identical(colnames(pair$exposed), measurements))
  original <- scope$hypotheses
  result <- scope$analyze(pair$exposed, pair$unexposed, alpha)
  stopifnot(identical(original, scope$hypotheses))
  doc_result(result, original, measurements, alpha)
  jsonlite::write_json(list(hypotheses = original, result = result), "/output/document.json",
    dataframe = "rows", digits = 17, auto_unbox = TRUE)
}
