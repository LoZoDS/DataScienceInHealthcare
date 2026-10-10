# Open issues for the team (from WP 4.1)

Decisions the team needs to take. Proposed solutions are suggestions from the data preparation, not yet agreed.

## 1. Season onset: no FOPH/BAG epidemic threshold after 2019/20  — affects 4.2, 4.5

The study defines season onset as the first of two consecutive weeks in which the Sentinella ILI rate exceeds *the FOPH/BAG epidemic threshold of the respective season* (per 100,000 inhabitants; FOPH/BAG: average of the last ten seasons).

- **Found (FOPH/BAG values quoted in media / HUG bulletins):** 2013/14 = 74, 2014/15 = 70, 2016/17 = 64, 2017/18 = 68, 2018/19 = 68, 2019/20 = 69 (`data/reference/epidemic_thresholds.csv`, with sources). With these values the onset rule reproduces the FOPH/BAG-reported onset week in 4 of 5 seasons (QC `sent_V2`).
- **Not found:** 2015/16.
- **Not published:** from 2020/21 onwards ("Auf die Angabe eines epidemischen Schwellenwerts wird seit Saison 2020/21 verzichtet", Sentinella weekly report 47/2021, read from a copy on readkong.com). Since 2023/24 FOPH/BAG defines the epidemic period by ≥ 10 % influenza test positivity, which is not in our data.

So the rule as written cannot be applied to any post-2020 season, including the three test seasons. Options:
- **(a) Moving Epidemic Method (MEM)** (Vega et al. 2013, *Influenza Other Respir Viruses*; R package `mem`) – derives a threshold for each season from the preceding seasons; implemented by ECDC in TESSy (2010) and by WHO Europe in EuroFlu (2012). Consistent, reproducible, uses only past data. *Recommended.* Can be validated against the published FOPH/BAG thresholds 2013/14–2019/20.
- (b) Published FOPH/BAG thresholds where available, carry the last value (69) forward → simple, but not FOPH/BAG's definition after 2020 and ignores the changed consultation level.
- (c) FOPH/BAG test-positivity periods from the annual reports for 2023/24 onwards (week 49–11 for 2023/24, week 50–14 for 2024/25) → mixed definitions.

The in-season weeks for the in-season MAE/RMSE in 4.5 depend on this decision.

## 2. Unstable relationship between the two systems  — affects 4.3, 4.4

Lab-confirmed cases per 100 ILI consultations: about 3.5 before 2020, about 9.9 from 2022/23 (factor ≈ 2.8), with an upward drift already before 2020 (report, section 5). Suggestion: make the pre/post-2020 split a core part of the lag analysis and include `post2020` in all GLMs, not only as a sensitivity analysis. Consider also a training window starting in 2022/23 as an additional variant.

## 3. ILI is not influenza-specific after 2020  — affects 4.3 interpretation

Sentinella ILI also captures SARS-CoV-2 and other respiratory viruses (ILI rose in autumn 2020 with almost no influenza). Worth one sentence in the limitations.

## 4. Data vintage  — resolved as far as possible

The raw files are a later download (10.10.2026, up to 2026-W40) than the one in the study (24.09.2026). Removing all weeks after 2026-W37 reproduces exactly the 30,938 / 12,332 observations of the study (QC `vintage_1/2`). Values of earlier weeks may differ marginally through backfilling. If someone still has the original files of 24.09., replace them in `data/raw/` and update `DOWNLOAD_INFO.md`; the pipeline stays the same.

## 5. End of season 2025/26  — small, no action needed

The study period ends in 2026-W37, so 2025/26 lacks the off-season weeks W38–W39. Kept as in the study.

## 6. Missing Sentinella weeks 2020-W11/W12  — affects 4.4

Missing nationally and in all regions, so the regional fallback of Section 3 cannot fill them. Kept as `NA`. Decide in 4.4: linear interpolation for the lagged predictor, or drop the affected rows (all in training data).

## 7. Reporting delay  — affects 4.4

Publication lags of the two systems (Section 4.4) are not in the data; the forecasting WP needs to fix the lag per system (e.g. from FOPH/BAG publication schedule) in `config.R`.
