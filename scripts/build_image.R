#' Build the pinned restricted R image and record its local image identity. Requires Docker
#'   and build-time network access; no model calls.

source("R/bootstrap.R")
args <- commandArgs(trailingOnly = TRUE)
config <- read_pilot_config(args)
doc_config(config)
result <- processx::run("docker", c("build", "-t", config$sandbox$image,
                                   "-f", "docker/Dockerfile", "."),
                         echo = TRUE, timeout = 600, error_on_status = FALSE)
if (result$status != 0) stop("Image build failed")
write_json(list(image = config$sandbox$image, image_id = docker_info(config$sandbox$image),
                built_at = timestamp()), "docker/document-image-manifest.json")
