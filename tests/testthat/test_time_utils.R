source(file.path("..", "..", "R", "time_utils.R"))

test_that("ISO week to Monday date is correct (incl. year boundaries)", {
  expect_equal(iso_week_to_date("2013-W01"), as.Date("2012-12-31"))
  expect_equal(iso_week_to_date("2015-W53"), as.Date("2015-12-28"))
  expect_equal(iso_week_to_date("2021-W01"), as.Date("2021-01-04"))
  expect_equal(iso_week_to_date("2026-W37"), as.Date("2026-09-07"))
})

test_that("non-existent and malformed ISO weeks are rejected", {
  expect_error(iso_week_to_date("2019-W53"))
  expect_error(iso_week_to_date("2019-53"))
})

test_that("53-week years are detected", {
  expect_equal(iso_weeks_in_year(c(2015, 2019, 2020, 2026)), c(53L, 52L, 53L, 53L))
})

test_that("ISO week sequence has no gaps across 53-week years", {
  s <- iso_week_seq("2015-W52", "2016-W02")
  expect_equal(s, c("2015-W52", "2015-W53", "2016-W01", "2016-W02"))
  expect_length(iso_week_seq("2013-W01", "2026-W37"), 715)
})

test_that("seasons run from W40 to W39", {
  expect_equal(iso_week_to_season(c("2023-W39", "2023-W40", "2024-W01", "2024-W39")),
               c("2022/23", "2023/24", "2023/24", "2023/24"))
  expect_equal(iso_week_to_season("2099-W40"), "2099/00")
  expect_equal(season_week(c("2023-W40", "2023-W52", "2024-W01", "2024-W39")),
               c(1L, 13L, 14L, 52L))
  # 53-week year: 2020-W53 is week 14, 2021-W39 is week 53
  expect_equal(season_week(c("2020-W53", "2021-W39")), c(14L, 53L))
})
