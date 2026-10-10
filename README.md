# From Surveillance to Prediction: Forecasting Weekly Influenza Activity in Switzerland

Group project in the module **Data Science in Healthcare**, MSc Applied Information and Data Science (HSLU), autumn 2026.
Authors: S. Ryf, H. Wang, Q. Xu, L. Zovkic · Examiner: Philip Hochuli

**Main question.** Can the weekly national incidence of laboratory-confirmed influenza (per 100,000) in Switzerland be forecast one week ahead, and does adding Sentinella data improve the forecast compared with a model based on mandatory reporting data alone?

## Status

| WP | Content | Responsible / feedback | Status |
|---|---|---|---|
| 4.1 | Data preparation, GitHub repository | L. Zovkic / S. Ryf | ✅ draft ready for feedback → [report](reports/01_data_preparation.md) |
| 4.2 | Exploratory analysis (RQ1) | S. Ryf / L. Zovkic | open |
| 4.3 | Relationship and lag analysis (RQ2, H1) | H. Wang / Q. Xu | open |
| 4.4, 4.5 | Forecasting and evaluation (RQ3, H2) | Q. Xu / H. Wang | open |

## Quick start

```r
# 1. open DataScienceInHealthcare.Rproj in RStudio (sets the working directory)
# 2. once per computer
source("install_packages.R")
# 3. rebuild processed data + quality checks from the frozen raw files
source("scripts/01_data_preparation.R")
# 4. use the analysis-ready data in your own script
national <- readr::read_csv("data/processed/flu_weekly_national.csv")
```

Run the tests with `testthat::test_dir("tests/testthat")`. Render the report with `rmarkdown::render("reports/01_data_preparation.Rmd")`.

## Repository structure

```
├── config.R                     central settings: paths, study period, seasons, flags
├── install_packages.R           packages needed
├── R/                           functions only (no side effects)
│   ├── setup.R                  loads packages, config and all functions
│   ├── time_utils.R             ISO weeks, seasons (W40-W39)
│   ├── load_data.R              raw file schemas and readers
│   ├── qc.R                     quality checks
│   └── prepare.R                national series, strata table, season boundaries
├── scripts/                     numbered pipeline steps, run in order
│   ├── 00_download_data.R       (optional) new download - overwrites frozen raw data
│   └── 01_data_preparation.R    WP 4.1 -> data/processed, output/qc
├── data/
│   ├── raw/                     FOPH/BAG exports, frozen vintage (never edit by hand)
│   ├── reference/               BFS population, epidemic thresholds
│   └── processed/               analysis-ready data (generated)
├── output/qc/                   quality-check tables (generated)
├── reports/                     R Markdown reports per WP (+ rendered .md for GitHub)
├── tests/testthat/              unit and data tests
└── docs/                        data dictionary, open issues
```

Next WPs add `scripts/02_exploratory_analysis.R`, `03_lag_analysis.R`, `04_forecasting.R`, … and a report each.

## Data

| Dataset | Source | Content |
|---|---|---|
| `INFLUENZA_oblig.csv` | [FOPH/BAG](https://idd.bag.admin.ch/api/v1/export/latest/INFLUENZA_oblig/csv) | laboratory-confirmed influenza cases (mandatory reporting) |
| `INFLUENZA_sentinella.csv` | [FOPH/BAG](https://idd.bag.admin.ch/api/v1/export/latest/INFLUENZA_sentinella/csv) | influenza-like illness (ILI) consultations, Sentinella GP network |
| `population_ch_bfs.csv` | BFS STATPOP | permanent resident population on 31 December |

Only aggregated, publicly available data are used. The pipeline reproduces the data vintage of the Preliminary Study (24.09.2026, 2013-W01 to 2026-W37, 30,938 / 12,332 observations). Download date and file hashes: [data/raw/DOWNLOAD_INFO.md](data/raw/DOWNLOAD_INFO.md). Variables of the processed data: [docs/data_dictionary.md](docs/data_dictionary.md).

> ⚠️ The raw files contain several stratifications side by side (canton, age group, sex, type). Never sum over all rows – use `flu_weekly_national.csv`, or sum within one `dimension` of `flu_weekly_strata_long.csv`.

## Team workflow

See [CONTRIBUTING.md](CONTRIBUTING.md): one branch per work package, pull request reviewed by the feedback author, never commit to `main` directly.

## GenAI disclosure

As stated in the Preliminary Study, generative AI is used to support data preparation and programming (WP 4.1: Claude). All research ideas, decisions and interpretations remain our own.
