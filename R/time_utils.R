# =============================================================================
# R/time_utils.R -- ISO week and influenza season helpers
# =============================================================================
# Conventions used throughout the project
#   * Weeks are ISO 8601 weeks ("2024-W05"), weeks start on Monday.
#   * An influenza season runs from ISO week 40 to ISO week 39 of the next
#     year, labelled by its two calendar years, e.g. "2023/24".
#   * ISO years can have 53 weeks (2015, 2020, 2026 in the study period).
# =============================================================================

#' Parse an ISO week string ("2024-W05") into year and week integers
parse_iso_week <- function(x) {
  ok <- grepl("^\\d{4}-W\\d{2}$", x)
  if (!all(ok)) {
    stop("Invalid ISO week string(s): ", paste(head(x[!ok], 5), collapse = ", "))
  }
  list(
    year = as.integer(substr(x, 1, 4)),
    week = as.integer(substr(x, 7, 8))
  )
}

#' Monday of ISO week 1 of a given ISO year
#' (ISO week 1 is the week that contains 4 January)
iso_week1_monday <- function(year) {
  jan4 <- as.Date(sprintf("%d-01-04", year))
  dow  <- as.integer(format(jan4, "%u"))       # 1 = Monday ... 7 = Sunday
  jan4 - (dow - 1L)
}

#' Monday (start date) of an ISO week
iso_week_to_date <- function(x) {
  p <- parse_iso_week(x)
  d <- iso_week1_monday(p$year) + 7L * (p$week - 1L)
  # guard against impossible weeks such as 2019-W53
  back <- date_to_iso_week(d)
  if (any(back != x)) {
    stop("Non-existent ISO week(s): ", paste(head(x[back != x], 5), collapse = ", "))
  }
  d
}

#' ISO week string of a date
date_to_iso_week <- function(date) {
  format(as.Date(date), "%G-W%V")
}

#' Number of ISO weeks in an ISO year (52 or 53)
iso_weeks_in_year <- function(year) {
  # 28 December is always in the last ISO week of its ISO year
  as.integer(format(as.Date(sprintf("%d-12-28", year)), "%V"))
}

#' Complete sequence of ISO weeks between two ISO week strings (inclusive)
iso_week_seq <- function(from, to) {
  d <- seq(iso_week_to_date(from), iso_week_to_date(to), by = "week")
  date_to_iso_week(d)
}

#' First calendar year of the influenza season an ISO week belongs to
season_start_year <- function(x, start_week = 40L) {
  p <- parse_iso_week(x)
  ifelse(p$week >= start_week, p$year, p$year - 1L)
}

#' Season label ("2023/24") for an ISO week
iso_week_to_season <- function(x, start_week = 40L) {
  y <- season_start_year(x, start_week)
  sprintf("%d/%02d", y, (y + 1L) %% 100L)
}

#' Running week number within the season (W40 = 1)
season_week <- function(x, start_week = 40L) {
  y     <- season_start_year(x, start_week)
  first <- iso_week1_monday(y) + 7L * (start_week - 1L)
  as.integer((iso_week_to_date(x) - first) / 7) + 1L
}

#' First calendar year of a season label ("2023/24" -> 2023)
season_label_start <- function(season) {
  as.integer(substr(season, 1, 4))
}
