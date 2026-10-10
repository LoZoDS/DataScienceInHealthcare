# Open issues for the team (from WP 4.1)

Decisions the team needs to take. Proposed solutions are suggestions from the data preparation, not yet agreed.

## 1. Season onset: no FOPH/BAG epidemic threshold after 2019/20  — affects 4.2, 4.5

The study defines season onset as the first of two consecutive weeks in which the Sentinella ILI rate exceeds *the FOPH/BAG epidemic threshold of the respective season*. FOPH/BAG stopped publishing that threshold from 2020/21 onwards ("Auf die Angabe eines epidemischen Schwellenwerts wird seit Saison 2020/21 verzichtet", Sentinella weekly report 47/2021). Since 2023/24 the epidemic period is defined by ≥ 10 % influenza test positivity, which is not in our data. Verified published values so far: 2016/17 = 64, 2018/19 = 68 ILI per 100,000 (`data/reference/epidemic_thresholds.csv`).

Options:
- **(a) Moving Epidemic Method (MEM)** – derive a threshold for every season from the preceding seasons (R package `mem`; standard method of ECDC/WHO Europe). Consistent, reproducible, uses only past data. *Recommended.*
- (b) Use the FOPH/BAG test-positivity periods from the annual reports for 2023/24 onwards (week 49–11 for 2023/24, week 50–14 for 2024/25) and published thresholds before 2020 → mixed definitions.
- (c) One fixed threshold (e.g. mean of published pre-2020 values) → simple, but ignores changes in consultation behaviour.

Also needed: the in-season weeks for the in-season MAE/RMSE in 4.5 depend on this.

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
