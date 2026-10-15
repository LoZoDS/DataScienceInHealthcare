# scripts/02_eda.R: Exploratory analysis

# Input:
#data/processed/flu_weekly_national.csv (from 01_data_preparation.R)
#data/processed/flu_weekly_strata_long.csv
#data/reference/epidemic_thresholds.csv (published FOPH/BAG thresholds)

# Output: output/eda/*.csv

# Run: Rscript scripts/02_eda.R

"Preliminary Study, Section 4.2: seasonal patterns, between-season differences,
unusual observations; per season peak week, peak intensity and season onset/end
(applied to both systems); regional variation described only"

source("R/setup.R")
PATH_EDA <- file.path("output", "eda")
dir.create(PATH_EDA, showWarnings = FALSE, recursive = TRUE)

# ---- 1. Load and check inputs ------------------------------------------------------
national   <- load_national()
strata     <- load_strata()
thresholds <- readr::read_csv(file.path(PATH_REFERENCE, "epidemic_thresholds.csv"),
                              comment = "#", show_col_types = FALSE)
check_eda_inputs(national, strata)

if (!requireNamespace("mem", quietly = TRUE)) {
  warning("Package 'mem' not installed (needed for step 4). Run source(\"install_packages.R\").")
}

message(sprintf("national: %d weeks (%s to %s), %d seasons; strata: %s rows",
                nrow(national), min(national$iso_week), max(national$iso_week),
                dplyr::n_distinct(national$season),
                format(nrow(strata), big.mark = ",")))
message("Seasons in summary statistics: ",
        paste(unique(national$season[national$in_summary]), collapse = ", "))
message(sprintf("Sentinella missing: %s",
                paste(national$iso_week[national$sentinella_missing], collapse = ", ")))

# 2. Seasonal patterns
# Descriptive statistics per period and the typical season (median per season week)
periods <- period_summary(national)
typical <- typical_season(national)
readr::write_csv(periods, file.path(PATH_EDA, "period_summary.csv"))
readr::write_csv(typical, file.path(PATH_EDA, "typical_season.csv"))

# 3. Peak timing and intensity
# Peak week and peak intensity per season and system, plus summary by period
peaks    <- peaks_per_season(national)
peak_sum <- peak_summary(peaks)
readr::write_csv(peaks,    file.path(PATH_EDA, "peaks_per_season.csv"))
readr::write_csv(peak_sum, file.path(PATH_EDA, "peak_summary.csv"))
message(sprintf("Peaks: %d seasons; Sentinella peak earlier than oblig in %d, same week in %d, later in %d",
                nrow(peaks), sum(peaks$peak_lag_weeks > 0), sum(peaks$peak_lag_weeks == 0),
                sum(peaks$peak_lag_weeks < 0)))

# 4. Season onset and end (MEM)
# Threshold per season from earlier seasons only (Moving Epidemic Method), then the onset/end rule of Section 4.2; the Sentinella window is applied to oblig.
bag_thresholds <- thresholds
reported <- readr::read_csv(file.path(PATH_REFERENCE, "bag_reported_values.csv"),
                            comment = "#", show_col_types = FALSE)
mem_th     <- mem_thresholds(national)
validation <- mem_validation(national, mem_th, bag_thresholds, reported)
boundaries <- boundaries_both_systems(national, mem_th, peaks)
in_season  <- in_season_weeks(national, boundaries)
readr::write_csv(mem_th,     file.path(PATH_EDA, "mem_thresholds.csv"))
readr::write_csv(validation, file.path(PATH_EDA, "mem_validation.csv"))
readr::write_csv(boundaries, file.path(PATH_EDA, "season_boundaries.csv"))
readr::write_csv(in_season,  file.path(PATH_EDA, "in_season_weeks.csv"))   # for WP 4.5
message(sprintf("MEM: thresholds for %d seasons; retrospective pre-2020 threshold %.1f per 100,000",
                sum(!is.na(mem_th$threshold_ili_per_100k)), validation$mem_retro_threshold[1]))

# 5. Unusual observations
# Evidence for the unusual observations described in the report:
# influenza type per season, off-season baseline, consultation volume around holidays
types         <- type_by_season(strata)
baseline      <- offseason_baseline(national)
consultations <- consultation_volume(national)
readr::write_csv(types,         file.path(PATH_EDA, "type_by_season.csv"))
readr::write_csv(baseline,      file.path(PATH_EDA, "offseason_baseline.csv"))
readr::write_csv(consultations, file.path(PATH_EDA, "consultation_volume.csv"))

# 6. Regional variation (descriptive only)
# Peak week and intensity per Sentinella region; regions are only described
# (Section 4.2: smaller numbers, noisier series, national forecasting target)
reg_peaks <- region_peaks(strata, national)
reg_sum   <- region_summary(reg_peaks)
readr::write_csv(reg_peaks, file.path(PATH_EDA, "region_peaks.csv"))
readr::write_csv(reg_sum,   file.path(PATH_EDA, "region_summary.csv"))

message("Done. Tables in ", PATH_EDA)
