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
# ---- Seasonal patterns (Section 4.2) --------------------------------------------

#' National series in long format: one row per week and system
#' value = oblig_inc_100k (lab-confirmed cases per 100,000) or
#'         sentinella_ili_rate (ILI consultations per 1,000 consultations)
national_long <- function(national) {
  national |>
    dplyr::select(iso_week, week_start, season, season_week, period, in_summary,
                  lockdown_2020, oblig = oblig_inc_100k, sentinella = sentinella_ili_rate) |>
    tidyr::pivot_longer(c(oblig, sentinella), names_to = "system", values_to = "value") |>
    dplyr::mutate(system = factor(system, levels = c("oblig", "sentinella"),
                                  labels = SYSTEM_LABELS))
}

#' Descriptive statistics per period and system (weekly values)
period_summary <- function(national) {
  national_long(national) |>
    dplyr::filter(!is.na(value)) |>
    dplyr::group_by(system, period) |>
    dplyr::summarise(
      seasons     = dplyr::n_distinct(season),
      weeks       = dplyr::n(),
      mean        = mean(value),
      median      = stats::median(value),
      p90         = stats::quantile(value, 0.9, names = FALSE),
      max         = max(value),
      pct_zero    = 100 * mean(value == 0),
      .groups = "drop")
}

#' Typical season: median value per season week, pre-2020 vs post-2020.
#' Only seasons that enter summary statistics; COVID seasons left out by design.
typical_season <- function(national) {
  national_long(national) |>
    dplyr::filter(in_summary, period %in% c("pre2020", "post2020"),
                  !lockdown_2020, !is.na(value)) |>
    dplyr::group_by(system, period, season_week) |>
    dplyr::summarise(median = stats::median(value),
                     q25 = stats::quantile(value, 0.25, names = FALSE),
                     q75 = stats::quantile(value, 0.75, names = FALSE),
                     n_seasons = dplyr::n(), .groups = "drop")
}

# Peak timing and intensity (Section 4.2)

# Peak week (week of maximum incidence) and peak intensity (maximum weekly incidence) per season, separately for both systems.
# *_peak_sw       peak week as week within season (W40 = 1)
# peak_lag_weeks  oblig peak week minus Sentinella peak week (> 0: Sentinella peaks earlier)
# Ties: the first week with the maximum value is used.
peaks_per_season <- function(national) {
  peak_of <- function(df, col) {
    df |>
      dplyr::filter(!is.na(.data[[col]])) |>
      dplyr::group_by(season) |>
      dplyr::slice_max(.data[[col]], n = 1, with_ties = FALSE) |>
      dplyr::ungroup() |>
      dplyr::select(season, peak_week = iso_week, peak_sw = season_week, peak_value = dplyr::all_of(col))
  }
  seasons <- national |>
    dplyr::group_by(season) |>
    dplyr::summarise(period = dplyr::first(period),
                     in_summary = dplyr::first(in_summary),
                     complete_season = dplyr::first(complete_season),
                     test_season = dplyr::first(test_season),
                     oblig_cases = sum(oblig_cases), .groups = "drop")
  o <- peak_of(national, "oblig_inc_100k") |>
    dplyr::rename_with(~ paste0("oblig_", .x), -season)
  s <- peak_of(national, "sentinella_ili_rate") |>
    dplyr::rename_with(~ paste0("sent_", .x), -season)
  seasons |>
    dplyr::left_join(o, by = "season") |>
    dplyr::left_join(s, by = "season") |>
    dplyr::mutate(peak_lag_weeks = oblig_peak_sw - sent_peak_sw)
}

# Summary of peak timing and intensity across seasons, by period.
# Only seasons with in_summary = TRUE; COVID seasons shown separately.
peak_summary <- function(peaks) {
  peaks |>
    dplyr::filter(in_summary) |>
    dplyr::group_by(period) |>
    dplyr::summarise(
      seasons            = dplyr::n(),
      oblig_peak_sw_mean = mean(oblig_peak_sw),
      oblig_peak_sw_sd   = stats::sd(oblig_peak_sw),
      oblig_peak_sw_min  = min(oblig_peak_sw),
      oblig_peak_sw_max  = max(oblig_peak_sw),
      sent_peak_sw_mean  = mean(sent_peak_sw),
      sent_peak_sw_sd    = stats::sd(sent_peak_sw),
      oblig_peak_median  = stats::median(oblig_peak_value),
      sent_peak_median   = stats::median(sent_peak_value),
      lag_mean           = mean(peak_lag_weeks),
      lag_min            = min(peak_lag_weeks),
      lag_max            = max(peak_lag_weeks),
      .groups = "drop")
}

# Convert a week within season (W40 = 1) to an approximate ISO week label for axis labels (W40 ... W52, W01 ...; ignores 53-week years)
season_week_label <- function(sw) {
  wk <- (sw + SEASON_START_WEEK - 2) %% 52 + 1
  sprintf("W%02d", wk)
}

# Season onset and end with the Moving Epidemic Method MEM

# MEM input: one column per season, one row per week within season (1-52),
# Sentinella ILI consultations per 100,000 inhabitants (scale of the FOPH/BAG threshold).
# Lockdown weeks 2020 are set to NA. Week 53 of 53-week seasons (an off-season week in September) is left out, as MEM needs equal lengths.
mem_input <- function(national) {
  national |>
    dplyr::filter(season_week <= 52) |>
    dplyr::mutate(value = ifelse(lockdown_2020, NA_real_, sentinella_ili_inc)) |>
    dplyr::select(season, season_week, value) |>
    tidyr::pivot_wider(names_from = season, values_from = value) |>
    dplyr::arrange(season_week)
}

# Seasons that can serve as MEM training data: complete seasons with influenza circulation, excluding the COVID-19 seasons
mem_training_seasons <- function(national) {
  national |>
    dplyr::distinct(season, complete_season, covid_season, in_summary) |>
    dplyr::filter(complete_season, !covid_season, in_summary) |>
    dplyr::pull(season) |>
    sort()
}

# Prospective MEM threshold for every season: estimated only from earlier seasons (no leakage), at most MEM_MAX_SEASONS, at least MEM_MIN_SEASONS.
# Returns one row per season with the pre-epidemic threshold (used for onset and end),
# the post-epidemic threshold and the intensity thresholds (medium / high / very high), all per 100,000 inhabitants.
mem_thresholds <- function(national, min_seasons = MEM_MIN_SEASONS,
                           max_seasons = MEM_MAX_SEASONS) {
  wide     <- mem_input(national)
  training <- mem_training_seasons(national)
  targets  <- setdiff(sort(unique(national$season)), EDA_INCOMPLETE_SEASONS)
  rows <- lapply(targets, function(s) {
    train <- utils::tail(training[training < s], max_seasons)
    out <- tibble::tibble(season = s, n_train = length(train),
                          train_seasons = paste(train, collapse = ", "),
                          threshold_ili_per_100k = NA_real_, post_threshold = NA_real_,
                          intensity_medium = NA_real_, intensity_high = NA_real_,
                          intensity_very_high = NA_real_)
    if (length(train) < min_seasons) return(out)
    m <- mem::memmodel(as.data.frame(wide[, train]))
    out$threshold_ili_per_100k <- m$epidemic.thresholds[1]
    out$post_threshold         <- m$epidemic.thresholds[2]
    out[c("intensity_medium", "intensity_high", "intensity_very_high")] <-
      as.list(m$intensity.thresholds)
    out
  })
  dplyr::bind_rows(rows)
}

# Retrospective MEM threshold from all pre-2020 seasons, used only to validate MEM against the thresholds published by FOPH/BAG (not for the analysis)
mem_threshold_pre2020 <- function(national) {
  train <- intersect(mem_training_seasons(national), PRE_2020_SEASONS)
  m <- mem::memmodel(as.data.frame(mem_input(national)[, train]))
  m$epidemic.thresholds[1]
}

# Season boundaries (rule of Section 4.2, function season_boundaries() from WP 4.1) with duration and the Sentinella window applied to mandatory reporting:
#   duration_weeks       onset to end, inclusive
#   oblig_share_in_window share of the season's oblig cases inside the window
#   oblig_peak_in_window  oblig peak lies inside the window
boundaries_both_systems <- function(national, thresholds, peaks) {
  b <- season_boundaries(national, thresholds) |>
    dplyr::mutate(duration_weeks = ifelse(
      is.na(onset_week), NA_integer_,
      match(end_week, national$iso_week) - match(onset_week, national$iso_week) + 1L))
  window <- national |>
    dplyr::left_join(dplyr::select(b, season, onset_week, end_week), by = "season") |>
    dplyr::mutate(in_window = !is.na(onset_week) & iso_week >= onset_week & iso_week <= end_week) |>
    dplyr::group_by(season) |>
    dplyr::summarise(oblig_share_in_window = ifelse(all(is.na(onset_week)), NA_real_,
                                                    sum(oblig_cases[in_window]) / sum(oblig_cases)),
                     .groups = "drop")
  b |>
    dplyr::left_join(window, by = "season") |>
    dplyr::left_join(dplyr::select(peaks, season, oblig_peak_week, sent_peak_week), by = "season") |>
    dplyr::mutate(oblig_peak_in_window = oblig_peak_week >= onset_week & oblig_peak_week <= end_week)
}

# Weekly flag: in_season = week lies between MEM onset and end
in_season_weeks <- function(national, boundaries) {
  national |>
    dplyr::select(iso_week, season, test_season) |>
    dplyr::left_join(dplyr::select(boundaries, season, onset_week, end_week), by = "season") |>
    dplyr::mutate(in_season = !is.na(onset_week) & iso_week >= onset_week & iso_week <= end_week) |>
    dplyr::select(iso_week, season, test_season, in_season)
}

# Validation of MEM against FOPH/BAG (pre-2020 seasons): thresholds and the resulting onset weeks
# with (a) the published FOPH/BAG threshold, (b) the prospective MEM threshold and
# (c) the retrospective MEM threshold from all pre-2020 seasons, next to the onset week reported by FOPH/BAG.
mem_validation <- function(national, mem_th, bag_th, reported) {
  retro <- mem_threshold_pre2020(national)
  retro_th <- tibble::tibble(season = PRE_2020_SEASONS, threshold_ili_per_100k = retro)
  onset <- function(th, name) {
    season_boundaries(national, th) |>
      dplyr::select(season, !!name := onset_week)
  }
  tibble::tibble(season = PRE_2020_SEASONS) |>
    dplyr::left_join(dplyr::select(bag_th, season, bag_threshold = threshold_ili_per_100k), by = "season") |>
    dplyr::left_join(dplyr::select(mem_th, season, mem_threshold = threshold_ili_per_100k), by = "season") |>
    dplyr::mutate(mem_retro_threshold = retro) |>
    dplyr::left_join(reported |> dplyr::filter(reported_onset %in% TRUE) |>
                       dplyr::transmute(season = iso_week_to_season(iso_week, SEASON_START_WEEK),
                                        onset_reported = iso_week), by = "season") |>
    dplyr::left_join(onset(bag_th, "onset_bag"), by = "season") |>
    dplyr::left_join(onset(mem_th, "onset_mem"), by = "season") |>
    dplyr::left_join(onset(retro_th, "onset_mem_retro"), by = "season")
}
