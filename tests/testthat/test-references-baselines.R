testthat::test_that("reference packs invalidate cache identity and reject stale payloads", {
  config <- load_config(file.path(project_root, "config/pilot.yml"))
  original <- reference_pack_digest(config)
  root <- tempfile("reference-test-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE))
  files <- list.files(reference_pack_path(config), full.names = TRUE)
  stopifnot(all(file.copy(files, root, recursive = TRUE)))
  config$reference_pack <- root
  testthat::expect_identical(reference_pack_digest(config), original)
  brief <- file.path(root, "brief.md")
  cat("\nChanged methods brief.\n", file = brief, append = TRUE)
  testthat::expect_error(reference_pack_digest(config), "stale")
  catalog <- read_json(file.path(root, "catalog.json"))
  catalog$files[["brief.md"]] <- file_hash(brief)
  write_json(catalog, file.path(root, "catalog.json"))
  testthat::expect_false(identical(reference_pack_digest(config), original))
  config$reference_digest <- original
  testthat::expect_error(reference_pack_digest(config), "changed during this run")
})

testthat::test_that("BH and BY baselines share raw tests but have distinct corrections and IDs", {
  set.seed(19)
  x <- matrix(rnorm(60), 20, 3, dimnames = list(NULL, letters[1:3]))
  y <- matrix(rnorm(60), 20, 3, dimnames = list(NULL, letters[1:3]))
  config <- load_config(file.path(project_root, "config/pilot.yml"))
  for (known in c(FALSE, TRUE)) {
    bh <- baseline_analysis(x, y, "FDR", .05 / 3, known, "BH")
    by <- baseline_analysis(x, y, "FDR", .05 / 3, known, "BY")
    testthat::expect_identical(bh$result$p_value, by$result$p_value)
    testthat::expect_equal(bh$result$adjusted_p_value, p.adjust(bh$result$p_value, "BH"))
    testthat::expect_equal(by$result$adjusted_p_value, p.adjust(by$result$p_value, "BY"))
  }
  scenario <- list(id = "fixture", criterion = "FDR", m = 3, c = .2)
  pair <- list(exposed = x, unexposed = y)
  setting <- list(observations = rep(list(pair), 3), effects = matrix(0, 3, 3))
  output <- ensure_dir(tempfile("baselines-"))
  on.exit(unlink(output, recursive = TRUE))
  scores <- do.call(rbind, evaluate_scenario_baselines(config, scenario, setting, output))
  testthat::expect_equal(nrow(scores), 12L)
  testthat::expect_true(all(scores$status == "ok"))
  testthat::expect_setequal(unique(scores$method),
    c("welch_bh", "welch_by", "oracle_variance_z_bh", "oracle_variance_z_by"))
  testthat::expect_true(all(table(scores$method) == 3L))
})

testthat::test_that("configurations reject invalid correction lists", {
  config <- load_config(file.path(project_root, "config/pilot.yml"))
  config$baseline_fdr_methods <- c("BH", "BH")
  testthat::expect_error(validate_config(config))
  config$baseline_fdr_methods <- "invalid"
  testthat::expect_error(validate_config(config))
})
