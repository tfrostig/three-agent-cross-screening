source("R/bootstrap.R")

reference_entry <- function(id, source, citation, pages, excerpts = list()) {
  list(id = id, source_file = source, citation = citation, pages = pages, excerpts = excerpts)
}

excerpt_spec <- function(id, first, last, start, finish, crop = NULL) {
  list(id = id, first = first, last = last, start = start, finish = finish, crop = crop)
}

reference_entries <- function() {
  two_team <- paste0("Exploration  Confirmation  and Replication in the Same Observational Study  ",
    "A Two Team Cross-Screening Approach to Studying the Effect of Unwanted Pre.pdf")
  list(
    reference_entry("two-team", two_team,
      "Roy et al. (2026). Exploration, Confirmation, and Replication in the Same Observational Study. JASA. doi:10.1080/01621459.2026.2668130.", "6–7, 10–13", list(
        excerpt_spec("design", 6L, 6L, "Step 2 - Exploratory Data Analysis (exploration):", "alongside the initially planned ones."),
        excerpt_spec("gatekeeping", 11L, 11L, "To control for the multiple testing of the five hypotheses", "shown as a flow chart in Figure 3."))),
    reference_entry("proposal", "Research_proposal.pdf",
      "NSF-BSF. Cross-Screening to Simultaneously Explore, Confirm, and Replicate Findings. Project Description.", "6–9"),
    reference_entry("cross-screening-2018", "Zhao-CrossScreeningObservationalStudies-2018.pdf",
      "Zhao, Small and Rosenbaum (2018). Cross-Screening in Observational Studies That Test Many Hypotheses. JASA. doi:10.1080/01621459.2017.1407770.", "2–4", list(
        excerpt_spec("excerpt", 2L, 2L, "Cross-screening splits the data inhalf at random", "forhaving done two studies.",
          crop = c(64L, 220L, 422L, 224L)))),
    reference_entry("replicability-2018", "BOGOMOLOV-Assessingreplicabilityfindings-2018.pdf",
      "Bogomolov and Heller (2018). Assessing replicability of findings across two studies of multiple features. Biometrika. doi:10.1093/biomet/asy029.", "2, 4–5, 10", list(
        excerpt_spec("excerpt", 2L, 2L, "Replicability analysis aims", "behavioural genetics data."))),
    reference_entry("adafilter", "Wang-DETECTINGMULTIPLEREPLICATING-2022.pdf",
      "Wang et al. (2022). Detecting multiple replicating signals using adaptive filtering procedures. Annals of Statistics. doi:10.1214/21-AOS2139.", "2, 9–11", list(
        excerpt_spec("excerpt", 2L, 2L, "Replicability is a fundamental quality", "GWAS for metabolomics."))),
    reference_entry("cofilter", "CoFilter.pdf",
      "Dickhaus et al. (2026). A procedure for multiple testing of partial conjunction hypotheses based on a hazard rate inequality. Bernoulli. doi:10.3150/25-BEJ1858.", "1–2", list(
        excerpt_spec("excerpt", 1L, 1L, "The partial conjunction null hypothesis", "Crohn’s disease."))),
    reference_entry("replicability-review", "Stat_Science.pdf",
      "Bogomolov and Heller (2023). Replicability Across Multiple Studies. Statistical Science. doi:10.1214/23-STS892.", "1–2, 12", list(
        excerpt_spec("excerpt", 1L, 1L, "Abstract. Meta-analysis is routinely performed", "future directions.")))
  )
}

extract_reference_excerpt <- function(source, spec) {
  crop <- if (is.null(spec$crop)) character() else as.vector(rbind(c("-x", "-y", "-W", "-H"), spec$crop))
  result <- processx::run("pdftotext", c("-layout", "-f", spec$first, "-l", spec$last, crop, source, "-"))
  lines <- strsplit(result$stdout, "\n", fixed = TRUE)[[1]]
  lines <- lines[!grepl("^\\s*(t|ip|cr|us|an|M|d|e|ce|Ac|pt)\\s*$", lines, perl = TRUE)]
  text <- gsub("[[:space:]]+", " ", paste(lines, collapse = " "))
  text <- gsub("\uf061", "\u03b1", text, fixed = TRUE)
  text <- gsub("\uf03d", "=", text, fixed = TRUE)
  start <- regexpr(spec$start, text, fixed = TRUE)[1]
  if (start < 1L) stop("Excerpt start not found: ", spec$id, " in ", source)
  text <- substring(text, start)
  finish <- regexpr(spec$finish, text, fixed = TRUE)[1]
  if (finish < 1L) stop("Excerpt end not found: ", spec$id, " in ", source)
  substring(text, 1L, finish + nchar(spec$finish) - 1L)
}

build_reference_entry <- function(entry, root) {
  source <- file.path(project_root, "references", entry$source_file)
  card <- paste0("cards/", entry$id, ".md")
  sections <- list(overview = list(file = card, kind = "curated summary", pages = entry$pages))
  for (spec in entry$excerpts) {
    file <- paste0("excerpts/", entry$id, "-", spec$id, ".txt")
    text <- extract_reference_excerpt(source, spec)
    ensure_dir(dirname(file.path(root, file)))
    writeLines(text, file.path(root, file), useBytes = TRUE)
    sections[[spec$id]] <- list(file = file,
      kind = "source excerpt; layout/whitespace normalized, watermark lines removed, Symbol-font glyphs transcribed",
      pages = paste(unique(c(spec$first, spec$last)), collapse = "–"))
  }
  list(title = sub("^# ", "", readLines(file.path(root, card), n = 1L, warn = FALSE)),
    citation = entry$citation, source_file = entry$source_file,
    source_sha256 = file_hash(source), sections = sections)
}

build_reference_pack <- function() {
  root <- ensure_dir(file.path(project_root, "references/agent-pack"))
  entries <- reference_entries()
  references <- lapply(entries, build_reference_entry, root = root)
  names(references) <- vapply(entries, `[[`, character(1), "id")
  files <- c("brief.md", unlist(lapply(references, function(x) {
    vapply(x$sections, `[[`, character(1), "file")
  }), use.names = FALSE))
  paths <- file.path(root, files)
  limits <- ifelse(files == "brief.md", 16384L, 6144L)
  stopifnot(all(file.exists(paths)), all(file.info(paths)$size <= limits))
  hashes <- as.list(stats::setNames(vapply(paths, file_hash, character(1)), files))
  write_json(list(version = 1L, brief_file = "brief.md", files = hashes, references = references),
    file.path(root, "catalog.json"))
  message("Reference pack verified: ", reference_pack_digest(list(reference_pack = root)))
}

if (sys.nframe() == 0L) build_reference_pack()
