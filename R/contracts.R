#' Data-only matrix, hypothesis, and result contracts shared by the trusted host and
#'   restricted R image. No method is statistically certified here.

#' Validate the simulator's equal-shape finite matrix contract
#'
#' @param exposed Numeric n by m exposed matrix with unique measurement column names.
#' @param unexposed Numeric n by m independent control matrix with the same dimensions and
#'   names.
#' @return TRUE invisibly; stops on invalid matrices, names, dimensions, or values.
validate_matrices <- function(exposed, unexposed) {
  stopifnot(is.matrix(exposed), is.matrix(unexposed), is.numeric(exposed),
            is.numeric(unexposed), nrow(exposed) > 0, ncol(exposed) > 0,
            identical(dim(exposed), dim(unexposed)),
            identical(colnames(exposed), colnames(unexposed)),
            !is.null(colnames(exposed)), !anyDuplicated(colnames(exposed)),
            all(is.finite(exposed)), all(is.finite(unexposed)))
  invisible(TRUE)
}

#' Validate a frozen directional hypothesis family
#'
#' @param hypotheses Frozen table with hypothesis_id, measurement_id, and integer direction
#'   (-1 or +1).
#' @param measurements Character vector of valid measurement column names.
#' @return TRUE invisibly; requires exact columns and unique measurement-direction pairs;
#'   empty families are valid.
validate_hypotheses <- function(hypotheses, measurements) {
  required <- c("hypothesis_id", "measurement_id", "direction")
  if (!identical(names(hypotheses), required)) stop("Invalid hypothesis columns")
  if (!nrow(hypotheses)) return(invisible(TRUE))
  stopifnot(is.character(hypotheses$hypothesis_id),
            all(!is.na(hypotheses$hypothesis_id) & nzchar(hypotheses$hypothesis_id)),
            !anyDuplicated(hypotheses$hypothesis_id),
            all(hypotheses$measurement_id %in% measurements),
            all(hypotheses$direction %in% c(-1L, 1L)),
            !anyDuplicated(hypotheses[c("measurement_id", "direction")]))
  invisible(TRUE)
}

#' Validate agent output against the frozen family
#'
#' @param result Per-hypothesis table with hypothesis_id, p_value, reject, and
#'   adjusted_p_value.
#' @param hypotheses Frozen table with hypothesis_id, measurement_id, and integer direction
#'   (-1 or +1).
#' @return TRUE invisibly; checks exact columns, IDs, logical decisions, and finite raw
#'   p-values in [0,1]. Does not certify statistical validity.
validate_result <- function(result, hypotheses) {
  required <- c("hypothesis_id", "p_value", "reject", "adjusted_p_value")
  if (!is.data.frame(result)) stop("Analysis result must be a data.frame")
  if (!identical(names(result), required)) stop("Invalid result columns")
  if (nrow(result) != nrow(hypotheses)) stop("Wrong result row count")
  if (!nrow(result)) return(invisible(TRUE))
  stopifnot(!anyDuplicated(result$hypothesis_id),
            setequal(result$hypothesis_id, hypotheses$hypothesis_id),
            is.numeric(result$p_value), all(is.finite(result$p_value)),
            all(result$p_value >= 0 & result$p_value <= 1),
            is.logical(result$reject), !anyNA(result$reject),
            is.numeric(result$adjusted_p_value),
            all(is.na(result$adjusted_p_value) |
                  (is.finite(result$adjusted_p_value) & result$adjusted_p_value >= 0 &
                     result$adjusted_p_value <= 1)))
  invisible(TRUE)
}

#' Construct the typed empty analysis result
#'
#' @return Zero-row data frame with hypothesis_id, p_value, reject, adjusted_p_value.
empty_result <- function() {
  data.frame(hypothesis_id = character(), p_value = numeric(),
             reject = logical(), adjusted_p_value = numeric())
}

#' Read the frozen CSV with explicit column types
#'
#' @param path Input or destination filesystem path, as indicated in the description.
#' @return Hypothesis data frame; direction is integer. Validation is a separate operation.
read_hypothesis_table <- function(path) {
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE,
                  colClasses = c(hypothesis_id = "character", measurement_id = "character",
                                 direction = "integer"))
}

#' Read per-hypothesis results with explicit column types
#'
#' @param path Input or destination filesystem path, as indicated in the description.
#' @return Result data frame; reject is logical. Validation is a separate operation.
read_result_table <- function(path) {
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE,
                  colClasses = c(hypothesis_id = "character", p_value = "numeric",
                                 reject = "logical", adjusted_p_value = "numeric"))
}
