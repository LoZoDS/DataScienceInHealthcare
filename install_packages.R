# Run once per computer: source("install_packages.R")
pkgs <- c(
  # data preparation (WP 4.1)
  "dplyr", "tidyr", "readr", "tibble", "ggplot2",
  # reports and tests
  "rmarkdown", "knitr", "testthat",
  # exploratory analysis (WP 4.2): Moving Epidemic Method for season onset/end
  "mem",
  # lag analysis (WP 4.3)
  "forecast"
  # forecasting (WP 4.4/4.5) will add e.g. "MASS", "forecast", "xgboost"
)
new <- pkgs[!pkgs %in% rownames(installed.packages())]
if (length(new)) install.packages(new)
