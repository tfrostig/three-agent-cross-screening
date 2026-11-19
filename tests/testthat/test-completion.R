source(file.path(project_root, "analyses/complete_timeouts.R"))

testthat::test_that("completion copies preserve bytes and refuse overwrite", {
  previous <- ensure_dir(tempfile("completion-old-"))
  destination <- ensure_dir(tempfile("completion-new-"))
  writeLines("preserved", file.path(previous, "artifact.md"))
  completion_copy(previous, destination)
  testthat::expect_identical(file_hash(file.path(previous, "artifact.md")),
    file_hash(file.path(destination, "artifact.md")))
  testthat::expect_error(completion_copy(previous, destination))
  testthat::expect_equal(readLines(file.path(previous, "artifact.md")), "preserved")
})

testthat::test_that("completion imports committed designs without observations or mutable work", {
  previous <- ensure_dir(tempfile("source-old-"))
  destination <- ensure_dir(tempfile("source-new-"))
  frozen <- ensure_dir(file.path(previous, "frozen"))
  audit <- ensure_dir(file.path(previous, "audit"))
  writeLines("hypotheses <- data.frame()", file.path(frozen, "analysis.R"))
  write_json(list(protocol="document-v2", hashes=list(analysis.R=file_hash(file.path(frozen,"analysis.R")))),
    file.path(frozen,"frozen.json"))
  write_json(list(frozen_sha256=file_hash(file.path(frozen,"frozen.json"))),file.path(frozen,"complete.json"))
  write_json(list(status="ok"), file.path(audit, "session.json"))
  ensure_dir(file.path(previous, "input"))
  ensure_dir(file.path(previous, "work"))
  row <- completion_source(previous, destination, NULL, NULL)
  testthat::expect_equal(row$disposition, "imported_frozen")
  testthat::expect_true(doc_committed(file.path(destination, "frozen")))
  testthat::expect_false(dir.exists(file.path(destination, "input")))
  testthat::expect_false(dir.exists(file.path(destination, "work")))
  testthat::expect_identical(file_hash(file.path(previous,"frozen/frozen.json")), row$frozen_sha256)
})
