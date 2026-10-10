# Integration tests on the processed dataset (run scripts/01_data_preparation.R first)
root <- file.path("..", "..")
path <- file.path(root, "data", "processed", "flu_weekly_national.csv")
skip_if_not(file.exists(path), "processed data not built yet")
d <- readr::read_csv(path, show_col_types = FALSE)

test_that("one row per week, chronologically ordered", {
  expect_false(anyDuplicated(d$iso_week) > 0)
  expect_true(all(diff(d$week_start) == 7))
})

test_that("target is complete, non-negative and consistent with population", {
  expect_false(any(is.na(d$oblig_cases)))
  expect_true(all(d$oblig_cases >= 0))
  expect_equal(d$oblig_inc_100k, d$oblig_cases / d$population * 1e5, tolerance = 1e-4)
})

test_that("flags follow the study design", {
  expect_setequal(unique(d$season[d$covid_season]), c("2020/21", "2021/22"))
  expect_setequal(unique(d$season[d$test_season]), c("2023/24", "2024/25", "2025/26"))
  expect_true(all(d$post2020 == (as.integer(substr(d$season, 1, 4)) >= 2022)))
})

test_that("no leakage-prone FOPH/BAG columns in processed data", {
  expect_false(any(c("trend", "deltaValue", "valueMean5y", "inc14d") %in% names(d)))
})

test_that("Sentinella predictor follows the study definition", {
  expect_true(all(d$sentinella_ili_rate >= 0, na.rm = TRUE))
  expect_equal(sort(d$iso_week[is.na(d$sentinella_ili_rate)]), c("2020-W11", "2020-W12"))
  expect_true(all(d$sentinella_source[!is.na(d$sentinella_ili_rate)] %in%
                    c("national", "regional_weighted_mean")))
})

test_that("study period and vintage as in the Preliminary Study", {
  expect_equal(range(d$iso_week), c("2013-W01", "2026-W37"))
  qc <- readr::read_csv(file.path(root, "output", "qc", "qc_checks.csv"), show_col_types = FALSE)
  expect_true(all(qc$result[qc$id %in% c("vintage_1", "vintage_2")] == "PASS"))
})
