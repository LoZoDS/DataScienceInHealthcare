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

#' Stop the pipeline if any check failed
assert_qc <- function(qc) {
  failed <- dplyr::filter(qc, result == "FAIL")
  if (nrow(failed) > 0) {
    print(failed)
    stop(nrow(failed), " QC check(s) failed -- see output/qc/qc_checks.csv")
  }
  invisible(qc)
}
