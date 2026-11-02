source("R/bootstrap.R")
config <- load_config("config/pilot.yml")
config$sandbox$image <- docker_info(config$sandbox$image)
root <- ensure_dir(tempfile("isolation-test-"))
input <- ensure_dir(file.path(root, "input"))
workspace <- ensure_dir(file.path(root, "work"))
private <- ensure_dir(file.path(root, "private"))
Sys.chmod(workspace, "0777")
writeLines("synthetic-private-canary", file.path(private, "truth.txt"))
set.seed(8)
pair <- list(exposed = matrix(rnorm(12), 6, 2, dimnames = list(NULL, c("a", "b"))),
             unexposed = matrix(rnorm(12), 6, 2, dimnames = list(NULL, c("a", "b"))))
write_pair(pair, input)
request <- list(mode = "explore", input_dir = input, workspace = workspace,
                sandbox = config$sandbox, alpha = .05 / 3, execution_seed = 731)
request$code <- paste0(
  "stopifnot(!file.exists(", encodeString(file.path(private, "truth.txt"), quote = '"'), "))\n",
  "stopifnot(!file.exists('/var/run/docker.sock'))\n",
  "stopifnot(Sys.getenv('OPENAI_API_KEY') == '')\n",
  "stopifnot(file.access('/opt/runner/runtime.R', 2) == -1)\n",
  "read_only <- tryCatch({writeLines('bad', '/input/canary'); FALSE}, error=function(e) TRUE)\n",
  "stopifnot(read_only)\n",
  "options(timeout=2)\n",
  "offline <- tryCatch({x <- url('https://example.com', open='r', method='libcurl'); close(x); FALSE}, error=function(e) TRUE)\n",
  "stopifnot(offline)\ncat('ISOLATION_CHECKS_PASSED')")
checked <- execute_sandbox(request)
stopifnot(checked$status == "ok", grepl("ISOLATION_CHECKS_PASSED", checked$stdout))
request$sandbox$timeout_seconds <- 1
request$code <- "Sys.sleep(10)"
timeout <- execute_sandbox(request)
stopifnot(timeout$status == "failed", isTRUE(timeout$timed_out))
write_json(list(isolation = checked$status, timeout_enforced = timeout$timed_out,
                image_id = config$sandbox$image, checked_at = timestamp()), "docker/isolation-checks.json")
unlink(root, recursive = TRUE)
cat("Isolation and timeout checks passed\n")
