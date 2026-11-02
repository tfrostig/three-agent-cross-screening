source(file.path(project_root, "scripts/sharing_helpers.R"))

testthat::test_that("publication rejects private paths even with example filenames", {
  blocked <- c(".env", "nested/.env.local", "nested/private/code.R", "results/.env.example",
    "exports/results.zip", "renv/library/package/DESCRIPTION", "key.pem", "proposal.pdf")
  testthat::expect_true(all(publication_private_path(blocked)))
  testthat::expect_false(any(publication_private_path(c(".env.example", "R/io.R", "poetry.lock"))))
})

testthat::test_that("credential scanning detects tokens without matching signature substrings", {
  key <- paste0("sk-", strrep("x", 30))
  token <- paste0("ghp_", strrep("x", 30))
  pattern <- publication_secret_pattern()
  testthat::expect_true(grepl(pattern, key, perl = TRUE))
  testthat::expect_true(grepl(pattern, token, perl = TRUE))
  testthat::expect_false(grepl(pattern, paste0("random", key), perl = TRUE))
  testthat::expect_false(grepl(pattern, "OPENAI_API_KEY=", perl = TRUE))
})

testthat::test_that("sharing sanitizes copies and refuses to change frozen artifacts", {
  root <- tempfile("publication-copy-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE))
  original <- file.path(root, "original.json")
  copied <- file.path(root, "copy.json")
  text <- paste0('{"path":"', project_root, '/results"}')
  publication_write_text(text, original)
  testthat::expect_error(publication_copy(original, copied, immutable = TRUE), "local path")
  testthat::expect_identical(publication_copy(original, copied), "path-sanitized")
  testthat::expect_identical(publication_read_text(original), text)
  testthat::expect_match(publication_read_text(copied), "[PROJECT_ROOT]", fixed = TRUE)
})
