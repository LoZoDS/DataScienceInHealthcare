# =============================================================================
# config.R -- central settings for the whole project
# -----------------------------------------------------------------------------
# Every script sources this file. Change paths, study period or column names
# HERE, never inside the analysis scripts.
# =============================================================================

# ---- Paths ------------------------------------------------------------------
PATH_RAW        <- file.path("data", "raw")
PATH_REFERENCE  <- file.path("data", "reference")
PATH_PROCESSED  <- file.path("data", "processed")
PATH_QC         <- file.path("output", "qc")
PATH_FIGURES    <- file.path("output", "figures")

FILE_OBLIG       <- file.path(PATH_RAW, "INFLUENZA_oblig.csv")
FILE_SENTINELLA  <- file.path(PATH_RAW, "INFLUENZA_sentinella.csv")
FILE_POPULATION  <- file.path(PATH_REFERENCE, "population_ch_bfs.csv")
FILE_RAW_META    <- file.path(PATH_RAW, "DOWNLOAD_INFO.md")

# Download endpoints (FOPH/BAG infectious disease dashboard, linked on
# opendata.swiss). "latest" always returns the current vintage.
URL_OBLIG      <- "https://idd.bag.admin.ch/api/v1/export/latest/INFLUENZA_oblig/csv"
URL_SENTINELLA <- "https://idd.bag.admin.ch/api/v1/export/latest/INFLUENZA_sentinella/csv"

# ---- Study period and data vintage (Preliminary Study, Section 3) -----------
STUDY_START_ISOWEEK <- "2013-W01"
STUDY_END_ISOWEEK   <- "2026-W37"

# The Preliminary Study is based on the download of 24 September 2026
# (FOPH/BAG 2026a). Later downloads contain additional weeks; all weekly rows
# after STUDY_END_ISOWEEK are removed directly after loading, which reproduces
# exactly the number of observations reported in Section 3.
STUDY_DOWNLOAD_DATE <- "2026-09-24"
STUDY_N_OBLIG       <- 30938L   # INFLUENZA_oblig, 20 variables
STUDY_N_SENTINELLA  <- 12332L   # INFLUENZA_sentinella, 20 variables

# Influenza season runs from ISO week 40 to ISO week 39 of the following year
SEASON_START_WEEK <- 40L

# Seasons with almost no influenza circulation (COVID-19 measures), Section 4.1
COVID_SEASONS <- c("2020/21", "2021/22")

# Sensitivity analysis: level shift after the pandemic (testing behaviour).
# Post-2020 = seasons from 2022/23 onwards; pre-2020 = 2013/14 to 2019/20.
PRE_2020_SEASONS  <- sprintf("%d/%02d", 2013:2019, (14:20) %% 100)
POST_2020_FIRST_SEASON <- "2022/23"

# Test seasons for rolling-origin evaluation (Section 4.5) -- flagged only,
# the split itself is done by the forecasting work package.
TEST_SEASONS <- c("2023/24", "2024/25", "2025/26")

# ---- Population -------------------------------------------------------------
# Permanent resident population at 31 December of the respective year (BFS,
# STATPOP). Years without a value (e.g. 2026) use the latest available year.
POPULATION_FALLBACK_TO_LATEST <- TRUE

# EDA (4.2)
"Seasons left out of summary statistics across seasons (means, medians, SD of
peak week): 2012/13 (starts in W01, onset and early weeks missing) and the
season without influenza circulation. 2025/26 stays in: only the off-season
# weeks W38-W39 are missing. All seasons stay in tables and figures, flagged."
EDA_INCOMPLETE_SEASONS  <- c("2012/13")
EDA_NO_SEASON           <- c("2020/21")
# Weeks affected by the COVID-19 lockdown at the end of season 2019/20
# (feedback on WP 4.1): 2020-W11 to the end of the season; flagged, not removed.
EDA_LOCKDOWN_WEEKS_2020 <- sprintf("2020-W%02d", 11:39)   # until end of season 2019/20
# Colours used throughout the project (CONTRIBUTING.md)
COL_OBLIG <- "#2a78d6"   # mandatory reporting
COL_SENT  <- "#eb6834"   # Sentinella
# Display names of the two systems in tables and figures
SYSTEM_LABELS <- c("Mandatory reporting (cases per 100,000)",
                   "Sentinella (ILI per 1,000 consultations)")
