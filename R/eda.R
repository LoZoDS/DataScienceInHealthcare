# R/eda.R: helps for EDA

# Load the national weekly analysis dataset

# Adds two EDA flags (settings in config.R):
# in_summary: season enters summary statistics across seasons, (FALSE for incomplete seasons and 2020/21)
# lockdown_2020: week lies after the start of the COVID-19 lockdown in season 2019/20 (feedback on WP 4.1)
load_national <- function(path = file.path(PATH_PROCESSED, "flu_weekly_national.csv")) {
  if (!file.exists(path)) {
    stop("Processed data not found: ", path,
         "\nRun scripts/01_data_preparation.R first.")
  }
  readr::read_csv(path, show_col_types = FALSE,
                  col_types = readr::cols(iso_week = "c", season = "c",
                                          sentinella_source = "c", period = "c")) |>
    dplyr::mutate(
      period        = factor(period, levels = c("pre2020_partial", "pre2020",
                                                "covid", "post2020")),
      in_summary    = !season %in% c(EDA_INCOMPLETE_SEASONS, EDA_NO_SEASON),
      lockdown_2020 = iso_week %in% EDA_LOCKDOWN_WEEKS_2020
    )
}

# Load the stratified long table (canton, Sentinella region, age group, sex, type)
# Reminder: sum only within one system x dimension. Oblig age group, sex and type refer to CH + FL; Sentinella strata are extrapolated and not additive.
load_strata <- function(path = file.path(PATH_PROCESSED, "flu_weekly_strata_long.csv")) {
  if (!file.exists(path)) {
    stop("Processed data not found: ", path,
         "\nRun scripts/01_data_preparation.R first.")
  }
  readr::read_csv(path, show_col_types = FALSE,
                  col_types = readr::cols(iso_week = "c", season = "c",
                                          level = "c", geo = "c"))
}

# Sanity checks on the inputs; stops with a clear message if the processed data do not match the study design.
check_eda_inputs <- function(national, strata) {
  n_expected <- length(iso_week_seq(STUDY_START_ISOWEEK, STUDY_END_ISOWEEK))
  needed <- c("iso_week", "season", "season_week", "oblig_inc_100k",
              "sentinella_ili_rate", "sentinella_ili_inc", "period",
              "covid_season", "post2020", "test_season", "complete_season")
  problems <- c(
    if (nrow(national) != n_expected)
      sprintf("national: %d rows, expected %d", nrow(national), n_expected),
    if (anyDuplicated(national$iso_week)) "national: duplicated ISO weeks",
    if (length(setdiff(needed, names(national))))
      paste("national: missing columns", paste(setdiff(needed, names(national)), collapse = ", ")),
    if (any(is.na(national$oblig_inc_100k))) "national: target has missing weeks",
    if (!all(c("canton", "sentinella_region", "agegroup", "sex", "type") %in% strata$dimension))
      "strata: not all dimensions present"
  )
  if (length(problems)) stop("Input check failed:\n- ", paste(problems, collapse = "\n- "))
  invisible(TRUE)
}
