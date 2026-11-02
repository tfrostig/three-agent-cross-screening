source("R/bootstrap.R")
args <- commandArgs(trailingOnly = TRUE)
config <- load_config(cli_value(args, "--config", "config/pilot.yml"))
offline <- "--offline" %in% args
require_packages(c("jsonlite", "yaml", "digest", "data.table", "processx", "ggplot2", "rmarkdown"))
if (!rmarkdown::pandoc_available()) stop("Pandoc is required")
references <- reference_pack_record(config)
cat("Reference catalog:", references$digest, "\n")
if (!offline) validate_live_config(config)
image <- docker_info(config$sandbox$image)
python <- processx::run("poetry", c("run", "python", "-c",
  "import pydantic_ai, pydantic, openai; print('PydanticAI dependencies available')"))
cat(python$stdout)
cat("Image:", image, "\nModel:", config$openai$model,
    "\nScenarios:", nrow(scenario_grid(config)), "\nAgent sessions: 24\nValidation draws: 0\n")
