#' Check data-free inspection and isolation using synthetic observations only.
source("R/bootstrap.R")
source("R/document_pipeline.R")
config <- yaml::read_yaml("config/pilot.yml")
config$sandbox$image <- docker_info(config$sandbox$image)
work <- ensure_dir(tempfile("document-isolation-"))
input <- ensure_dir(tempfile("document-observations-"))
write_pair(list(exposed=matrix(1,2,1,dimnames=list(NULL,"v0001")),
  unexposed=matrix(0,2,1,dimnames=list(NULL,"v0001"))),input)
writeLines(c('stopifnot(!file.exists("/input/exposed.rds"), Sys.getenv("OPENAI_API_KEY") == "",',
  ' !file.exists("/var/run/docker.sock"), !file.exists("/opt/runner/simulation.R"))',
  'hypotheses <- data.frame(measurement_id="v0001",direction=1L)',
  'analyze <- function(exposed,unexposed,alpha) stop("ANALYZE MUST NOT RUN")'),file.path(work,"analysis.R"))
request <- list(mode="document-inspect",workspace=work,input_dir=input,measurements="v0001",
  alpha=.05/3,execution_seed=1,sandbox=config$sandbox)
result <- doc_sandbox(request)
stopifnot(result$status=="ok")
request$mode <- "document-evaluate"
result <- doc_sandbox(request)
stopifnot(result$status=="failed")
unlink(c(work,input),recursive=TRUE)
cat("Data-free inspection, credential/truth separation and non-application verified.\n")
