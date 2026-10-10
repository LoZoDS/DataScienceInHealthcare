# =============================================================================
# R/setup.R -- load packages, config and all helper functions
# Usage (from the project root):  source("R/setup.R")
# =============================================================================
required_packages <- c("dplyr", "tidyr", "readr", "tibble", "ggplot2")
missing <- required_packages[!vapply(required_packages, requireNamespace,
                                     logical(1), quietly = TRUE)]
if (length(missing) > 0) {
  stop("Missing packages: ", paste(missing, collapse = ", "),
       "\nRun source(\"install_packages.R\") once.")
}
suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})

if (!file.exists("config.R")) {
  stop("Run this from the project root (open DataScienceInHealthcare.Rproj).")
}
source("config.R")
for (f in c("R/time_utils.R", "R/load_data.R", "R/qc.R", "R/prepare.R")) source(f)
