#' Host dependency checks, fixed scenario-grid validation, and live credential-availability
#'   checks.

#' List the host-side R dependencies
#'
#' @return Character vector of package names.
r_packages <- function() {
  c("renv", "jsonlite", "yaml", "data.table", "digest", "processx", "ggplot2",
    "testthat", "knitr", "rmarkdown", "matrixStats", "coin", "boot")
}

#' Read and validate a pilot YAML configuration
#'
#' @param path Input or destination filesystem path, as indicated in the description.
#' @return Validated configuration list; invalid settings raise an error.
load_config <- function(path) {
  config <- yaml::read_yaml(path)
  validate_config(config)
  config
}

#' Enforce the fixed pilot grid and one-iteration contract
#'
#' @param config Validated configuration list from load_config(), unless a SessionConfig is
#'   explicitly noted.
#' @return The configuration invisibly; stops on unsupported settings.
validate_config <- function(config) {
  stopifnot(config$iterations_per_scenario == 1,
            config$additional_validation_draws == 0,
            config$alpha > 0, config$alpha < 1,
            config$tau_squared > 0, config$max_n >= 1,
            identical(sort(as.integer(config$measurements)), c(20L, 100L, 1000L)),
            any(vapply(list(c(0.2, 0.6), c(0.2, 0.6, 0.9)), function(x)
              identical(sort(as.numeric(config$power_targets)), x), logical(1))),
            (config$aggregation %||% "cycle") %in% c("cycle", "pooled_leave_one_out"))
  probs <- unlist(config$state_probabilities)
  stopifnot(setequal(names(probs), c("000", "001", "010", "011", "100", "101", "110", "111")),
            all(is.finite(probs)), all(probs >= 0), abs(sum(probs) - 1) < 1e-12)
  methods <- config$baseline_fdr_methods %||% "BY"
  stopifnot(length(methods) >= 1L, all(methods %in% c("BH", "BY")), !anyDuplicated(methods))
  invisible(config)
}

#' Substitute a default only for NULL
#'
#' @param value Any R value; only NULL triggers the fallback.
#' @param default Fallback returned when the requested value is absent.
#' @return The supplied value or the default; NA and empty vectors are preserved.
`%||%` <- function(value, default) if (is.null(value)) default else value

#' Expand the permitted scenarios and shared dataset IDs
#'
#' @param config Validated configuration list from load_config(), unless a SessionConfig is
#'   explicitly noted.
#' @return Data frame with m, c, criterion, id, and data_id. Matching m=100 criteria share
#'   data_id.
scenario_grid <- function(config) {
  grid <- expand.grid(m = as.integer(config$measurements),
                      c = as.numeric(config$power_targets),
                      criterion = c("FWER", "FDR"), stringsAsFactors = FALSE)
  grid <- grid[(grid$criterion == "FWER" & grid$m %in% c(20, 100)) |
                 (grid$criterion == "FDR" & grid$m %in% c(100, 1000)), ]
  grid <- grid[order(grid$criterion, grid$m, grid$c), ]
  grid$id <- sprintf("%s_m%d_c%02d", tolower(grid$criterion), grid$m, as.integer(grid$c * 100))
  grid$data_id <- sprintf("m%d_c%02d", grid$m, as.integer(grid$c * 100))
  rownames(grid) <- NULL
  grid
}

#' Check dependencies without installing packages
#'
#' @param packages Character vector of required R package names.
#' @return NULL invisibly; stops with missing package names.
require_packages <- function(packages) {
  missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) stop("Missing R packages: ", paste(missing, collapse = ", "),
                            ". Run Rscript --vanilla scripts/setup.R")
}

#' Check explicit model selection and private credential availability
#'
#' @param config Validated configuration list from load_config(), unless a SessionConfig is
#'   explicitly noted.
#' @return No scientific result; stops before agents start if configuration is unavailable.
validate_live_config <- function(config) {
  if (is.null(config$openai$model) || !nzchar(trimws(config$openai$model))) {
    stop("An explicit openai.model is required")
  }
  check <- processx::run("poetry", c("run", "python", "-m", "agents.credentials", "--check"),
                          wd = project_root, error_on_status = FALSE)
  if (check$status != 0) {
    stop("Credential unavailable; export OPENAI_API_KEY or configure the authorized local .env")
  }
}
