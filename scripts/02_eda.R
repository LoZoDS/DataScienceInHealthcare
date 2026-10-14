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
# (next step)

# 5. Unusual observations
# (next step)

# 6. Regional variation (descriptive only)
# (next step)

message("Done. Tables in ", PATH_EDA)
