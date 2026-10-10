# Data dictionary

## `data/processed/flu_weekly_national.csv`

One row per ISO week, 2013-W01 to 2026-W37 (715 rows), built from the study vintage (30,938 / 12,332 observations). Geography: Switzerland (without Liechtenstein).

| Variable | Type | Description |
|---|---|---|
| `iso_week` | chr | ISO 8601 week, e.g. `2024-W05` (key) |
| `week_start` | date | Monday of the ISO week |
| `iso_year`, `iso_wk` | int | ISO year and week number (1–53) |
| `season` | chr | influenza season W40–W39, e.g. `2023/24` |
| `season_week` | int | week within season, W40 = 1 (up to 53) |
| `oblig_cases` | int | laboratory-confirmed influenza cases, mandatory reporting, summed over cantons (incl. `unknown`) = Switzerland |
| `population` | int | BFS permanent resident population on 31 Dec of `iso_year` (2025 for 2026) |
| `oblig_inc_100k` | dbl | **Target.** `oblig_cases / population × 100,000` |
| `sentinella_ili_rate` | dbl | **Sentinella predictor.** ILI consultations per 1,000 consultations, national (`prctConsultations × 10`) |
| `sentinella_ili_inc` | dbl | Sentinella ILI consultations per 100,000 inhabitants (`incValue`); scale of the FOPH/BAG epidemic threshold, used for season onset/end (4.2) |
| `sentinella_source` | chr | `national` (value from the dataset) or `regional_weighted_mean` (fallback, Section 3); `NA` if missing |
| `complete_season` | lgl | all weeks of the season are in the data (FALSE for 2012/13 and 2025/26) |
| `covid_season` | lgl | season 2020/21 or 2021/22 |
| `period` | chr | `pre2020` (2013/14–2019/20), `covid`, `post2020` (≥ 2022/23), `pre2020_partial` (2012/13) |
| `post2020` | lgl | season ≥ 2022/23 (level-shift indicator for the sensitivity analysis) |
| `test_season` | lgl | 2023/24, 2024/25 or 2025/26 (rolling-origin test seasons) |
| `sentinella_missing` | lgl | no Sentinella value (2020-W11, 2020-W12) |
| `oblig_missing` | lgl | no mandatory-reporting value (none) |

Not included on purpose (leakage, see report section 4): FOPH/BAG `trend`, `deltaValue`, `deltaIncValue`, `incValuePrctChange`, `valueMean5y`, `inc14d`, and the 10-year min/median/max reference curves.

## `data/processed/flu_weekly_strata_long.csv`

All breakdowns of both systems in long format, for descriptive analyses (4.2). **Sum only within one `system` × `dimension`.**

| Variable | Description |
|---|---|
| `system` | `oblig` or `sentinella` |
| `iso_week`, `season` | as above |
| `dimension` | `canton`, `sentinella_region`, `agegroup`, `sex`, `type` |
| `level` | category within the dimension (e.g. `ZH`, `region_3`, `65+`, `female`, `A`, `unknown`) |
| `geo` | geographic level of the row (`CHFL` for oblig age/sex/type, `CH` for Sentinella age/sex, else the region) |
| `count` | oblig: lab-confirmed cases; Sentinella: extrapolated ILI consultations |
| `incidence_100k` | FOPH/BAG incidence per 100,000 within that stratum |
| `unit` | unit of `count` / `incidence_100k` |

Notes: Oblig age, sex and type breakdowns exist only for CH + FL combined. Sentinella values are extrapolated per stratum and do **not** add up to the national value.

## Raw files (`data/raw/`)

Columns as delivered by FOPH/BAG; types are fixed in `R/load_data.R`. The columns are not documented by FOPH/BAG; the meanings of the columns used were validated:

- `incValue` (both): per 100,000 inhabitants (checked against BFS population and against published FOPH/BAG Sentinella values, QC `sent_V1`)
- `prctConsultations` (Sentinella): ILI share of all consultations in % (× 10 = published "Grippeverdachtsfälle pro 1000 Konsultationen", QC `sent_V1`)
- `totalConsultationsExtrapolation`, `popExtrapolation` (Sentinella): not documented; used only as weights for the regional fallback (Section 3). With these weights the regional mean reproduces the national `prctConsultations` and `incValue` (QC `sent_C5`)
