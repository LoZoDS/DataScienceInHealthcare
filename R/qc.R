# =============================================================================
# R/qc.R -- data quality checks (Section 4.1)
# =============================================================================
# Every check returns one row: check id, dataset, description, result (PASS /
# WARN / FAIL) and a short detail string. The full table is written to
# output/qc/qc_checks.csv and shown in the data preparation report.
# FAIL stops the pipeline; WARN is documented but does not stop it.
# =============================================================================

qc_row <- function(id, dataset, description, pass, detail = "", warn_only = FALSE) {
  tibble::tibble(
    id = id, dataset = dataset, description = description,
    result = if (isTRUE(pass)) "PASS" else if (warn_only) "WARN" else "FAIL",
    detail = as.character(detail)
  )
}

# ---- Structural checks --------------------------------------------------------

qc_structure <- function(df, dataset, key_cols, week_type) {
  wk  <- dplyr::filter(df, temporal_type == week_type)
  dup <- sum(duplicated(df[key_cols]))
  weeks <- sort(unique(wk$temporal))
  expected <- iso_week_seq(weeks[1], weeks[length(weeks)])
  missing_weeks <- setdiff(expected, weeks)
  dplyr::bind_rows(
    qc_row(paste0(dataset, "_S1"), dataset, "No duplicated keys",
           dup == 0, sprintf("%d duplicated rows on (%s)", dup, paste(key_cols, collapse = ", "))),
    qc_row(paste0(dataset, "_S2"), dataset, "Weekly series has no missing ISO weeks",
           length(missing_weeks) == 0,
           sprintf("%s to %s, %d weeks, missing: %s", weeks[1], weeks[length(weeks)],
                   length(weeks), if (length(missing_weeks)) paste(missing_weeks, collapse = " ") else "none")),
    qc_row(paste0(dataset, "_S3"), dataset, "All rows flagged dataComplete = TRUE",
           all(df$dataComplete), sprintf("%d rows not complete", sum(!df$dataComplete)), warn_only = TRUE)
  )
}

# ---- Mandatory reporting: additivity of the marginal tables -------------------

qc_oblig_consistency <- function(oblig, pop_ref) {
  w <- dplyr::filter(oblig, valueCategory == "cases", temporal_type == "iso_week")
  pick <- function(d, name) dplyr::select(d, temporal, !!name := value)
  total <- w |> dplyr::filter(georegion == "CHFL", agegroup == "all", sex == "all", type == "all") |> pick("chfl")
  ch    <- w |> dplyr::filter(georegion == "CH") |> pick("ch")
  fl    <- w |> dplyr::filter(georegion == "FL") |> pick("fl")
  sums  <- function(filter_expr, name) {
    w |> dplyr::filter({{ filter_expr }}) |>
      dplyr::group_by(temporal) |> dplyr::summarise(!!name := sum(value), .groups = "drop")
  }
  cant <- sums(georegion_type == "canton", "cantons")
  age  <- sums(georegion == "CHFL" & agegroup != "all", "age")
  sex  <- sums(georegion == "CHFL" & sex != "all", "sex")
  typ  <- sums(georegion == "CHFL" & type != "all", "type")
  chk <- Reduce(function(a, b) dplyr::left_join(a, b, by = "temporal"),
                list(total, ch, fl, cant, age, sex, typ))

  # population: BAG `pop` vs BFS reference
  pop_bag <- w |> dplyr::filter(georegion == "CH") |>
    dplyr::mutate(year = as.integer(substr(temporal, 1, 4))) |>
    dplyr::distinct(year, pop)
  pop_cmp <- dplyr::inner_join(pop_bag, pop_ref, by = "year")

  n <- nrow(chk)
  frac <- function(x) sprintf("%d / %d weeks equal", sum(x, na.rm = TRUE), n)
  dplyr::bind_rows(
    qc_row("oblig_C1", "oblig", "CH + FL = CHFL national total", all(chk$ch + chk$fl == chk$chfl), frac(chk$ch + chk$fl == chk$chfl)),
    qc_row("oblig_C2", "oblig", "Sum of cantons (incl. 'unknown') = CH", all(chk$cantons == chk$ch), frac(chk$cantons == chk$ch)),
    qc_row("oblig_C3", "oblig", "Sum of age groups (incl. 'unknown') = CHFL", all(chk$age == chk$chfl), frac(chk$age == chk$chfl)),
    qc_row("oblig_C4", "oblig", "Sum of sexes (incl. 'unknown') = CHFL", all(chk$sex == chk$chfl), frac(chk$sex == chk$chfl)),
    qc_row("oblig_C5", "oblig", "Sum of types A + B + unknown = CHFL", all(chk$type == chk$chfl), frac(chk$type == chk$chfl)),
    qc_row("oblig_C6", "oblig", "BAG `pop` column equals BFS reference population",
           nrow(pop_cmp) > 0 && all(pop_cmp$pop == pop_cmp$population),
           sprintf("%d of %d years identical", sum(pop_cmp$pop == pop_cmp$population), nrow(pop_cmp))),
    qc_row("oblig_C7", "oblig", "No negative case counts", all(w$value >= 0),
           sprintf("%d negative values", sum(w$value < 0)))
  )
}

# ---- Sentinella ----------------------------------------------------------------

qc_sentinella_consistency <- function(sent) {
  ch <- dplyr::filter(sent, temporal_type == "week", georegion == "CH",
                      agegroup == "all", sex == "all")
  reg <- sent |>
    dplyr::filter(temporal_type == "week", georegion_type == "sentinella_region") |>
    dplyr::group_by(temporal) |>
    dplyr::summarise(regions = sum(value, na.rm = TRUE), .groups = "drop")
  cmp <- dplyr::inner_join(dplyr::select(ch, temporal, value), reg, by = "temporal") |>
    dplyr::filter(!is.na(value), value > 0)
  rel_diff <- stats::median(abs(cmp$regions - cmp$value) / cmp$value)

  # incValue = extrapolated ILI consultations per 100,000 inhabitants?
  pop_implied <- ch$value / ch$incValue * 1e5
  na_weeks <- ch$temporal[is.na(ch$incValue)]
  dplyr::bind_rows(
    qc_row("sent_C1", "sentinella", "National ILI rate (CH) available for every week",
           length(na_weeks) == 0,
           sprintf("missing weeks: %s", if (length(na_weeks)) paste(na_weeks, collapse = " ") else "none"),
           warn_only = TRUE),
    qc_row("sent_C2", "sentinella",
           "Info: regional values are extrapolated separately (not additive) -> national row used",
           TRUE,
           sprintf("median |sum(regions) - CH| / CH = %.1f%%", 100 * rel_diff), warn_only = TRUE),
    qc_row("sent_C3", "sentinella", "incValue = value / population x 100,000 (plausible population 7.5-9.5 Mio.)",
           all(dplyr::between(pop_implied, 7.5e6, 9.5e6), na.rm = TRUE),
           sprintf("implied population %.2f to %.2f Mio.", min(pop_implied, na.rm = TRUE) / 1e6,
                   max(pop_implied, na.rm = TRUE) / 1e6)),
    qc_row("sent_C4", "sentinella", "No negative ILI values",
           all(ch$value >= 0, na.rm = TRUE), "")
  )
}

# ---- Data vintage --------------------------------------------------------------

qc_study_vintage <- function(oblig, sent, n_raw_oblig, n_raw_sent) {
  dplyr::bind_rows(
    qc_row("vintage_1", "oblig", "Observations = Preliminary Study (Section 3)",
           nrow(oblig) == STUDY_N_OBLIG && ncol(oblig) == 20,
           sprintf("%s x %d after restriction to <= %s (raw file: %s rows); study: %s x 20",
                   format(nrow(oblig), big.mark = ","), ncol(oblig), STUDY_END_ISOWEEK,
                   format(n_raw_oblig, big.mark = ","), format(STUDY_N_OBLIG, big.mark = ","))),
    qc_row("vintage_2", "sentinella", "Observations = Preliminary Study (Section 3)",
           nrow(sent) == STUDY_N_SENTINELLA && ncol(sent) == 20,
           sprintf("%s x %d after restriction to <= %s (raw file: %s rows); study: %s x 20",
                   format(nrow(sent), big.mark = ","), ncol(sent), STUDY_END_ISOWEEK,
                   format(n_raw_sent, big.mark = ","), format(STUDY_N_SENTINELLA, big.mark = ",")))
  )
}

#' Fallback for the national Sentinella rate (weighted mean of regions) must
#' reproduce the national values where both exist
qc_sentinella_fallback <- function(sent) {
  nat <- sent |>
    dplyr::filter(temporal_type == "week", georegion == "CH", agegroup == "all", sex == "all") |>
    dplyr::transmute(iso_week = temporal, rate = prctConsultations * 10, inc = incValue)
  cmp <- dplyr::inner_join(nat, regional_weighted_mean(sent), by = "iso_week") |>
    stats::na.omit()
  d     <- abs(cmp$rate - cmp$rate_reg)
  r     <- stats::cor(cmp$rate, cmp$rate_reg)
  qc_row("sent_C5", "sentinella",
         "Weighted mean of regions reproduces national ILI rate (validates fallback)",
         stats::median(d) < 0.05 && r > 0.999,
         sprintf("%d weeks; abs diff per 1,000 consultations: median %.3f, max %.2f; r = %.4f",
                 nrow(cmp), stats::median(d), max(d), r))
}

# ---- Geographic and demographic levels (Section 4.1) ---------------------------

#' Overview of all levels per stratification: cases / ILI consultations and
#' share within the stratification, study period
levels_overview <- function(strata) {
  strata |>
    dplyr::group_by(system, dimension, level) |>
    dplyr::summarise(total = sum(count, na.rm = TRUE),
                     weeks_with_value = sum(!is.na(count)),
                     .groups = "drop_last") |>
    dplyr::mutate(pct_of_total = round(100 * total / sum(total), 2)) |>
    dplyr::ungroup()
}

#' Share of cases with unknown canton / age group / sex / type must be small
qc_levels <- function(levels, max_unknown_pct = 1) {
  unk <- dplyr::filter(levels, level == "unknown")
  ob  <- dplyr::filter(unk, system == "oblig")
  se  <- dplyr::filter(unk, system == "sentinella")
  n_levels <- levels |> dplyr::count(system, dimension)
  dplyr::bind_rows(
    qc_row("levels_1", "oblig",
           sprintf("Share 'unknown' < %g%% in every stratification", max_unknown_pct),
           all(ob$pct_of_total < max_unknown_pct),
           paste(sprintf("%s %.2f%%", ob$dimension, ob$pct_of_total), collapse = ", ")),
    qc_row("levels_2", "sentinella", "Info: 'unknown' strata contain no values",
           TRUE, paste(sprintf("%s: %d weeks with value", se$dimension, se$weeks_with_value),
                       collapse = ", ")),
    qc_row("levels_3", "both", "Expected number of levels per stratification",
           all(n_levels$n[n_levels$dimension == "canton"] == 27,
               n_levels$n[n_levels$dimension == "agegroup"] == 6,
               n_levels$n[n_levels$dimension == "sex"] == 3,
               n_levels$n[n_levels$dimension == "sentinella_region"] == 7),
           paste(sprintf("%s/%s: %d", n_levels$system, n_levels$dimension, n_levels$n),
                 collapse = ", "))
  )
}

# ---- Validation against values published by FOPH/BAG ---------------------------

#' Compares the processed national Sentinella series with weekly values that
#' FOPH/BAG published at the time (data/reference/bag_reported_values.csv).
#' Confirms the units (prctConsultations x 10 = per 1,000 consultations;
#' incValue = per 100,000 inhabitants) and that the season-onset rule with the
#' published thresholds reproduces the onset weeks reported by FOPH/BAG.
#' Published values are first releases; small deviations are due to backfilling.
qc_bag_validation <- function(national, reported, thresholds) {
  cmp <- dplyr::inner_join(reported, national, by = "iso_week")
  rel <- function(ours, theirs) abs(ours - theirs) / theirs
  r1000 <- with(cmp[!is.na(cmp$ili_per_1000), ], rel(sentinella_ili_rate, ili_per_1000))
  r100k <- with(cmp[!is.na(cmp$ili_per_100k), ], rel(sentinella_ili_inc, ili_per_100k))
  onsets <- season_boundaries(national, thresholds)
  rep_on <- reported |>
    dplyr::filter(reported_onset %in% TRUE) |>
    dplyr::mutate(season = iso_week_to_season(iso_week)) |>
    dplyr::left_join(onsets, by = "season")
  match <- rep_on$iso_week == rep_on$onset_week
  dplyr::bind_rows(
    qc_row("sent_V1", "national",
           "Units confirmed against FOPH/BAG first publications (median dev. < 10%; a unit error would be a factor 10/100)",
           stats::median(r1000) < 0.10 && stats::median(r100k) < 0.10,
           sprintf("per 1,000 consultations: %d weeks, median dev. %.1f%%; per 100,000: %d weeks, median dev. %.1f%% (largest in holiday weeks: %s)",
                   length(r1000), 100 * stats::median(r1000), length(r100k), 100 * stats::median(r100k),
                   paste(cmp$iso_week[!is.na(cmp$ili_per_100k)][order(-r100k)][1:2], collapse = ", "))),
    qc_row("sent_V2", "national",
           "Onset rule + published thresholds reproduce FOPH/BAG onset weeks",
           all(match),
           paste(sprintf("%s: reported %s, ours %s", rep_on$season, rep_on$iso_week, rep_on$onset_week),
                 collapse = "; "),
           warn_only = TRUE)
  )
}

#' Stop the pipeline if any check failed
assert_qc <- function(qc) {
  failed <- dplyr::filter(qc, result == "FAIL")
  if (nrow(failed) > 0) {
    print(failed)
    stop(nrow(failed), " QC check(s) failed -- see output/qc/qc_checks.csv")
  }
  invisible(qc)
}
