#' CLI: --config FILE, --scenario ID, --run-dir DIR, --offline, --dry-run, --resume. Run from
#'   the project root; live mode makes paid model calls.

source("R/bootstrap.R")
args <- commandArgs(trailingOnly = TRUE)
config <- read_pilot_config(args)
options <- list(offline = "--offline" %in% args, dry_run = "--dry-run" %in% args,
                resume = "--resume" %in% args, run_dir = cli_value(args, "--run-dir"),
                scenario = cli_value(args, "--scenario"), reuse_run = cli_value(args, "--reuse-run"))
doc_run(config, options)
