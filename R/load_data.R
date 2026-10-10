# =============================================================================
# R/load_data.R -- read the raw FOPH/BAG and BFS files with explicit types
# =============================================================================
# Raw file structure (verified on the 2026-W40 vintage)
# -----------------------------------------------------
# Both FOPH/BAG exports are NOT a full cross-table week x region x age x sex.
# They are a stack of *marginal* tables: each row breaks down at most ONE
# dimension and sets the others to "all", plus national totals. Summing over
# all rows would therefore count each case several times. National values
# must be taken from the national total row (see R/prepare.R).
#
# INFLUENZA_oblig    valueCategory: cases | min/median/max_value_10y
#                    temporal_type: iso_week | month | year
#                    georegion:     26 cantons + "unknown" (type canton),
#                                   CH, FL (type country), CHFL
#                    breakdowns at CHFL level: agegroup, sex, type (A/B)
# INFLUENZA_sentinella valueCategory: consultations
#                    temporal_type: week | month | year
#                    georegion:     CH (country), region_1..6 + unknown
#                    breakdowns at CH level: agegroup, sex
# =============================================================================

OBLIG_COLTYPES <- readr::cols(
  valueCategory      = readr::col_character(),
  temporal           = readr::col_character(),
  temporal_type      = readr::col_character(),
  georegion          = readr::col_character(),
  georegion_type     = readr::col_character(),
  agegroup           = readr::col_character(),
  agegroup_type      = readr::col_character(),
  sex                = readr::col_character(),
  type               = readr::col_character(),
  value              = readr::col_double(),
  pop                = readr::col_double(),
  incValue           = readr::col_double(),
  prct               = readr::col_double(),
  inc14d             = readr::col_double(),
  trend              = readr::col_character(),
  deltaValue         = readr::col_double(),
  deltaIncValue      = readr::col_double(),
  incValuePrctChange = readr::col_double(),
  valueMean5y        = readr::col_double(),
  dataComplete       = readr::col_logical()
)

SENTINELLA_COLTYPES <- readr::cols(
  valueCategory                   = readr::col_character(),
  temporal                        = readr::col_character(),
  temporal_type                   = readr::col_character(),
  georegion                       = readr::col_character(),
  georegion_type                  = readr::col_character(),
  agegroup                        = readr::col_character(),
  agegroup_type                   = readr::col_character(),
  sex                             = readr::col_character(),
  value                           = readr::col_double(),
  popExtrapolation                = readr::col_double(),
  totalConsultationsExtrapolation = readr::col_double(),
  incValue                        = readr::col_double(),
  prctConsultations               = readr::col_double(),
  trend                           = readr::col_character(),
  prct                            = readr::col_double(),
  deltaValue                      = readr::col_double(),
  deltaIncValue                   = readr::col_double(),
  incValuePrctChange              = readr::col_double(),
  valueMean5y                     = readr::col_double(),
  dataComplete                    = readr::col_logical()
)

#' Read a raw export; fails loudly if columns differ from the expected schema
read_bag_export <- function(path, coltypes) {
  if (!file.exists(path)) {
    stop("File not found: ", path,
         "\nDownload it first (scripts/00_download_data.R) or copy it to data/raw/.")
  }
  header   <- names(readr::read_csv(path, n_max = 0, show_col_types = FALSE))
  expected <- names(coltypes$cols)
  missing  <- setdiff(expected, header)
  extra    <- setdiff(header, expected)
  if (length(missing) > 0) {
    stop("Schema change in ", basename(path), " -- missing column(s): ",
         paste(missing, collapse = ", "))
  }
  if (length(extra) > 0) {
    warning("New column(s) in ", basename(path), " (ignored): ",
            paste(extra, collapse = ", "))
  }
  readr::read_csv(path, col_types = coltypes, na = c("", "NA"))
}

load_oblig      <- function(path = FILE_OBLIG)      read_bag_export(path, OBLIG_COLTYPES)
load_sentinella <- function(path = FILE_SENTINELLA) read_bag_export(path, SENTINELLA_COLTYPES)

#' Permanent resident population of Switzerland at 31 December (BFS STATPOP)
load_population <- function(path = FILE_POPULATION) {
  readr::read_csv(path, comment = "#",
                  col_types = readr::cols(year = readr::col_integer(),
                                          population = readr::col_double(),
                                          .default = readr::col_character()))
}

#' Reproduce the data vintage of the Preliminary Study
#'
#' Removes all weekly rows after STUDY_END_ISOWEEK (monthly and yearly rows are
#' kept, as in the original download). Applied directly after loading, so that
#' every later step works on exactly the observations described in Section 3.
restrict_to_study_vintage <- function(df, end = STUDY_END_ISOWEEK) {
  is_week <- grepl("^\\d{4}-W\\d{2}$", df$temporal)
  df[!(is_week & df$temporal > end), ]
}
