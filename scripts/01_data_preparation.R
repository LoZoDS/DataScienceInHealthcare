# =============================================================================
# scripts/01_data_preparation.R -- WP 4.1 Data preparation
# -----------------------------------------------------------------------------
# Input : data/raw/INFLUENZA_oblig.csv, data/raw/INFLUENZA_sentinella.csv,
#         data/reference/population_ch_bfs.csv
# Output: data/processed/flu_weekly_national.csv   (one row per ISO week)
#         data/processed/flu_weekly_strata_long.csv (breakdowns for 4.2)
#         output/qc/qc_checks.csv, output/qc/*.csv  (quality checks)
# Run   : Rscript scripts/01_data_preparation.R   (from the project root)
# =============================================================================
source("R/setup.R")
dir.create(PATH_PROCESSED, showWarnings = FALSE, recursive = TRUE)
dir.create(PATH_QC, showWarnings = FALSE, recursive = TRUE)

# ---- 1. Load and restrict to the data vintage of the Preliminary Study ------------
oblig_raw  <- load_oblig()
sent_raw   <- load_sentinella()
population <- load_population()
oblig <- restrict_to_study_vintage(oblig_raw)
sent  <- restrict_to_study_vintage(sent_raw)
message(sprintf("oblig: %d -> %d rows, sentinella: %d -> %d rows (study vintage up to %s)",
                nrow(oblig_raw), nrow(oblig), nrow(sent_raw), nrow(sent), STUDY_END_ISOWEEK))

# ---- 2. Structure overview (documented in the report) ----------------------------
structure_overview <- function(df, dataset) {
  type_col <- if ("type" %in% names(df)) df$type else rep("all", nrow(df))
  df |>
    dplyr::mutate(breakdown = dplyr::case_when(
      agegroup != "all" ~ "agegroup",
      sex != "all"      ~ "sex",
      type_col != "all" ~ "type",
      TRUE              ~ "none")) |>
    dplyr::count(valueCategory, temporal_type, georegion_type, breakdown, name = "rows") |>
    dplyr::mutate(dataset = dataset, .before = 1)
}
overview <- dplyr::bind_rows(structure_overview(oblig, "oblig"),
                             structure_overview(sent, "sentinella"))
readr::write_csv(overview, file.path(PATH_QC, "structure_overview.csv"))

missing_overview <- dplyr::bind_rows(
  tibble::tibble(dataset = "oblig", column = names(oblig),
                 n_missing = colSums(is.na(oblig)), n_rows = nrow(oblig)),
  tibble::tibble(dataset = "sentinella", column = names(sent),
                 n_missing = colSums(is.na(sent)), n_rows = nrow(sent))
) |> dplyr::mutate(pct_missing = round(100 * n_missing / n_rows, 1))
readr::write_csv(missing_overview, file.path(PATH_QC, "missing_values.csv"))

# ---- 3. Quality checks -------------------------------------------------------------
qc <- dplyr::bind_rows(
  qc_study_vintage(oblig, sent, nrow(oblig_raw), nrow(sent_raw)),
  qc_structure(oblig, "oblig",
               c("valueCategory", "temporal", "georegion", "agegroup", "sex", "type"), "iso_week"),
  qc_structure(sent, "sentinella",
               c("valueCategory", "temporal", "georegion", "agegroup", "sex"), "week"),
  qc_oblig_consistency(oblig, population),
  qc_sentinella_consistency(sent),
  qc_sentinella_fallback(sent)
)

# ---- 4. Build analysis datasets ------------------------------------------------------
national <- build_national_weekly(oblig, sent, population)
strata   <- build_strata_long(oblig, sent)

# checks on the final national dataset
inc_bag <- oblig |>
  dplyr::filter(valueCategory == "cases", temporal_type == "iso_week", georegion == "CH") |>
  dplyr::select(iso_week = temporal, inc_bag = incValue) |>
  dplyr::right_join(dplyr::select(national, iso_week, oblig_inc_100k), by = "iso_week")
max_diff <- max(abs(inc_bag$oblig_inc_100k - inc_bag$inc_bag))
n_fallback <- sum(national$sentinella_source == "regional_weighted_mean", na.rm = TRUE)
n_expected <- length(iso_week_seq(STUDY_START_ISOWEEK, STUDY_END_ISOWEEK))
qc <- dplyr::bind_rows(
  qc,
  qc_row("final_1", "national", "One row per ISO week in study period",
         nrow(national) == n_expected && !anyDuplicated(national$iso_week),
         sprintf("%d rows, %d expected (%s to %s)", nrow(national), n_expected,
                 STUDY_START_ISOWEEK, STUDY_END_ISOWEEK)),
  qc_row("final_2", "national", "Target (oblig incidence) complete",
         !any(national$oblig_missing), sprintf("%d missing weeks", sum(national$oblig_missing))),
  qc_row("final_3", "national", "Own incidence (cantons summed / BFS) = FOPH/BAG incidence",
         max_diff <= 0.0051, sprintf("max abs diff %.4f (FOPH/BAG rounds to 2 decimals)", max_diff)),
  qc_row("final_4", "national", "Sentinella ILI rate complete in study period",
         !any(national$sentinella_missing),
         sprintf("missing (national and all regions): %s; filled by regional weighted mean: %d weeks",
                 paste(national$iso_week[national$sentinella_missing], collapse = " "), n_fallback),
         warn_only = TRUE),
  qc_row("final_5", "national", "Leakage-prone BAG columns excluded",
         !any(LEAKAGE_COLUMNS %in% names(national)),
         paste(LEAKAGE_COLUMNS, collapse = ", "))
)
readr::write_csv(qc, file.path(PATH_QC, "qc_checks.csv"))
print(qc, n = Inf)
assert_qc(qc)

# season summary (descriptive input for 4.2; onset/end needs thresholds)
thresholds <- readr::read_csv(file.path(PATH_REFERENCE, "epidemic_thresholds.csv"),
                              comment = "#", show_col_types = FALSE)
season_summary <- national |>
  dplyr::group_by(season, period, complete_season, test_season) |>
  dplyr::summarise(
    n_weeks          = dplyr::n(),
    oblig_cases      = sum(oblig_cases),
    oblig_peak_week  = iso_week[which.max(oblig_inc_100k)],
    oblig_peak_inc   = round(max(oblig_inc_100k), 2),
    ili_peak_week    = iso_week[which.max(sentinella_ili_rate)],
    ili_peak_rate    = round(max(sentinella_ili_rate, na.rm = TRUE), 2),
    .groups = "drop") |>
  dplyr::left_join(season_boundaries(national, thresholds), by = "season")
readr::write_csv(season_summary, file.path(PATH_QC, "season_summary.csv"))

# ---- 5. Write ----------------------------------------------------------------------
national_out <- national |>
  dplyr::mutate(oblig_inc_100k = round(oblig_inc_100k, 4),
                sentinella_ili_rate = round(sentinella_ili_rate, 2))
readr::write_csv(national_out, file.path(PATH_PROCESSED, "flu_weekly_national.csv"))
readr::write_csv(strata, file.path(PATH_PROCESSED, "flu_weekly_strata_long.csv"))
message(sprintf("Wrote %d weekly rows (%s to %s) and %d stratified rows.",
                nrow(national), STUDY_START_ISOWEEK, STUDY_END_ISOWEEK, nrow(strata)))
