r_packages <- function() {
  c("renv", "jsonlite", "yaml", "data.table", "digest", "processx", "ggplot2",
    "testthat", "knitr", "rmarkdown", "matrixStats", "coin", "boot")
}

load_config <- function(path) {
  config <- yaml::read_yaml(path)
  validate_config(config)
  config
}

validate_config <- function(config) {
  stopifnot(config$iterations_per_scenario == 1,
            config$additional_validation_draws == 0,
            config$alpha > 0, config$alpha < 1,
            config$tau_squared > 0, config$max_n >= 1,
            identical(sort(as.integer(config$measurements)), c(20L, 100L, 1000L)),
            identical(sort(as.numeric(config$power_targets)), c(0.2, 0.6)))
  probs <- unlist(config$state_probabilities)
  stopifnot(setequal(names(probs), c("000", "001", "010", "011", "100", "101", "110", "111")),
            all(is.finite(probs)), all(probs >= 0), abs(sum(probs) - 1) < 1e-12)
  methods <- config$baseline_fdr_methods %||% "BY"
  stopifnot(length(methods) >= 1L, all(methods %in% c("BH", "BY")), !anyDuplicated(methods))
  invisible(config)
}

`%||%` <- function(value, default) if (is.null(value)) default else value

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

require_packages <- function(packages) {
  missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) stop("Missing R packages: ", paste(missing, collapse = ", "),
                            ". Run Rscript --vanilla scripts/setup.R")
}

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
