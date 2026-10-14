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
# (next step)

# 3. Peak timing and intensity
# (next step)

# 4. Season onset and end (MEM)
# (next step)

# 5. Unusual observations
# (next step)

# 6. Regional variation (descriptive only)
# (next step)

message("Done. Tables in ", PATH_EDA)
