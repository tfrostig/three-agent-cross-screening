#' Offline verification of every imported source design before live model calls.
#' CLI: --reuse-run DIR and --output-dir DIR; requires Docker but no API credentials.
source("R/bootstrap.R")
args <- commandArgs(trailingOnly = TRUE)
config <- load_config("config/pilot.yml")
config$sandbox$image <- docker_info(config$sandbox$image)
config$reference_digest <- reference_pack_digest(config)
reuse <- cli_value(args, "--reuse-run", "results/live-revised-20261101")
config$reuse <- prepare_reuse(config, reuse, FALSE)
output <- ensure_dir(cli_value(args, "--output-dir", tempfile("verified-imports-")))
scenarios <- read_csv(file.path(reuse, "scenarios.csv"))
for (i in seq_len(nrow(scenarios))) {
  scenario <- scenarios[i, ]
  setting <- readRDS(reuse_file(config, file.path("private", paste0(scenario$data_id, ".rds"))))
  for (source in 1:3) {
    directory <- file.path(output, scenario$id, paste0("agent-", source))
    result <- import_design(config, scenario, setting$observations[[source]], directory, source)
    stopifnot(result$status == "ok")
    message("Verified imported source: ", scenario$id, " / ", source)
  }
}
message("Verified ", 3L * nrow(scenarios), " historical designs; no model calls.")
