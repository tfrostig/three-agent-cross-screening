#' Legacy original-run Word report builder. Requires saved results, Pandoc and XML helpers;
#'   visually verify any regenerated Word artifact.

source("R/bootstrap.R")
source("analyses/technical_note.R")

#' Insert a report page break using raw OpenXML
#'
#' @return Markdown fragment for Word-oriented rendering.
note_page_break <- function() {
  '\n\n```{=openxml}\n<w:p><w:r><w:br w:type="page"/></w:r></w:p>\n```\n\n'
}

#' Display literal prompt text as a fenced code block
#'
#' @param text Character text to escape, sanitize, or write.
#' @return Markdown string without interpreting prompt content as instructions.
prompt_block <- function(text) paste0("\n\n```text\n", sub("\n$", "", text), "\n```\n")

#' Select three reviewed examples from original frozen artifacts
#'
#' @return List of excerpt metadata and agent explanations; tied to the original run.
note_agent_examples <- function() {
  list(
    list(title = "Artificial row differences", design = "fwer_m100_c20/agent-1",
      lines = 31:37, context = "FWER objective, 100 measurements, c = 0.2. Here x and y are target observations, k is the smaller sample size, and direction is the frozen sign.",
      quote = "Arbitrary pairing loses efficiency compared with an ideal unequal-variance procedure, but avoids assuming equal variances and avoids relying on the Welch degrees-of-freedom approximation at n=6.",
      recommendations = c(
        "The family contains six positive mean-effect hypotheses: v0032, v0023, v0079, v0084, v0041, and v0069.",
        "Use the existing row order; this is an arbitrary pairing of independent observations, NOT an assertion of matched subjects. Row order must not be chosen by sorting outcomes or data-dependent matching.",
        "If effects reverse, the frozen positive hypothesis is a true null, not permission to switch direction. A failure to reject does not establish no effect or a negative effect."),
      interpretation = "The agent traded Welch’s approximate calibration for an exact normal-theory t argument. The assumption of normality remained necessary."),
    list(title = "Conservative calibration of a Welch statistic", design = "fdr_m100_c20/agent-2",
      lines = 34:41, context = "FDR objective, 100 measurements, c = 0.2. nx and ny are sample sizes; vx and vy are sample variances. Comments are retained as written.",
      quote = "The conservative degrees of freedom and BY correction can substantially reduce power, and exploratory large statistics can regress toward zero in the target subgroup.",
      recommendations = c(
        "I selected the ten measurements with absolute statistic at least 3.5 and froze their observed signs. All ten signs were positive: v0008, v0012, v0041, v0044, v0051, v0056, v0062, v0069, v0074, v0083.",
        "Apply Benjamini-Yekutieli (BY) to all m = 10 frozen directional p-values, with H_m = sum_{j=1}^m 1/j.",
        "The script raises informative errors for unsupported small samples, zero variances, missing values, or numerical overflow rather than fabricating p-values."),
      interpretation = "The mean contrast and standard error match Welch, but the reference distribution uses the smaller group degrees of freedom. Statistics against the claimed direction return p = 1."),
    list(title = "Exact permutation enumeration", design = "fdr_m100_c20/agent-1",
      lines = 28:37, context = "FDR objective, 100 measurements, c = 0.2. assignments contains all group allocations, generated elsewhere in the script. Six exposed and six controls give 924 allocations.",
      quote = "Without this common-shape location-shift assumption, equality or ordering of means alone does not justify an exact permutation test.",
      recommendations = c(
        "I selected the ten highest-ranked coordinates, a focused family with absolute design statistics from 2.935 to 7.540, and froze each observed sign. Nine are positive and v0057 is negative.",
        "Apply Benjamini–Yekutieli (BY) to all K supplied frozen directional hypotheses, without screening target p-values.",
        "The important scientific limitation is the unverified marginal shift model; these design data cannot establish it, and users should not interpret the conditional guarantee as distribution-free mean inference."),
      interpretation = "The helper counts allocations at least as extreme as the observed statistic. The agent explicitly limited its mean-effect justification to a common-shape shift model.")
  )
}

#' Format one archived code example with its explanation
#'
#' @param example Archived example metadata and exact code/report excerpts.
#' @return Markdown text quoting the source artifact and separating editorial commentary.
render_agent_example <- function(example) {
  frozen <- file.path("results/live-first/scenarios", example$design, "frozen")
  verify_frozen(frozen)
  code <- readLines(file.path(frozen, "analysis.R"), warn = FALSE)
  report <- paste(readLines(file.path(frozen, "report.md"), warn = FALSE), collapse = "\n")
  quotes <- c(example$quote, example$recommendations)
  stopifnot(max(example$lines) <= length(code),
    all(vapply(quotes, function(x) grepl(x, report, fixed = TRUE), logical(1))))
  excerpt <- paste(code[example$lines], collapse = "\n")
  source <- sprintf("Source: %s/frozen; analysis.R lines %d to %d and report.md.",
                    example$design, min(example$lines), max(example$lines))
  verify_frozen(frozen)
  paste0("\n## ", example$title, "\n\n", example$context,
    "\n\nAgent explanation verbatim\n\n> ", example$quote,
    "\n\nAgent recommendations and cautions verbatim\n\n",
    paste0("> ", example$recommendations, collapse = "\n\n"),
    "\n\nAgent R code excerpt\n\n```r\n", excerpt, "\n```\n\n",
    "Our reading: ", example$interpretation, "\n\n", source, "\n")
}

#' Combine original agent examples into the supplement
#'
#' @return Markdown appendix string.
note_examples_appendix <- function() {
  examples <- vapply(note_agent_examples(), render_agent_example, character(1))
  paste0(note_page_break(), "# Appendix D Examples from frozen agent designs\n\n",
    "These three examples illustrate submitted analysis choices, explanations, and recommendations. They were selected to show different approaches, not to estimate their frequency or quality. Code is copied directly from the frozen R files. All quotations are exact passages from the corresponding agent reports. Recommendations include the submitted hypothesis choices, application instructions, and interpretive cautions; they are not new advice generated for this supplement. Excerpts show core calculations rather than complete runnable analyses. Our interpretations are labeled separately.\n",
    paste(examples[1:2], collapse = "\n"), note_page_break(), examples[3])
}

#' Collect archived shared and session prompts for the original run
#'
#' @return Markdown appendix; current prompt templates are not substituted for archived text.
note_prompt_appendix <- function() {
  paths <- list.files("results/live-first/scenarios", pattern = "prompts.json$",
                       recursive = TRUE, full.names = TRUE)
  archived <- lapply(paths, read_json)
  stopifnot(length(archived) == 24L,
    all(vapply(archived, function(x) identical(x$system, archived[[1]]$system), logical(1))),
    all(vapply(archived, function(x) identical(x$developer, archived[[1]]$developer), logical(1))))
  fwer <- read_json("results/live-first/scenarios/fwer_m20_c20/agent-1/audit/prompts.json")
  fdr <- read_json("results/live-first/scenarios/fdr_m100_c20/agent-1/audit/prompts.json")
  paste0(note_page_break(), "# Appendix A Shared system prompt\n\n",
    "The following text is reproduced from the archived live prompts. All 24 sessions shared the same system prompt and instructions. Session messages varied only in identifier, dimensions, and testing criterion. Tool interfaces supplied the execution capabilities described in the main text.\n",
    prompt_block(archived[[1]]$system), note_page_break(),
    "# Appendix B Shared instructions\n", prompt_block(archived[[1]]$developer),
    note_page_break(), "# Appendix C Session messages\n\n",
    "These are two actual archived messages, one for each objective. The FWER example had eight observations per sample and 20 measurements; the FDR example had six per sample and 100 measurements. Other sessions used the corresponding dimensions and their own opaque identifiers.\n\n",
    "## FWER session message\n", prompt_block(fwer$user),
    "\n## FDR session message\n", prompt_block(fdr$user))
}

#' Fill the historical note template from saved results
#'
#' @return Writes the composed Markdown note and returns its destination path; requires saved
#'   comparison outputs and original artifacts.
compose_research_note <- function() {
  body <- paste(readLines("docs/agent-analysis-research-note.md", warn = FALSE), collapse = "\n")
  sections <- list(CONCISE_RESULTS = concise_note_results())
  for (name in names(sections)) {
    marker <- paste0("{{", name, "}}")
    stopifnot(grepl(marker, body, fixed = TRUE))
    body <- sub(marker, sections[[name]], body, fixed = TRUE)
  }
  output <- file.path(ensure_dir("deliverables"), "agent-analysis-research-note.md")
  writeLines(body, output, useBytes = TRUE)
  output
}

#' Apply Word table-cell widths, borders and paragraph styles
#'
#' @param row Character scalar containing a legacy Word table row's XML.
#' @param widths Numeric cell widths for the legacy Word formatter.
#' @param header Logical; apply header-row styling.
#' @param last Logical; apply the final-row border rule.
#' @return Modified XML row string for the legacy Word formatter.
style_note_row <- function(row, widths, header, last) {
  if (grepl('<w:trPr>', row, fixed = TRUE)) {
    row <- sub('<w:trPr>', '<w:trPr><w:cantSplit/>', row, fixed = TRUE)
  } else row <- sub('<w:tr>', '<w:tr><w:trPr><w:cantSplit/></w:trPr>', row, fixed = TRUE)
  if (!last) row <- gsub('<w:pPr>', '<w:pPr><w:keepNext/>', row, fixed = TRUE)
  cells <- regmatches(row, gregexpr('<w:tc>.*?</w:tc>', row, perl = TRUE))[[1]]
  stopifnot(length(cells) == length(widths))
  borders <- paste0('<w:', c("top", "left", "bottom", "right"),
                     ' w:val="single" w:sz="4" w:color="D9D9D9"/>', collapse = "")
  for (i in seq_along(cells)) {
    shade <- if (header) '<w:shd w:val="clear" w:fill="E8EDF2"/>' else ''
    properties <- paste0('<w:tcPr><w:tcW w:w="', widths[i], '" w:type="dxa"/>',
      '<w:vAlign w:val="center"/><w:tcBorders>', borders, '</w:tcBorders>', shade, '</w:tcPr>')
    cell <- sub('<w:tcPr />', properties, cells[i], fixed = TRUE)
    row <- sub(cells[i], cell, row, fixed = TRUE)
  }
  row
}

#' Apply layout rules to one legacy Word table
#'
#' @param table Character scalar containing a Word table's XML.
#' @return Modified XML table string.
style_one_table <- function(table) {
  rows <- regmatches(table, gregexpr('<w:tr>.*?</w:tr>', table, perl = TRUE))[[1]]
  cells <- regmatches(rows[1], gregexpr('<w:tc>.*?</w:tc>', rows[1], perl = TRUE))[[1]]
  widths <- note_table_widths(length(cells), grepl("J / K", table, fixed = TRUE))
  padding <- paste0('<w:', c("top", "left", "bottom", "right"),
                     ' w:w="90" w:type="dxa"/>', collapse = "")
  properties <- paste0('<w:tblCellMar>', padding, '</w:tblCellMar>')
  table <- sub('</w:tblPr>', paste0(properties, '</w:tblPr>'), table, fixed = TRUE)
  grid <- paste0('<w:tblGrid>', paste0('<w:gridCol w:w="', widths, '"/>', collapse = ""), '</w:tblGrid>')
  table <- sub('<w:tblGrid>.*?</w:tblGrid>', grid, table, perl = TRUE)
  for (i in seq_along(rows)) {
    row <- style_note_row(rows[i], widths, i == 1L, i == length(rows) || (length(rows) > 12L && i > 1L))
    table <- sub(rows[i], row, table, fixed = TRUE)
  }
  table
}

#' Choose widths for the legacy report's table types
#'
#' @param columns Number of columns in the report table.
#' @param per_design Logical; use the per-design appendix layout.
#' @return Numeric vector of cell widths for the supplied table shape.
note_table_widths <- function(columns, per_design) {
  if (columns == 2L) return(c(6300L, 3636L))
  if (columns == 3L) return(c(1000L, 7300L, 1636L))
  if (columns == 5L) return(c(2300L, 1400L, 2100L, 2100L, 2036L))
  if (columns == 6L && per_design) return(c(3600L, 1000L, 700L, 1300L, 1400L, 1936L))
  if (columns == 6L) return(c(3000L, 1387L, 1387L, 1387L, 1387L, 1388L))
  rep(9936L / columns, columns)
}

#' Style all tables inside a legacy Word document
#'
#' @param document Character scalar containing the Word document XML.
#' @return Modified document XML string; does not mutate the caller's input.
style_note_tables <- function(document) {
  tables <- regmatches(document, gregexpr('<w:tbl>.*?</w:tbl>', document, perl = TRUE))[[1]]
  for (table in tables) document <- sub(table, style_one_table(table), document, fixed = TRUE)
  document <- gsub('</w:tbl><w:p><w:pPr>',
    '</w:tbl><w:p><w:pPr><w:spacing w:before="120" w:after="120"/>', document, fixed = TRUE)
  paragraphs <- regmatches(document, gregexpr('<w:p>.*?</w:p>', document, perl = TRUE))[[1]]
  introduction <- paragraphs[grepl('The table reports realized power', paragraphs, fixed = TRUE)]
  stopifnot(length(introduction) == 1L)
  kept <- sub('<w:pPr>', '<w:pPr><w:keepNext/>', introduction, fixed = TRUE)
  sub(introduction, kept, document, fixed = TRUE)
}

#' Adjust code and prompt paragraph styles in Word XML
#'
#' @param styles Character scalar containing Word styles XML.
#' @return Modified styles XML string.
style_prompt_text <- function(styles) {
  pattern <- '(?s)<w:style[^>]*w:styleId="(SourceCode|VerbatimChar)"[^>]*>.*?</w:style>'
  matches <- regmatches(styles, gregexpr(pattern, styles, perl = TRUE))[[1]]
  properties <- '<w:rFonts w:ascii="Courier New" w:hAnsi="Courier New"/><w:sz w:val="18"/><w:szCs w:val="18"/>'
  for (style in matches) {
    updated <- if (grepl('<w:rPr>', style, fixed = TRUE)) {
      sub('(?s)<w:rPr>.*?</w:rPr>', paste0('<w:rPr>', properties, '</w:rPr>'), style, perl = TRUE)
    } else sub('</w:style>', paste0('<w:rPr>', properties, '</w:rPr></w:style>'), style, fixed = TRUE)
    updated <- sub('<w:wordWrap w:val="off" />', '<w:wordWrap w:val="on"/>', updated, fixed = TRUE)
    styles <- sub(style, updated, styles, fixed = TRUE)
  }
  styles
}

#' Apply legacy report font, spacing, and heading styles
#'
#' @param styles Character scalar containing Word styles XML.
#' @return Modified styles XML string.
style_note_styles <- function(styles) {
  styles <- gsub('<w:color[^>]*/>', '<w:color w:val="000000"/>', styles)
  styles <- gsub('<w:pBdr>.*?</w:pBdr>', '', styles, perl = TRUE)
  styles <- gsub('<w:rFonts[^>]*/>', '<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman"/>', styles)
  styles <- gsub('w:val="24"', 'w:val="22"', styles, fixed = TRUE)
  styles <- gsub('w:val="56"', 'w:val="40"', styles, fixed = TRUE)
  styles <- gsub('w:val="32"', 'w:val="28"', styles, fixed = TRUE)
  styles <- gsub('w:after="180" w:before="180"', 'w:after="120" w:before="0"', styles, fixed = TRUE)
  style_prompt_text(styles)
}

#' Unpack, style, and repack a generated legacy Word note
#'
#' @param path Input or destination filesystem path, as indicated in the description.
#' @return Rewrites the supplied docx; publishing a document still requires visual
#'   verification.
style_word_note <- function(path) {
  directory <- tempfile("research-note-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE))
  utils::unzip(path, exdir = directory)
  styles_path <- file.path(directory, "word", "styles.xml")
  styles <- paste(readLines(styles_path, warn = FALSE), collapse = "\n")
  writeLines(style_note_styles(styles), styles_path, useBytes = TRUE)
  document_path <- file.path(directory, "word", "document.xml")
  document <- paste(readLines(document_path, warn = FALSE), collapse = "\n")
  document <- gsub('<w:pgMar[^>]*/>',
    '<w:pgMar w:top="1152" w:right="1152" w:bottom="1152" w:left="1152" w:header="360" w:footer="360" w:gutter="0"/>', document)
  writeLines(style_note_tables(document), document_path, useBytes = TRUE)
  old <- setwd(directory)
  on.exit(setwd(old), add = TRUE)
  unlink(path)
  utils::zip(path, list.files(".", recursive = TRUE, all.files = TRUE, no.. = TRUE), flags = "-q")
}

#' Build the legacy original-run Word research note
#'
#' @return Writes deliverables Markdown/docx from saved results; this is not the revised-run
#'   summary.
build_research_note <- function() {
  input <- compose_research_note()
  path <- file.path(dirname(input), "agent-analysis-research-note.docx")
  rmarkdown::pandoc_convert(input, from = "markdown", to = "docx",
                           output = path, options = c("--standalone"))
  style_word_note(path)
  stopifnot(file.exists(path), file.info(path)$size > 10000)
  message("Research note: ", path)
}

if (sys.nframe() == 0L) build_research_note()
