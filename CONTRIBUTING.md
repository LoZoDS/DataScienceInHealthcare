# Working together in this repository

The project plan (Preliminary Study, Table 1) gives every work package a responsible author and a feedback author. The Git workflow mirrors this.

| WP | Branch | Author → reviewer |
|---|---|---|
| 4.1 Data preparation | `LZo` | L. Zovkic → S. Ryf |
| 4.2 Exploratory analysis | `SRy` | S. Ryf → L. Zovkic |
| 4.3 Lag analysis | `wp43-lag-analysis` | H. Wang → Q. Xu |
| 4.4/4.5 Forecasting | `wp44-forecasting` | Q. Xu → H. Wang |

## Workflow

1. Get the latest state: `git checkout main && git pull`
2. Create or switch to your WP branch: `git checkout -b wp42-exploratory`
3. Work, commit small steps with clear messages (`Add peak week per season`)
4. Push and open a **pull request** to `main`; assign your feedback author as reviewer
5. The reviewer comments in the PR (= feedback deadline), the author revises (= revision deadline), the reviewer merges

In RStudio all of this works via the *Git* tab; GitHub Desktop is a good alternative.

## Rules

- **Never edit files in `data/raw/`.** They are the frozen data vintage.
- **Do not change processed data by hand.** Change the code in `R/` or `scripts/` and re-run.
- Settings (periods, seasons, paths) only in `config.R`.
- Functions go into `R/`, analysis steps into numbered `scripts/`, text and figures into `reports/`.
- Each script must run from a fresh R session from the project root (`Rscript scripts/0X_....R`).
- Before opening a PR: run `testthat::test_dir("tests/testthat")`.
- Use only information available at the forecast origin as predictors (no leakage).

## Style

- tidyverse style, `snake_case`, native pipe `|>`
- Code, comments and reports in English (the paper is in English)
- Figures: one y-axis per panel (no dual axes); blue `#2a78d6` = mandatory reporting, orange `#eb6834` = Sentinella throughout the project
