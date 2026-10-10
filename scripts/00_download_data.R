# =============================================================================
# scripts/00_download_data.R -- download the current FOPH/BAG exports
# -----------------------------------------------------------------------------
# NOTE: the committed files in data/raw/ are the frozen vintage used in the
# project. Only re-run this on purpose (it OVERWRITES them) and document the
# new vintage in data/raw/DOWNLOAD_INFO.md.
# =============================================================================
source("config.R")

download_export <- function(url, dest) {
  message("Downloading ", url)
  utils::download.file(url, dest, mode = "wb", quiet = TRUE)
  hash <- if (requireNamespace("digest", quietly = TRUE)) {
    digest::digest(file = dest, algo = "sha256")
  } else NA_character_
  data.frame(file = basename(dest), url = url,
             downloaded = format(Sys.time(), "%Y-%m-%d %H:%M %Z"),
             sha256 = hash, rows = length(readLines(dest)) - 1L)
}

if (interactive()) {
  ok <- utils::askYesNo("This overwrites the frozen raw data in data/raw/. Continue?")
  if (!isTRUE(ok)) stop("Aborted.")
}
info <- rbind(download_export(URL_OBLIG, FILE_OBLIG),
              download_export(URL_SENTINELLA, FILE_SENTINELLA))
print(info)
message("Now update data/raw/DOWNLOAD_INFO.md with the table above.")
