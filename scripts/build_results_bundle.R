#' CLI: --output-dir DIR. Package the original/revised completed runs with an allowlist and
#'   integrity checks; no model calls or agent-code execution.

source("R/bootstrap.R")
source("scripts/sharing_helpers.R")

#' Select reviewable results through an explicit path allowlist
#'
#' @param directory Filesystem directory holding the relevant inputs or outputs.
#' @return Sorted relative filenames; excludes input, private, work, controller logs, and
#'   caches.
bundle_run_files <- function(directory) {
  top <- c("report.html", "scores.csv", "global-scores.csv", "scenarios.csv", "planning.csv",
    "run.json", "completion.json", "usage.csv", "power.png", "agent-designs.csv",
    "comparison.csv", "exploration-index.csv", "exploration-README.md")
  paths <- list.files(directory, recursive = TRUE, all.files = TRUE)
  frozen <- "^scenarios/[^/]+/agent-[123]/frozen/(analysis\\.R|hypotheses\\.csv|report\\.md|frozen\\.json)$"
  audit <- "audit/(prompts|messages|session|references|execution-[0-9]+(-result)?)\\.json$|audit/exploration/execution-[0-9]+\\.R$"
  agents <- grepl("^scenarios/[^/]+/agent-[123]/", paths) & grepl(audit, paths)
  evaluation <- grepl("^scenarios/[^/]+/evaluation/[^/]+\\.(csv|json)$", paths)
  design_status <- grepl("^scenarios/[^/]+/design-status\\.json$", paths)
  retries <- startsWith(paths, "infrastructure-retries/") &
    (grepl(audit, paths) | paths %in% c("infrastructure-retries/README.md", "infrastructure-retries/recovery.json"))
  sort(paths[paths %in% top | grepl(frozen, paths) | agents | evaluation | design_status | retries])
}

#' Copy one completed live run into an export tree
#'
#' @param name Saved live-run folder name, relative to results/.
#' @param output Destination directory or file, as indicated in the description.
#' @return Manifest records for copied files; local paths may be sanitized except in immutable
#'   artifacts.
bundle_copy_run <- function(name, output) {
  directory <- file.path(project_root, "results", name)
  stopifnot(read_json(file.path(directory, "run.json"))$mode == "live",
            file.exists(file.path(directory, "completion.json")))
  files <- bundle_run_files(directory)
  records <- lapply(files, function(path) {
    immutable <- grepl("/frozen/|/exploration/[^/]+\\.R$", path)
    target <- file.path(output, "runs", name, path)
    action <- publication_copy(file.path(directory, path), target, immutable)
    data.frame(path = file.path("runs", name, path), original = file.path("results", name, path),
      disposition = action, stringsAsFactors = FALSE)
  })
  do.call(rbind, records)
}

#' Verify frozen hashes, exploration exports, and successful scores
#'
#' @param directory Filesystem directory holding the relevant inputs or outputs.
#' @return No result value; stops unless the saved run has eight scenarios and 24 successful
#'   designs.
bundle_check_run <- function(directory) {
  scenarios <- read_csv(file.path(directory, "scenarios.csv"))
  stopifnot(nrow(scenarios) == 8L)
  for (scenario in scenarios$id) for (agent in 1:3) {
    frozen <- file.path(directory, "scenarios", scenario, paste0("agent-", agent), "frozen")
    verify_frozen(frozen)
    session <- read_json(file.path(dirname(frozen), "audit/session.json"))
    stopifnot(session$status == "ok", session$model == "gpt-6.1-sol")
  }
  index <- read_csv(file.path(directory, "exploration-index.csv"))
  for (i in seq_len(nrow(index))) {
    code <- file.path(directory, index$code_file[i])
    request <- read_json(file.path(directory, index$request_file[i]))
    stopifnot(file_hash(code) == index$sha256[i],
      identical(publication_read_text(code), request$code),
      file.exists(file.path(directory, index$result_file[i])))
  }
  scores <- read_csv(file.path(directory, "scores.csv"))
  stopifnot(all(scores$status == "ok"), sum(scores$method == "agent") == 24L)
}

#' Copy the methodology and approved reference context
#'
#' @param output Destination directory or file, as indicated in the description.
#' @return Manifest records for methods documents, current prompts, and curated library files.
bundle_extra_files <- function(output) {
  paths <- c("docs/isolation.md", "docs/prompt-revision.md", "docs/sharing.md",
    "prompts/system.txt", "prompts/developer.txt")
  references <- list.files("references/agent-pack", recursive = TRUE, full.names = TRUE)
  paths <- c(paths, references)
  records <- lapply(paths, function(path) {
    target <- file.path("methods", path)
    action <- publication_copy(path, file.path(output, target))
    data.frame(path = target, original = path, disposition = action)
  })
  do.call(rbind, records)
}

#' Write editorial descriptions linking two actual revised designs
#'
#' @param output Destination directory or file, as indicated in the description.
#' @return Creates examples/README.md; agent explanations themselves remain in frozen reports.
bundle_examples <- function(output) {
  lines <- c("# Two actual revised-agent analyses", "",
    "These notes are editorial summaries. Linked reports contain the agents' own explanations.", "",
    "## 1. Keep all measurements and weight source evidence", "",
    "FDR / m=100 / c=0.2, source Agent 1 -> target Group 2. The agent kept all 100 measurements, froze one source-selected direction each, and assigned raw weights 4, 2, or 0.5 to tiers of 9, 17, and 74 measurements. It normalized weights to sum to 100 and applied BH to independent target Welch p-values divided by their weights.", "",
    "Its rationale was to prioritize source signals while preserving opportunities for effects that differ across subgroups. It explored variance ratios, residual distributions, correlations, and single-observation deletion stability. It explicitly called the cutoffs pragmatic and made no optimality claim. Our assessment: a conventional coherent design, with heuristic allocations and an acknowledged risk of freezing the wrong direction.", "",
    "[Agent explanation](../runs/live-revised-20261101/scenarios/fdr_m100_c20/agent-1/frozen/report.md) | [Exact R code](../runs/live-revised-20261101/scenarios/fdr_m100_c20/agent-1/frozen/analysis.R) | [Hypotheses](../runs/live-revised-20261101/scenarios/fdr_m100_c20/agent-1/frozen/hypotheses.csv)", "",
    "## 2. Test only two isolated source standouts", "",
    "FWER / m=20 / c=0.2, source Agent 2 -> target Group 3. This agent selected positive alternatives for v0003 and v0019 only. Their source standardized statistics were approximately 7.18 and 3.30, while all other absolute statistics were below 1.61. Both positive differences survived deleting any single observation. The target algorithm used pooled two-sample Student t-tests and Holm over those two hypotheses.", "",
    "Its rationale was to concentrate testing on two clear signals. The agent acknowledged losing every opportunity among the other 18 measurements and that similar source variances cannot establish target equal variances or normality. Our assessment: understandable selection, but no demonstrated target-power advantage or optimal shortlist. This was the only revised design that excluded measurements.", "",
    "[Agent explanation](../runs/live-revised-20261101/scenarios/fwer_m20_c20/agent-2/frozen/report.md) | [Exact R code](../runs/live-revised-20261101/scenarios/fwer_m20_c20/agent-2/frozen/analysis.R) | [Hypotheses](../runs/live-revised-20261101/scenarios/fwer_m20_c20/agent-2/frozen/hypotheses.csv)")
  publication_write_text(paste(lines, collapse = "\n"), file.path(output, "examples/README.md"))
}

#' Render the reading guide and portable saved-results summary
#'
#' @param output Destination directory or file, as indicated in the description.
#' @return Manifest rows for copied templates/tables; writes HTML and Markdown without
#'   executing agent code.
bundle_render <- function(output) {
  sources <- c("docs/results-bundle-README.md", "reports/shared-summary.Rmd",
    "results/live-revised-20261101/comparison.csv")
  targets <- c("README.md", "summary/summary.Rmd", "summary/comparison.csv")
  actions <- vapply(seq_along(sources), function(i) {
    publication_copy(sources[i], file.path(output, targets[i]))
  }, character(1))
  rmarkdown::pandoc_convert(file.path(output, "README.md"), from = "markdown", to = "html5",
    output = file.path(output, "README.html"),
    options = c("--standalone", "--metadata", "title=Results reading guide"), verbose = FALSE)
  rmarkdown::render(file.path(output, "summary/summary.Rmd"), quiet = TRUE,
    envir = new.env(parent = baseenv()))
  data.frame(path = targets, original = sources, disposition = actions)
}

#' Inventory every exported payload with size, hash, and provenance
#'
#' @param output Destination directory or file, as indicated in the description.
#' @param records Data frame mapping exported paths to original paths and copy dispositions.
#' @return Manifest data frame, also written to MANIFEST.csv; excludes the manifest's own
#'   hash.
bundle_manifest <- function(output, records) {
  paths <- sort(list.files(output, recursive = TRUE))
  original <- records$original[match(paths, records$path)]
  action <- records$disposition[match(paths, records$path)]
  original[is.na(original)] <- ""
  action[is.na(action)] <- "generated"
  rows <- data.frame(path = paths, bytes = file.info(file.path(output, paths))$size,
    sha256 = vapply(file.path(output, paths), file_hash, character(1)),
    original = original, disposition = action, stringsAsFactors = FALSE)
  write_csv(rows, file.path(output, "MANIFEST.csv"))
  rows
}

#' Check exported file integrity and absence of prohibited content
#'
#' @param output Destination directory or file, as indicated in the description.
#' @param manifest Export inventory data frame containing paths and SHA-256 hashes.
#' @return Stops on hash failures, common credential patterns, remaining local paths, or
#'   invalid saved artifacts.
bundle_verify_files <- function(output, manifest) {
  paths <- file.path(output, manifest$path)
  text <- !grepl("\\.png$", paths)
  publication_scan(paths[text])
  stopifnot(!any(grepl("(^|/)(private|input|work|cache)(/|$)|\\.(rds|pdf|docx)$", manifest$path)),
    all(vapply(paths, file_hash, character(1)) == manifest$sha256))
  local_paths <- vapply(paths[text], function(path) {
    grepl("/Users/|/home/|file:///", publication_read_text(path))
  }, logical(1))
  if (any(local_paths)) stop("Local paths remain in: ", paste(paths[text][local_paths], collapse = ", "))
  for (run in c("live-first", "live-revised-20261101")) {
    bundle_check_run(file.path(output, "runs", run))
  }
}

#' Build and validate a shareable ZIP for the two completed runs
#'
#' @param output Destination directory or file, as indicated in the description.
#' @return Creates output directory and adjacent .zip, refusing existing destinations.
#'   Originals remain unchanged; requires both local live runs.
build_results_bundle <- function(output) {
  if (file.exists(output) || file.exists(paste0(output, ".zip"))) stop("Export destination already exists")
  output <- ensure_dir(output)
  runs <- c("live-first", "live-revised-20261101")
  records <- do.call(rbind, lapply(runs, bundle_copy_run, output = output))
  records <- rbind(records, bundle_extra_files(output))
  bundle_examples(output)
  records <- rbind(records, bundle_render(output))
  manifest <- bundle_manifest(output, records)
  bundle_verify_files(output, manifest)
  old <- setwd(dirname(output))
  on.exit(setwd(old))
  archive <- paste0(output, ".zip")
  status <- utils::zip(archive, file.path(basename(output), c(manifest$path, "MANIFEST.csv")), flags = "-q -X")
  if (status != 0L || !file.exists(archive)) stop("ZIP creation failed")
  listing <- utils::unzip(archive, list = TRUE)
  stopifnot(nrow(listing) == nrow(manifest) + 1L)
  message("Results ZIP: ", archive, " (", nrow(manifest) + 1L, " files)")
}

if (sys.nframe() == 0L) {
  output <- cli_value(commandArgs(trailingOnly = TRUE), "--output-dir",
    "exports/three-agent-cross-screening-results-2026-11-02")
  build_results_bundle(output)
}
