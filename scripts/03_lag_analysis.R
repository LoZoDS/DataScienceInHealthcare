# =============================================================================
# Script Name:    03_lag_analysis.R
# Developer:      Hsiang-Chi Wang
# Purpose:        To analyze the relationship and lag analysis as specified in
#                 the Section 4.3 of the preliminary study
# Input:          /data/processed/flu_weekly_national.csv
#                 /data/processed/flu_weekly_strata_long.csv
# Output:
# =============================================================================

# Packages
install_file <- "install_packages.R"

recorded <- character()
env <- new.env()
env$install.packages <- function(p, ...) {
  recorded <<- c(recorded, p)
  missing <- setdiff(p, rownames(installed.packages()))
  if (length(missing) > 0) utils::install.packages(missing, ...)
}
source(install_file, local = env)

pd <- getParseData(parse(install_file, keep.source = TRUE))
strings <- gsub("^[\"']|[\"']$", "", pd$text[pd$token == "STR_CONST"])

pkgs <- unique(c(recorded, strings))
pkgs <- intersect(pkgs, rownames(installed.packages()))
invisible(lapply(pkgs, library, character.only = TRUE))


# Figure Specification
COL_OBLIG <- "#2a78d6"  # categorical slot 1
COL_SENT  <- "#eb6834"  # categorical slot 2
theme_set(theme_minimal(base_size = 11) +
            theme(panel.grid.minor = element_blank(),
                  panel.grid.major.x = element_blank(),
                  plot.title.position = "plot",
                  strip.text = element_text(face = "bold", hjust = 0)))


# ==== Load data ====
flu_w_nation = read_csv("data/processed/flu_weekly_national.csv")
flu_w_s_long = read_csv("data/processed/flu_weekly_strata_long.csv")

# Check data: weeks with missing values in each system
missing_senti <- flu_w_nation |>
  filter(is.na(sentinella_ili_rate)) |>
  select(iso_week, season)
print(missing_senti)

flu_w_nation |> filter(is.na(oblig_inc_100k)) |> select(iso_week, season)

# Check how many weeks each system has
data_check <- flu_w_nation |>
  summarise(weeks         = n(),
            oblig_present = sum(!is.na(oblig_inc_100k)),
            senti_present = sum(!is.na(sentinella_ili_rate)),
            senti_missing = sum(is.na(sentinella_ili_rate)))
print(data_check)

# Check data: lab-confirmed cases per unit of ILI, before vs after 2020
ratio_tab <- flu_w_nation |>
  filter(sentinella_ili_rate > 10, period != "covid") |>  # epidemic weeks, without the COVID seasons
  group_by(period) |>
  summarise(median_ratio = round(median(oblig_inc_100k / sentinella_ili_rate),
                                 2),   # cases per 100,000 per unit of ILI
            weeks = n()) |>
  arrange(desc(period))
ratio_pre  <- ratio_tab$median_ratio[ratio_tab$period == "pre2020"]
ratio_post <- ratio_tab$median_ratio[ratio_tab$period == "post2020"]
print(ratio_tab)


# ==== 1 CROSS-CORRELATION ====

## ---- 1.1 Naive correlation (before pre-whitening) ----
# Correlation between x and y for each shift ("lead")
#   lead > 0: x in week t vs y in week t + lead   -> x leads y
#   lead < 0: y in week t vs x in week t + |lead| -> y leads x
#   use = "complete.obs": skip pairs with a missing value
#         (series are NOT shortened)
cross_cor <- function(x, y, leads = -6:6) {
  n <- length(x)
  r <- sapply(leads, function(k) {
    if (k >= 0) cor(x[1:(n - k)], y[(1 + k):n], use = "complete.obs")
    else        cor(y[1:(n + k)], x[(1 - k):n], use = "complete.obs")
  })
  tibble(lead = leads, r = r)
}

# Bar chart of cross-correlations, coloured by which system leads
plot_ccf <- function(cc, band, title) {
  cc |>
    mutate(direction = case_when(lead > 0 ~ "Sentinella",
                                 lead < 0 ~ "Oblig",
                                 TRUE     ~ "Same week")) |>
    ggplot(aes(lead, r, fill = direction)) +
    geom_col(width = 0.6) +
    geom_hline(yintercept = 0, colour = "grey40") +
    geom_hline(yintercept = c(-band, band), linetype = "dashed", colour = "grey40") +
    scale_fill_manual(values = c(Sentinella = COL_SENT, Oblig = COL_OBLIG,
                                 "Same week" = "grey55")) +
    scale_x_continuous(breaks = -6:6) +
    labs(x = "Lead in weeks (positive = Sentinella leads mandatory reporting)",
         y = "Cross-correlation", title = title,
         caption = paste("Orange: Sentinella leads. Blue: mandatory reporting leads.",
                         "Grey: same week. Dashed: significance band.")) +
    theme(plot.caption = element_text(hjust = 1), legend.position = "none")
}

# Weeks with both systems present, and the Bonferroni-corrected band (4 leads)
n_pairs <- sum(complete.cases(flu_w_nation$sentinella_ili_rate,
                              flu_w_nation$oblig_inc_100k))
band    <- qnorm(1 - 0.025 / 4) / sqrt(n_pairs)    # qnorm(0.99375) = 2.50
cat("Weeks with both systems:", n_pairs, " Significance band: +/-", round(band, 3), "\n")

# Naive cross-correlation of the original series
cc_raw <- cross_cor(flu_w_nation$sentinella_ili_rate,
                    flu_w_nation$oblig_inc_100k)

fig_ccf_raw <- plot_ccf(cc_raw, band, "Cross-correlation before pre-whitening")
print(fig_ccf_raw)


## ---- 1.2 Correlation after pre-whitening ----
x <- flu_w_nation$sentinella_ili_rate   # input: Sentinella (original values), contains 2 NA
y <- flu_w_nation$oblig_inc_100k    # output: mandatory reporting (original values), complete

# a. Remove the seasonal cycle with Fourier terms
fourier_terms <- fourier(ts(x, frequency = 365.25 / 7), K = 3)   # 6 sine/cosine columns

# na.exclude: residuals for ALL weeks, NA kept in place -> series stays aligned
x_deseason <- resid(lm(x ~ fourier_terms, na.action = na.exclude))
y_deseason <- resid(lm(y ~ fourier_terms, na.action = na.exclude))

# b. ARIMA filter fitted on Sentinella
arima_fit <- auto.arima(x_deseason, seasonal = FALSE)   # season already removed in 5a

x_white <- as.numeric(resid(arima_fit))                 # Sentinella surprises

# c. The SAME filter on mandatory reporting
y_white <- as.numeric(resid(Arima(y_deseason, model = arima_fit)))

# d. Checks
# Ljung-Box test, H0 = no autocorrelation up to lag 10. Want p > 0.05
lbtest = Box.test(x_white, lag = 10, type = "Ljung-Box")

# ACF before vs after (na.pass: use all available pairs)
acf_df <- function(v, label, max_lag = 60) {
  a <- acf(v, lag.max = max_lag, plot = FALSE, na.action = na.pass)
  tibble(lag = as.numeric(a$lag)[-1],      # drop lag 0 (always 1)
         acf = as.numeric(a$acf)[-1],
         stage = label)
}

acf_both <- bind_rows(acf_df(x,       "Before: Sentinella"),
                      acf_df(x_white, "After: pre-whitened Sentinella")) |>
  mutate(stage = factor(stage, levels = c("Before: Sentinella",
                                          "After: pre-whitened Sentinella")))

fig_acf <- ggplot(acf_both, aes(lag, acf)) +
  geom_col(fill = COL_SENT, width = 0.7) +
  geom_hline(yintercept = 0, colour = "grey40") +
  geom_hline(yintercept = c(-1.96, 1.96) / sqrt(n_pairs),    # 95% band for white noise
             linetype = "dashed", colour = "grey40") +
  facet_wrap(~stage, ncol = 1) +
  labs(x = "Lag (weeks)", y = "Autocorrelation",
       title = "Autocorrelation of Sentinella before and after pre-whitening",
       caption = "Dashed: 95% band for white noise. Source: FOPH/BAG.") +
  theme(plot.caption = element_text(hjust = 1))

print(fig_acf)

# Values used in the pre-whitening table
arima_order <- paste0("ARIMA(", paste(arimaorder(arima_fit), collapse = ","), ")")
acf_after   <- acf_both |> filter(stage == "After: pre-whitened Sentinella")
acf_outside <- acf_after |> filter(abs(acf) > 1.96 / sqrt(n_pairs))
n_white     <- sum(complete.cases(x_white, y_white))

# Table: pre-whitening filter and white-noise checks
print(knitr::kable(
  tibble(Check = c("ARIMA filter (chosen by AIC)",
                   "Weeks with both pre-whitened series",
                   "Ljung-Box statistic (lag 10)",
                   "Ljung-Box p-value",
                   "ACF lags outside the 95% band (lags 1 to 60)"),
         Result = c(arima_order,
                    as.character(n_white),
                    sprintf("%.2f (df = %d)", lbtest$statistic, lbtest$parameter),
                    sprintf("%.2f", lbtest$p.value),
                    paste0(nrow(acf_outside), " (lags ",
                           paste(acf_outside$lag, collapse = ", "), ")"))),
  caption = "Pre-whitening filter and white-noise checks for the Sentinella series."))

# Cross-correlation of the pre-whitened series
cc_white <- cross_cor(x_white, y_white)

fig_ccf_white <- plot_ccf(cc_white, band, "Cross-correlation after pre-whitening")
print(fig_ccf_white)

# Table: naive and pre-whitened cross-correlations side by side
ccf_tab <- cc_raw |>
  rename(r_naive = r) |>
  left_join(cc_white |> rename(r_white = r), by = "lead") |>
  mutate(direction = case_when(lead > 0 ~ "Sentinella leads",
                               lead < 0 ~ "Mandatory reporting leads",
                               TRUE     ~ "Same week"),
         outside = ifelse(abs(r_white) > band, "Yes", "No"))

print(knitr::kable(ccf_tab |> select(lead, direction, r_naive, r_white, outside),
                   digits = 2,
                   col.names = c("Lead (weeks)", "Direction", "Naive r",
                                 "Pre-whitened r", "Outside band"),
                   caption = paste0("Cross-correlation between Sentinella and mandatory reporting, ",
                                    "before and after pre-whitening (n = ", n_pairs,
                                    " weeks; significance band +/-", sprintf("%.3f", band), ").")))


# ==== 2 LAG ANALYSIS ====

# Test statistics for each lead of the pre-whitened cross-correlation
z_bonf <- qnorm(1 - 0.025 / 4)

ccf_stats <- function(x, y, leads = -3:3) {
  n_all <- length(x)
  bind_rows(lapply(leads, function(k) {
    if (k >= 0) { a <- x[1:(n_all - k)]; b <- y[(1 + k):n_all] }
    else        { a <- y[1:(n_all + k)]; b <- x[(1 - k):n_all] }
    ok <- complete.cases(a, b)
    r  <- cor(a[ok], b[ok])
    n  <- sum(ok)
    tibble(lead = k, n = n, r = r,
           ci_low  = tanh(atanh(r) - z_bonf / sqrt(n - 3)),
           ci_high = tanh(atanh(r) + z_bonf / sqrt(n - 3)),
           p       = 2 * (1 - pnorm(abs(r) * sqrt(n))))
  }))
}

lag_stats <- ccf_stats(x_white, y_white, leads = -3:3) |>
  mutate(direction = case_when(lead > 0 ~ "Sentinella leads",
                               lead < 0 ~ "Mandatory reporting leads",
                               TRUE     ~ "Same week"))

# H1 table: leads 0 to 3, Bonferroni-adjusted p-values
h1_tab <- lag_stats |>
  filter(lead %in% 0:3) |>
  mutate(p_bonf = pmin(1, 4 * p),
         significant = ifelse(p_bonf < 0.05, "Yes", "No"))

# Lead with the strongest correlation
peak_lead <- lag_stats$lead[which.max(lag_stats$r)]
cat("Lead with the strongest correlation:", peak_lead, "weeks\n")


## ---- 2.1 Test of hypothesis H1 (leads 0 to 3 weeks) ----
fmt_p <- function(p) ifelse(p < 0.001, "<0.001", sprintf("%.3f", p))

print(knitr::kable(h1_tab |>
                     transmute(lead, n,
                               r = sprintf("%.2f", r),
                               ci = sprintf("%.2f to %.2f", ci_low, ci_high),
                               p = fmt_p(p),
                               p_bonf = fmt_p(p_bonf),
                               significant),
                   col.names = c("Lead (weeks)", "n", "r", "CI (Bonferroni-adjusted)",
                                 "p", "p (Bonferroni)", "Significant"),
                   caption = "Test of H1: pre-whitened cross-correlation at leads of 0 to 3 weeks (positive lead = Sentinella first)."))


## ---- 2.2 Direction and size of the lag ----
fig_lag <- ggplot(lag_stats, aes(lead, r, colour = direction)) +
  geom_hline(yintercept = 0, colour = "grey40") +
  geom_errorbar(aes(ymin = ci_low, ymax = ci_high), width = 0.15, linewidth = 0.7) +
  geom_point(size = 3) +
  geom_text(aes(label = sprintf("%.2f", ifelse(abs(r) < 0.005, 0, r))), nudge_x = 0.28, size = 3.2,
            colour = "grey20") +
  scale_colour_manual(values = c("Sentinella leads"          = COL_SENT,
                                 "Mandatory reporting leads" = COL_OBLIG,
                                 "Same week"                 = "grey45")) +
  scale_x_continuous(breaks = -3:3) +
  labs(x = "Lead in weeks (positive = Sentinella leads mandatory reporting)",
       y = "Cross-correlation after pre-whitening",
       title = "Lead-lag profile: the association peaks in the same week",
       caption = paste("Points: pre-whitened cross-correlation. Bars: Bonferroni-adjusted confidence intervals.",
                       "\nOrange: Sentinella leads. Blue: mandatory reporting leads. Grey: same week. Source: FOPH/BAG.")) +
  theme(legend.position = "none", plot.caption = element_text(hjust = 1))

print(fig_lag)

# Compare each Sentinella lead with the same-sized lead in the other direction
dir_tab <- tibble(k = 1:3) |>
  mutate(r_senti = sapply(k, function(i) lag_stats$r[lag_stats$lead ==  i]),
         r_oblig = sapply(k, function(i) lag_stats$r[lag_stats$lead == -i]),
         diff    = r_senti - r_oblig)

print(knitr::kable(dir_tab, digits = 2,
                   col.names = c("Shift (weeks)", "r, Sentinella leads",
                                 "r, mandatory reporting leads",
                                 "Difference (Sentinella minus mandatory)"),
                   caption = "Comparison of the two directions at the same shift."))


# ==== 3 SENSITIVITY ANALYSIS: PRE- AND POST-2020 (COVID) ====
prewhiten_ccf <- function(d, label, K = 3, scale = c("original", "log")) {
  scale <- match.arg(scale)
  x <- if (scale == "log") log1p(d$sentinella_ili_rate) else d$sentinella_ili_rate              # choose the scale
  y <- if (scale == "log") log1p(d$oblig_inc_100k)  else d$oblig_inc_100k
  ft <- fourier(ts(x, frequency = 365.25 / 7), K = K)           # 5a: seasonal waves
  xd <- resid(lm(x ~ ft, na.action = na.exclude))               # 5a: NA positions kept
  yd <- resid(lm(y ~ ft, na.action = na.exclude))
  fit <- auto.arima(xd, seasonal = FALSE)                       # 5b: filter on Sentinella
  xw <- as.numeric(resid(fit))                                  # 5b: Sentinella surprises
  yw <- as.numeric(resid(Arima(yd, model = fit)))               # 5c: same filter
  n_p <- sum(complete.cases(xw, yw))                            # weeks with both present
  cross_cor(xw, yw, leads = -3:3) |>                            # 6: cross-correlation
    mutate(subset = label, scale = scale, n = n_p,
           band = qnorm(1 - 0.025 / 4) / sqrt(n_p))             # band for this subset
}

sens <- bind_rows(
  prewhiten_ccf(flu_w_nation,                                            "All seasons"),
  prewhiten_ccf(filter(flu_w_nation, period == "pre2020"),               "Pre-2020"),
  prewhiten_ccf(filter(flu_w_nation, period == "post2020"),              "Post-2020"),
  #prewhiten_ccf(filter(flu_w_nation, week_start < as.Date("2023-10-02")), "Training only"),
  #prewhiten_ccf(flu_w_nation, "All seasons", scale = "log")             # scale check
)


# Cross-correlation figure per subset
sens_plot <- sens |>
  mutate(
    # panel title: subset, scale and number of weeks used
    panel = paste0(subset, " (n = ", n, ")"),
    panel = factor(panel, levels = unique(panel)),       # keep the order of the sens table
    # which system leads at this shift (same colours as the other figures)
    direction = case_when(lead > 0 ~ "Sentinella",
                          lead < 0 ~ "Oblig",
                          TRUE     ~ "Same week"),
    # is the bar outside this subset's own band? (used to fade non-significant bars)
    outside = abs(r) > band)

fig_sens <- ggplot(sens_plot, aes(lead, r, fill = direction)) +
  geom_col(aes(alpha = outside), width = 0.6) +
  geom_hline(yintercept = 0, colour = "grey40") +
  # each subset's own band: band is a column in the data, so each panel gets its own lines
  geom_hline(aes(yintercept =  band), linetype = "dashed", colour = "grey40") +
  geom_hline(aes(yintercept = -band), linetype = "dashed", colour = "grey40") +
  # value labels above positive bars, below negative bars (tiny values shown as 0.00)
  geom_text(aes(label = sprintf("%.2f", ifelse(abs(r) < 0.005, 0, r)),
                vjust = ifelse(r >= 0, -0.4, 1.3)),
            size = 2.8, colour = "grey20") +
  facet_wrap(~panel, ncol = 1) +                         # one panel per subset, stacked
  scale_fill_manual(values = c(Sentinella = COL_SENT, Oblig = COL_OBLIG,
                               "Same week" = "grey55")) +
  scale_alpha_manual(values = c(`TRUE` = 1, `FALSE` = 0.35)) +   # faded = inside the band
  scale_x_continuous(breaks = -3:3) +
  scale_y_continuous(limits = c(-0.25, 0.7), breaks = c(0, 0.25, 0.5)) +  # same scale in every panel
  labs(x = "Lead in weeks (positive = Sentinella leads mandatory reporting)",
       y = "Cross-correlation after pre-whitening",
       title = "Sensitivity analysis: pre-whitened cross-correlation by subset",
       caption = paste("Orange: Sentinella leads. Blue: mandatory reporting leads. Grey: same week.",
                       "\nFaded bars lie inside the dashed band (Bonferroni-corrected,",
                       "recomputed for each subset). Source: FOPH/BAG.")) +
  theme(plot.caption = element_text(hjust = 1),
        legend.position = "none",
        panel.spacing.y = unit(0.8, "lines"))

print(fig_sens)

# Table: pre-whitened cross-correlation by subset
sens_wide <- sens |>
  mutate(r = sprintf("%.2f", ifelse(abs(r) < 0.005, 0, r)),   # avoid "-0.00"
         band = sprintf("%.3f", band)) |>
  select(subset, n, band, lead, r) |>
  pivot_wider(names_from = lead, values_from = r)

print(knitr::kable(sens_wide,
                   col.names = c("Subset", "n", "Band", paste0("Lead ", -3:3)),
                   caption = "Pre-whitened cross-correlation by subset (positive lead = Sentinella first)."))

# Values used in the text of the report
r0_sens  <- sens |> filter(lead == 0)
rm1_sens <- sens |> filter(lead == -1)
rp1_sens <- sens |> filter(lead ==  1)
peak_all <- sens |> group_by(subset) |> slice_max(r, n = 1) |> pull(lead)

# Summary figure: leads -1, 0 and +1 per subset
fig_sens_summary <- sens |>
  filter(lead %in% c(-1, 0, 1)) |>                       # the three key shifts
  mutate(
    subset_lab = subset,
    subset_lab = factor(subset_lab, levels = rev(unique(subset_lab))),   # first subset on top
    lead_lab = factor(lead, levels = c(-1, 0, 1),
                      labels = c("Mandatory reporting leads by 1 week",
                                 "Same week",
                                 "Sentinella leads by 1 week"))) |>
  ggplot(aes(r, subset_lab)) +
  geom_segment(aes(x = 0, xend = r, yend = subset_lab), colour = "grey80") +  # line from 0
  geom_point(aes(colour = lead_lab), size = 3) +                               # the value
  geom_text(aes(label = sprintf("%.2f", r)), hjust = -0.4, size = 3, colour = "grey20") +
  facet_wrap(~lead_lab, nrow = 1) +                      # one column per shift
  scale_colour_manual(values = c("Mandatory reporting leads by 1 week" = COL_OBLIG,
                                 "Same week"                           = "grey45",
                                 "Sentinella leads by 1 week"          = COL_SENT)) +
  scale_x_continuous(limits = c(0, 0.72), breaks = c(0, 0.25, 0.5)) +
  labs(x = "Cross-correlation after pre-whitening", y = NULL,
       title = "Lead 0 is the strongest in every subset",
       caption = "Source: FOPH/BAG.") +
  theme(legend.position = "none",
        plot.caption = element_text(hjust = 1),
        panel.grid.major.x = element_line(colour = "grey92"),   # vertical lines help read values
        panel.grid.major.y = element_blank())

print(fig_sens_summary)
