testthat::test_that("all twelve scenarios have the expected pairing", {
  config <- load_config(file.path(project_root, "config/pilot.yml"))
  scenarios <- scenario_grid(config)
  testthat::expect_equal(nrow(scenarios), 12L)
  testthat::expect_equal(length(unique(scenarios$data_id)), 9L)
  testthat::expect_equal(sum(scenarios$m == 100), 6L)
  testthat::expect_true(all(scenarios$m[scenarios$criterion == "FWER"] %in% c(20, 100)))
})

testthat::test_that("state labels preserve subgroup positions and signal probabilities", {
  set.seed(2)
  states <- draw_states(100000, list('000' = .6, '001' = .05, '010' = .05, '011' = .05,
                                    '100' = .05, '101' = .05, '110' = .05, '111' = .1))
  testthat::expect_equal(rowMeans(states), rep(.25, 3), tolerance = .01)
  testthat::expect_equal(mean(colSums(states) == 0), .6, tolerance = .01)
  testthat::expect_equal(draw_states(3, list('100' = 1)), rbind(rep(1L, 3), rep(0L, 3), rep(0L, 3)))
})

testthat::test_that("effects preserve exact nulls and folded-normal magnitudes", {
  set.seed(3)
  states <- matrix(rep(c(0, 1), 3000), 3)
  effects <- draw_effects(states, 1, 1)
  testthat::expect_true(all(effects[states == 0] == 0))
  testthat::expect_true(all(effects[states == 1] > 0))
  testthat::expect_gt(mean(effects[states == 1]), 1)
})

testthat::test_that("sample size is the strict minimum and uses alpha/m", {
  effects <- matrix(c(0, .5, 1, 1.4, 0, .9, .8, 1, 0), 3)
  found <- smallest_sample(effects, .6, .05)
  testthat::expect_gt(min(found$power), .6)
  testthat::expect_lte(min(found$previous_power), .6)
  brute <- which(vapply(seq_len(found$n), function(n) min(planning_power(n, effects, .05)) > .6, logical(1)))[1]
  testthat::expect_equal(found$n, brute)
  testthat::expect_error(smallest_sample(matrix(0, 3, 4), .2, .05), "undefined_power")
  testthat::expect_error(smallest_sample(matrix(.001, 3, 4), .6, .05, max_n = 2), "max_n")
})

testthat::test_that("streams are reproducible and controls are independent", {
  config <- load_config(file.path(project_root, "config/pilot.yml"))
  streams <- seed_streams(config$seed, 3)
  first <- generate_setting(config, 100, .2, streams)
  second <- generate_setting(config, 100, .2, streams)
  testthat::expect_identical(first, second)
  testthat::expect_false(identical(first$observations[[1]]$unexposed, first$observations[[2]]$unexposed))
  testthat::expect_equal(sum(vapply(first$observations, function(p) nrow(p$exposed) + nrow(p$unexposed), integer(1))),
                         6 * first$planning$n)
})

testthat::test_that("selecting a scenario does not change its generator stream", {
  config <- load_config(file.path(project_root, "config/pilot.yml"))
  all <- scenario_grid(config)
  chosen <- all[all$id == "fwer_m20_c20", , drop = FALSE]
  full_root <- ensure_dir(tempfile("full-"))
  single_root <- ensure_dir(tempfile("single-"))
  full <- prepare_data(config, all, full_root)
  single <- prepare_data(config, chosen, single_root)
  full_setting <- readRDS(full$path[full$data_id == chosen$data_id])
  single_setting <- readRDS(single$path[1])
  testthat::expect_identical(full_setting, single_setting)
  unlink(c(full_root, single_root), recursive = TRUE)
})
