source("R/bootstrap.R")
args <- commandArgs(trailingOnly = TRUE)
config <- load_config(cli_value(args, "--config", "config/pilot.yml"))
options <- list(offline = "--offline" %in% args, dry_run = "--dry-run" %in% args,
                resume = "--resume" %in% args, run_dir = cli_value(args, "--run-dir"),
                scenario = cli_value(args, "--scenario"))
run_pilot(config, options)
