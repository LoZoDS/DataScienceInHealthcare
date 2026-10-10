# Raw data vintage

| File | Source URL | Downloaded | Rows (excl. header) | Last week | SHA-256 |
|---|---|---|---|---|---|
| INFLUENZA_oblig.csv | https://idd.bag.admin.ch/api/v1/export/latest/INFLUENZA_oblig/csv | by L. Zovkic, early Oct 2026 (exact date: please fill in) | 31,073 | 2026-W40 | `7ead6c967bc6e0815deb8a1dc4836ae73878ba5065ebafd94e3836fc5c794411` |
| INFLUENZA_sentinella.csv | https://idd.bag.admin.ch/api/v1/export/latest/INFLUENZA_sentinella/csv | by L. Zovkic, early Oct 2026 (exact date: please fill in) | 12,383 | 2026-W40 | `b29bac242168adf402705d110b592bbf4bb96c6ed09436aa5b535dc73f7d9474` |

Note: the Preliminary Study refers to a download on 24.09.2026 (30,938 / 12,332 observations, last week 2026-W37). The pipeline removes all weekly rows after 2026-W37 directly after loading (`restrict_to_study_vintage()`), which reproduces exactly these observation counts (QC checks `vintage_1`, `vintage_2`). See docs/open_issues.md, issue 4.

These files are the frozen project vintage. Do not edit; replace only on purpose via scripts/00_download_data.R.
