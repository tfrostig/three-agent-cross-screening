testthat::test_that("directional scoring uses target signs including negative claims", {
  hypotheses <- data.frame(hypothesis_id = c("a+", "a-", "b+", "c-"),
                           measurement_id = c("a", "a", "b", "c"), direction = c(1, -1, 1, -1))
  result <- data.frame(hypothesis_id = hypotheses$hypothesis_id, p_value = rep(.01, 4),
                       reject = rep(TRUE, 4), adjusted_p_value = rep(.04, 4))
  score <- score_claims(hypotheses, result, c(a = 1, b = 0, c = -1))
  testthat::expect_equal(score$false, 2)
  testthat::expect_equal(score$fdp, .5)
  testthat::expect_equal(score$power, 1)
  duplicate <- rbind(hypotheses, hypotheses[1, ])
  testthat::expect_error(validate_hypotheses(duplicate, c("a", "b", "c")))
  result$p_value[1] <- NA_real_
  testthat::expect_error(validate_result(result, hypotheses))
})

testthat::test_that("baselines match R tails and corrections", {
  set.seed(9)
  x <- matrix(rnorm(40), 20, 2, dimnames = list(NULL, c("a", "b")))
  y <- matrix(rnorm(40), 20, 2, dimnames = list(NULL, c("a", "b")))
  test <- baseline_analysis(x, y, "FWER", .05 / 3)
  testthat::expect_equal(test$result$p_value[1], t.test(x[, 1], y[, 1], alternative = "greater")$p.value)
  testthat::expect_equal(test$result$adjusted_p_value, p.adjust(test$result$p_value, "holm"))
  z <- baseline_analysis(x, y, "FDR", .05 / 3, TRUE)
  testthat::expect_equal(z$result$p_value[1], pnorm((mean(x[, 1]) - mean(y[, 1])) / sqrt(2 / 20), lower.tail = FALSE))
  testthat::expect_equal(z$result$adjusted_p_value, p.adjust(z$result$p_value, "BY"))
})

testthat::test_that("empty selections remain valid and failed groups do not become zero", {
  hypotheses <- data.frame(hypothesis_id = character(), measurement_id = character(), direction = integer())
  testthat::expect_silent(validate_hypotheses(hypotheses, "a"))
  testthat::expect_equal(score_claims(hypotheses, empty_result(), c(a = 1))$fdp, 0)
  scenario <- scenario_grid(load_config(file.path(project_root, "config/pilot.yml")))[1, ]
  row <- score_row(scenario, "agent", 1, 2, "ok", metrics = score_claims(hypotheses, empty_result(), c(a = 1)))
  summary <- global_scores(row)
  testthat::expect_false(summary$complete)
  testthat::expect_true(is.na(summary$realized_fdp))
})

testthat::test_that("unsafe artifacts and report HTML cannot escape", {
  root <- ensure_dir(tempfile("artifact-"))
  outside <- tempfile("canary-")
  writeLines("private-canary", outside)
  file.symlink(outside, file.path(root, "analysis.R"))
  testthat::expect_error(safe_file(file.path(root, "analysis.R"), root), "linked")
  testthat::expect_equal(escape_html('<script>alert("x")</script>'),
                         '&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;')
  unlink(c(root, outside), recursive = TRUE)
})

testthat::test_that("CSV round trips preserve empty and optional numeric columns", {
  path <- tempfile(fileext = ".csv")
  result <- data.frame(hypothesis_id = "123", p_value = .1, reject = FALSE,
                       adjusted_p_value = NA_real_)
  write_csv(result, path)
  restored <- read_result_table(path)
  testthat::expect_identical(restored, result)
  write_csv(empty_result(), path)
  testthat::expect_identical(read_result_table(path), empty_result())
  unlink(path)
})
