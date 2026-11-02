source("analyses/build_research_note.R")

rmarkdown_note_header <- function() {
  paste(c("---", "title: Can agents conduct a statistical analysis?",
    "subtitle: First simulation run — architecture, findings, and limitations",
    "date: 17 October 2026", "lang: en", "output:", "  html_document:",
    "    self_contained: true", "    toc: true", "    toc_float: true",
    "    number_sections: false", "    theme: readable", "    code_folding: hide",
    "---", "", "```{r report-root, include=FALSE}",
    "knitr::opts_chunk$set(echo = FALSE, warning = FALSE, message = FALSE)",
    "report_root <- normalizePath(\"..\", mustWork = TRUE)",
    "stopifnot(file.exists(file.path(report_root, \"analyses/build_research_note.R\")))",
    "knitr::opts_knit$set(root.dir = report_root)", "```", "",
    "```{r saved-results, include=FALSE}", "source(\"analyses/build_research_note.R\")",
    "note_results <- concise_note_results()", "```", "",
    "<!-- Render from this project's deliverables directory with rmarkdown::render().",
    "Requires the saved run and project R dependencies; makes no model calls.",
    "Prompts and code excerpts below are literal archived text, never executed. -->", ""),
    collapse = "\n")
}

build_agent_supplement <- function() {
  header <- paste(c("---", "title: Supplement — prompts and agent outputs",
    "date: 17 October 2026", "output:", "  html_document:",
    "    self_contained: true", "    toc: true", "    toc_float: true",
    "    theme: readable", "---", "",
    "[Return to the concise report](agent-analysis-research-note.html)", ""), collapse = "\n")
  body <- paste0(note_prompt_appendix(), note_examples_appendix())
  body <- gsub(note_page_break(), "\n\n", body, fixed = TRUE)
  output <- file.path(ensure_dir("deliverables"), "agent-analysis-supplement.Rmd")
  writeLines(paste0(header, body), output, useBytes = TRUE)
  output
}

build_rmarkdown_note <- function() {
  body <- paste(readLines("docs/agent-analysis-research-note.md", warn = FALSE), collapse = "\n")
  body <- sub("(?s)^---\n.*?\n---\n", "", body, perl = TRUE)
  chunk <- "\n```{r realized-results, results='asis'}\ncat(note_results, \"\\n\")\n```\n"
  stopifnot(grepl("{{CONCISE_RESULTS}}", body, fixed = TRUE))
  body <- sub("{{CONCISE_RESULTS}}", chunk, body, fixed = TRUE)
  prompts <- gsub(note_page_break(), "\n\n", note_prompt_appendix(), fixed = TRUE)
  writeLines(prompts, file.path(ensure_dir("deliverables"), "agent-analysis-prompts.md"), useBytes = TRUE)
  build_agent_supplement()
  body <- paste0(body, "\n[Supplement: prompts, agent code, explanations, and recommendations](agent-analysis-supplement.html)\n")
  output <- file.path(ensure_dir("deliverables"), "agent-analysis-research-note.Rmd")
  writeLines(paste0(rmarkdown_note_header(), body), output, useBytes = TRUE)
  message("R Markdown report: ", output)
}

build_rmarkdown_note()
