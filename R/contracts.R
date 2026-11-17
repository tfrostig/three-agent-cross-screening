#' Matrix validation shared by the trusted controller and restricted R image.
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
