# =============================================================================
# R/prepare.R -- build the analysis-ready datasets (Section 4.1)
# =============================================================================

# Columns from the raw exports that are NOT carried into the processed data.
# They are FOPH/BAG-derived statistics that use information from later weeks
# or other seasons (trend, deltas, 5-/10-year reference values, 14-day
# incidence) and would leak information into the forecasting models.
LEAKAGE_COLUMNS <- c("trend", "deltaValue", "deltaIncValue", "incValuePrctChange",
                     "valueMean5y", "inc14d")

# ---- National weekly series ----------------------------------------------------

#' National weekly mandatory-reporting series (Preliminary Study, Section 3)
#'
#' "Mandatory reporting cases are summed across strata to national weekly
#' counts and divided by the permanent resident population (BFS)."
#' The raw file holds several overlapping stratifications (canton, age group,
#' sex, type), so the sum is taken over ONE complete, non-overlapping set of
#' strata: the 26 cantons plus "unknown" canton. This equals the FOPH/BAG
#' national value for Switzerland (checked in qc_oblig_consistency(), C2).
#' Switzerland only (without Liechtenstein), matching the BFS denominator.
national_oblig <- function(oblig, population) {
  pop <- add_population_years(population, years = 2013:2026)
  oblig |>
    dplyr::filter(valueCategory == "cases", temporal_type == "iso_week",
                  georegion_type == "canton") |>
    dplyr::group_by(iso_week = temporal) |>
    dplyr::summarise(oblig_cases = sum(value), .groups = "drop") |>
    dplyr::mutate(year = as.integer(substr(iso_week, 1, 4))) |>
    dplyr::left_join(pop, by = "year") |>
    dplyr::mutate(oblig_inc_100k = oblig_cases / population * 1e5) |>
    dplyr::select(iso_week, oblig_cases, population, oblig_inc_100k)
}

#' National weekly Sentinella ILI rate (Preliminary Study, Section 3)
#'
#' "Sentinella ILI rates are reported per Sentinella region; the national rate
#' is taken from the national values in the dataset or otherwise computed as a
#' weighted mean of the regional rates."
#'   sentinella_ili_rate  ILI consultations per 1,000 consultations (study
#'                        definition) = prctConsultations x 10
#'   sentinella_ili_inc   ILI consultations per 100,000 inhabitants (incValue),
#'                        the scale of the FOPH/BAG epidemic threshold (4.2)
#' Weights for the fallback: number of consultations for the rate per 1,000
#' consultations, extrapolation base for the rate per 100,000. Both reproduce
#' the national values exactly where available (QC check sent_C5).
national_sentinella <- function(sent) {
  national <- sent |>
    dplyr::filter(temporal_type == "week", georegion == "CH",
                  agegroup == "all", sex == "all") |>
    dplyr::transmute(iso_week = temporal,
                     rate_nat = prctConsultations * 10,
                     inc_nat  = incValue)
  regional <- regional_weighted_mean(sent)
  national |>
    dplyr::full_join(regional, by = "iso_week") |>
    dplyr::mutate(
      sentinella_source   = dplyr::case_when(!is.na(rate_nat) ~ "national",
                                             !is.na(rate_reg) ~ "regional_weighted_mean",
                                             TRUE ~ NA_character_),
      sentinella_ili_rate = dplyr::coalesce(rate_nat, rate_reg),
      sentinella_ili_inc  = dplyr::coalesce(inc_nat, inc_reg)
    ) |>
    dplyr::select(iso_week, sentinella_ili_rate, sentinella_ili_inc, sentinella_source)
}

#' Weighted mean of the six Sentinella regions per week
regional_weighted_mean <- function(sent) {
  sent |>
    dplyr::filter(temporal_type == "week", georegion_type == "sentinella_region",
                  georegion != "unknown",
                  !is.na(prctConsultations), !is.na(incValue)) |>
    dplyr::group_by(iso_week = temporal) |>
    dplyr::summarise(
      rate_reg = stats::weighted.mean(prctConsultations * 10, totalConsultationsExtrapolation),
      inc_reg  = stats::weighted.mean(incValue, popExtrapolation),
      .groups = "drop")
}

#' Population lookup with fallback to the latest available year
add_population_years <- function(population, years) {
  out <- tibble::tibble(year = years) |>
    dplyr::left_join(dplyr::select(population, year, population), by = "year")
  if (POPULATION_FALLBACK_TO_LATEST) {
    latest <- population$population[which.max(population$year)]
    out$population[is.na(out$population) & out$year > max(population$year)] <- latest
  }
  out
}

#' Merge both systems on a complete weekly calendar and add time/season flags
build_national_weekly <- function(oblig, sent, population,
                                  from = STUDY_START_ISOWEEK, to = STUDY_END_ISOWEEK) {
  calendar <- tibble::tibble(iso_week = iso_week_seq(from, to))
  calendar |>
    dplyr::left_join(national_oblig(oblig, population), by = "iso_week") |>
    dplyr::left_join(national_sentinella(sent), by = "iso_week") |>
    add_time_variables() |>
    add_flags() |>
    dplyr::relocate(iso_week, week_start, iso_year, iso_wk, season, season_week)
}

add_time_variables <- function(df) {
  p <- parse_iso_week(df$iso_week)
  df |>
    dplyr::mutate(
      week_start  = iso_week_to_date(iso_week),
      iso_year    = p$year,
      iso_wk      = p$week,
      season      = iso_week_to_season(iso_week, SEASON_START_WEEK),
      season_week = season_week(iso_week, SEASON_START_WEEK)
    )
}

add_flags <- function(df) {
  post_start <- season_label_start(POST_2020_FIRST_SEASON)
  # a season is complete if all its ISO weeks (W40 ... W39) are in the data
  # (W40..W52/53 of year y plus W01..W39 of y+1 = number of ISO weeks in y)
  expected_weeks <- function(season) iso_weeks_in_year(season_label_start(season))
  df |>
    dplyr::group_by(season) |>
    dplyr::mutate(complete_season = dplyr::n() == expected_weeks(dplyr::first(season))) |>
    dplyr::ungroup() |>
    dplyr::mutate(
      covid_season   = season %in% COVID_SEASONS,
      period         = dplyr::case_when(
        season %in% PRE_2020_SEASONS                  ~ "pre2020",
        covid_season                                  ~ "covid",
        season_label_start(season) >= post_start      ~ "post2020",
        TRUE                                          ~ "pre2020_partial"),
      post2020       = season_label_start(season) >= post_start,
      test_season    = season %in% TEST_SEASONS,
      sentinella_missing = is.na(sentinella_ili_rate),
      oblig_missing  = is.na(oblig_cases)
    )
}

# ---- Stratified long table for descriptive analyses (Section 4.2) --------------

#' One tidy long table with every breakdown of both systems
#' (dimension = canton | sentinella_region | agegroup | sex | type)
build_strata_long <- function(oblig, sent) {
  ow <- dplyr::filter(oblig, valueCategory == "cases", temporal_type == "iso_week")
  sw <- dplyr::filter(sent, temporal_type == "week")
  o <- dplyr::bind_rows(
    ow |> dplyr::filter(georegion_type == "canton") |>
      dplyr::mutate(dimension = "canton", level = georegion),
    ow |> dplyr::filter(georegion == "CHFL", agegroup != "all") |>
      dplyr::mutate(dimension = "agegroup", level = agegroup),
    ow |> dplyr::filter(georegion == "CHFL", sex != "all") |>
      dplyr::mutate(dimension = "sex", level = sex),
    ow |> dplyr::filter(georegion == "CHFL", type != "all") |>
      dplyr::mutate(dimension = "type", level = type)
  ) |>
    dplyr::transmute(system = "oblig", iso_week = temporal, dimension, level,
                     geo = georegion, count = value, incidence_100k = incValue,
                     unit = "lab-confirmed cases / per 100,000")
  s <- dplyr::bind_rows(
    sw |> dplyr::filter(georegion_type == "sentinella_region") |>
      dplyr::mutate(dimension = "sentinella_region", level = georegion),
    sw |> dplyr::filter(georegion == "CH", agegroup != "all") |>
      dplyr::mutate(dimension = "agegroup", level = agegroup),
    sw |> dplyr::filter(georegion == "CH", sex != "all") |>
      dplyr::mutate(dimension = "sex", level = sex)
  ) |>
    dplyr::transmute(system = "sentinella", iso_week = temporal, dimension, level,
                     geo = georegion, count = value, incidence_100k = incValue,
                     unit = "extrapolated ILI consultations / per 100,000")
  dplyr::bind_rows(o, s) |>
    dplyr::filter(iso_week >= STUDY_START_ISOWEEK, iso_week <= STUDY_END_ISOWEEK) |>
    dplyr::mutate(season = iso_week_to_season(iso_week, SEASON_START_WEEK)) |>
    dplyr::arrange(system, dimension, level, iso_week)
}

# ---- Season boundaries (rule from Section 4.2) ---------------------------------

#' Onset = first of two consecutive weeks with ILI rate above the season's
#' threshold; end = last week above the threshold. Returns one row per season.
#' Seasons without a threshold get NA (see docs/open_issues.md).
season_boundaries <- function(national, thresholds) {
  national |>
    dplyr::left_join(thresholds, by = "season") |>
    dplyr::group_by(season) |>
    dplyr::arrange(iso_week, .by_group = TRUE) |>
    dplyr::summarise(
      threshold = dplyr::first(threshold_ili_per_100k),
      onset_week = {
        above <- sentinella_ili_inc > threshold
        above[is.na(above)] <- FALSE
        i <- which(above & dplyr::lead(above, default = FALSE))
        if (length(i)) iso_week[i[1]] else NA_character_
      },
      end_week = {
        above <- sentinella_ili_inc > threshold
        above[is.na(above)] <- FALSE
        i <- which(above)
        if (length(i)) iso_week[max(i)] else NA_character_
      },
      .groups = "drop"
    )
}
