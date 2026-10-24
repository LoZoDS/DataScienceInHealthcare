knitr::opts_knit$set(root.dir = normalizePath(".."))
knitr::opts_chunk$set(echo = FALSE,  message = FALSE,  warning = FALSE,  
                      dpi = 150, fig.path = "figures/04_")

source("R/setup.R")

# Load packages
install_file <- "../install_packages.R"

# Load the national-level data
national <- load_national()

# Load the in-season classification from WP 4.2
in_season <- readr::read_csv("output/eda/in_season_weeks.csv",
                             show_col_types = FALSE)

# Create the forecast cache directory.
forecast_cache_dir <- "../DataScienceInHealthcare/output/forecast_cache"

if (!dir.exists(forecast_cache_dir)) {
  dir.create(
    forecast_cache_dir,
    recursive = TRUE,
    showWarnings = TRUE
  )
}

# Models to rebuild; empty means reuse existing cache.
REBUILD_MODEL_CACHE <- character(0)


# ---------------------------------------------------------------------------
# Reusable cache for expensive model results
# ---------------------------------------------------------------------------

get_or_build_cache <- function(cache_key, build_fn) {

  cache_file <- file.path(
    forecast_cache_dir,
    paste0(cache_key, ".rds")
  )

  # Reuse an existing result unless this cache key is marked for rebuilding.
  if (
    file.exists(cache_file) &&
    !(cache_key %in% REBUILD_MODEL_CACHE)
  ) {
    message("Loading cached result: ", cache_key)
    return(readRDS(cache_file))
  }

  # Otherwise, calculate the result and save it immediately.
  message("Building result: ", cache_key)

  result <- build_fn()

  saveRDS(result, cache_file)

  message("Saved cache: ", cache_file)

  result
}

model_spec_table <- data.frame(
  Component = c("Oblig AR terms", "Fourier terms","Sentinella lag",
                "Earlier Sentinella lags","Parameter selection"),
  `Candidate rules for the formal model` = c(
    "Consecutive lag combinations: 1; 1–2; 1–3; 1–4 weeks",
    "K = 1, 2, 3, corresponding to 1, 2, or 3 pairs of annual sine/cosine terms",
    "Forecast-origin observation preferred; previous-week observation as a conservative candidate",
    "Not included as default candidates in the main models",
    "Selected separately within each expanding training window"),
  Rationale = c(
    "Consistent with the original protocol's requirement for multiple autoregressive terms.",
    "Consistent with the original protocol's requirements for seasonality modelling and within-window selection.",
    "In WP 4.3, the same-week association was strongest, but evidence that Sentinella leads Oblig was insufficient.",
    "WP 4.3 showed no stable evidence of a 2–3-week lead.",
    "Avoids using the test seasons to select the model."), check.names = FALSE)

knitr::kable(model_spec_table, format = "pipe",
             caption = "Candidate rules and rationale for the forecasting models",
             align = c("l", "l", "l"))

# Step 1: Create one-week-ahead targets and candidate predictors
#
# Time-index convention:
#   origin = forecast-origin week t
#   prev1  = week t-1
#   prev2  = week t-2, etc.
#   target = week t+1
#
# Important:Predictors from the origin week may only be used if they are
# assumed to be available at the forecast origin.

forecast_data <- national |>
  dplyr::arrange(week_start) |>
  dplyr::mutate(
    # Forecast origin and target week
    origin_week = iso_week,
    origin_week_start = week_start,
    target_week = dplyr::lead(iso_week),
    target_week_start = dplyr::lead(week_start),

    # One-week-ahead target variables
    target_oblig_inc_100k = dplyr::lead(oblig_inc_100k),
    target_oblig_cases = dplyr::lead(oblig_cases),
    target_population = dplyr::lead(population),

    # Oblig incidence candidates:origin week and up to three preceding weeks
    oblig_origin = oblig_inc_100k,
    oblig_prev1 = dplyr::lag(oblig_inc_100k, 1),
    oblig_prev2 = dplyr::lag(oblig_inc_100k, 2),
    oblig_prev3 = dplyr::lag(oblig_inc_100k, 3),

    # Log-transformed Oblig incidence candidates
    oblig_log_origin = log1p(oblig_origin),
    oblig_log_prev1 = log1p(oblig_prev1),
    oblig_log_prev2 = log1p(oblig_prev2),
    oblig_log_prev3 = log1p(oblig_prev3),

    # Sentinella candidates:
    # same week as forecast origin and preceding weeks
    sent_origin = sentinella_ili_rate,
    sent_prev1 = dplyr::lag(sentinella_ili_rate, 1),
    sent_prev2 = dplyr::lag(sentinella_ili_rate, 2),
    sent_prev3 = dplyr::lag(sentinella_ili_rate, 3),

    # Log-transformed Sentinella candidates
    sent_log_origin = log1p(sent_origin),
    sent_log_prev1 = log1p(sent_prev1),
    sent_log_prev2 = log1p(sent_prev2),
    sent_log_prev3 = log1p(sent_prev3),

    # Fourier terms for the target week
    # K = 1, 2, or 3 can be considered during training-window selection
    target_season_week = dplyr::lead(season_week),
    sin1 = sin(2 * pi * target_season_week / 52),
    cos1 = cos(2 * pi * target_season_week / 52),
    sin2 = sin(4 * pi * target_season_week / 52),
    cos2 = cos(4 * pi * target_season_week / 52),
    sin3 = sin(6 * pi * target_season_week / 52),
    cos3 = cos(6 * pi * target_season_week / 52))

# Step 2: Attach the season classification of the target week

forecast_data <- forecast_data |>
  dplyr::left_join(
    in_season |>
      dplyr::select(iso_week, season, test_season, in_season) |>
      dplyr::rename(target_week = iso_week, target_season = season,
                    target_test_season = test_season, target_in_season = in_season),
                    by = "target_week")

# Step 3: Define candidate predictor sets for formal model selection

# Oblig auto-regressive candidates:
# choose a contiguous lag structure within each training window.
# The origin-week value corresponds to lag 1 relative to target week t+1.
oblig_ar_candidates <- list(
  AR1 = c("oblig_log_origin"),
  AR2 = c("oblig_log_origin", "oblig_log_prev1"),
  AR3 = c("oblig_log_origin", "oblig_log_prev1", "oblig_log_prev2"),
  AR4 = c("oblig_log_origin","oblig_log_prev1","oblig_log_prev2","oblig_log_prev3"))

# Fourier candidates: K = 1, 2, or 3
fourier_candidates <- list(
  K1 = c("sin1", "cos1"),
  K2 = c("sin1", "cos1", "sin2", "cos2"),
  K3 = c("sin1", "cos1", "sin2", "cos2", "sin3", "cos3")
)

# Sentinella candidates motivated by WP 4.3:
# origin week is the primary candidate only if available at origin;
# previous week is the conservative alternative.
sentinella_candidates <- list(
  origin = "sent_log_origin",
  previous_week = "sent_log_prev1"
)

# These objects define candidate sets only.
# Selection must be performed separately inside each training window.

# Step 4: Check missingness among the candidate predictors

all_candidate_predictors <- unique(c(
  unlist(oblig_ar_candidates, use.names = FALSE),
  unlist(fourier_candidates, use.names = FALSE),
  unlist(sentinella_candidates, use.names = FALSE)))

forecast_data |>
  dplyr::summarise(
    missing_target_incidence = sum(is.na(target_oblig_inc_100k)),
    missing_target_cases = sum(is.na(target_oblig_cases)),
    missing_target_population = sum(is.na(target_population)),
    missing_candidate_predictors = sum(
      !stats::complete.cases(
        dplyr::pick(dplyr::all_of(all_candidate_predictors))
      ))) |>
  print()

# Step 5: Check test-season weeks and their in-season classification

cat("Number of rows:", nrow(forecast_data), "\n")

forecast_data |>
  dplyr::filter(target_test_season %in% TRUE) |>
  dplyr::count(target_season, target_in_season) |>
  print()

# =============================================================================
# Align COVID and post-2020 indicators with the target week
# =============================================================================

target_indicators <- national |>
  dplyr::select(iso_week, covid_season, post2020) |>
  dplyr::rename(target_week = iso_week, target_covid_season = covid_season,
                target_post2020 = post2020)

# Avoid joining the indicators twice if this block is re-run
forecast_data <- forecast_data |>
  dplyr::select(-dplyr::any_of(c("target_covid_season","target_post2020"))) |>
  dplyr::left_join(target_indicators,by = "target_week")

# Check indicator coverage and values
forecast_data |>
  dplyr::summarise(n_rows = dplyr::n(),missing_covid = sum(is.na(target_covid_season)),
                   missing_post2020 = sum(is.na(target_post2020))) |>
  print()

# Inspect the indicator types and values
str(forecast_data$target_covid_season)
str(forecast_data$target_post2020)

forecast_data |>
  dplyr::count(target_covid_season,target_post2020,.drop = FALSE) |>
  print(n = Inf)

# Identify the row with missing target-week indicators
forecast_data |>
  dplyr::filter(is.na(target_covid_season) | is.na(target_post2020)) |>
  dplyr::select(origin_week,target_week,origin_week_start,target_week_start,
                target_covid_season,target_post2020) |>
  print()

# Inspect the final rows of forecast_data
forecast_data |>
  dplyr::slice_tail(n = 5) |>
  dplyr::select(origin_week, target_week, origin_week_start, target_week_start,
                target_oblig_inc_100k, target_oblig_cases) |>
  print()

# Check rows without a valid one-week-ahead target
forecast_data |>
  dplyr::summarise(rows_without_target_week = sum(is.na(target_week)),
                   rows_without_target_date = sum(is.na(target_week_start)),
                   rows_without_target_incidence = sum(is.na(target_oblig_inc_100k)),
                   rows_without_target_cases = sum(is.na(target_oblig_cases))) |>
  print()

# =============================================================================
# Rolling-origin expanding-window forecasts
# Models 1, 2, and 3
# =============================================================================

# Model 1: Oblig-only negative binomial GLM
# Model 2: Oblig + Sentinella negative binomial GLM
# Model 3: Gradient Boosting using Model 2's selected predictors

# -----------------------------------------------------------------------------
# 1. Candidate predictors for NB GLM model selection
# -----------------------------------------------------------------------------

# Auto-regressive candidates: Oblig incidence observed at the forecast origin
ar_candidates <- list(
  AR1 = c("oblig_log_origin"),
  AR2 = c("oblig_log_origin", "oblig_log_prev1"),
  AR3 = c("oblig_log_origin", "oblig_log_prev1", "oblig_log_prev2"),
  AR4 = c("oblig_log_origin", "oblig_log_prev1", "oblig_log_prev2", "oblig_log_prev3"))

# Fourier candidates: K = 1, 2, or 3
fourier_candidates <- list(
  K1 = c("sin1", "cos1"),
  K2 = c("sin1", "cos1", "sin2", "cos2"),
  K3 = c("sin1", "cos1", "sin2", "cos2", "sin3", "cos3"))

# Sentinella candidates selected using the WP 4.3 analysis
sentinella_candidates <- c("sent_log_origin", "sent_log_prev1")

# -----------------------------------------------------------------------------
# 2. Select the NB GLM specification within one training window
# -----------------------------------------------------------------------------

select_nb_model <- function(train_data, include_sent = FALSE) {

  # Use a common complete-case sample for all candidate specifications.
  # Model 1: Oblig predictors only.
  # Model 2: Oblig predictors plus one candidate Sentinella predictor.

  all_predictors <- unique(c(
    unlist(ar_candidates, use.names = FALSE),
    unlist(fourier_candidates, use.names = FALSE),
    if (include_sent) sentinella_candidates
  ))

  train_complete <- train_data |>
    dplyr::filter(
      !is.na(target_oblig_cases),
      is.finite(target_oblig_cases),
      target_oblig_cases >= 0,
      !is.na(target_population),
      is.finite(target_population),
      target_population > 0,
      dplyr::if_all(
        dplyr::all_of(all_predictors),
        ~ !is.na(.x) & is.finite(.x)
      )
    )

  if (nrow(train_complete) == 0) {
    stop("No complete training rows available for NB model selection.")
  }

  candidates <- list()
  fit_errors <- character()
  j <- 0L

  # Compare all AR lag and Fourier K combinations.
  # Model 2 additionally compares the predefined Sentinella candidates.

  for (ar_name in names(ar_candidates)) {
    for (fourier_name in names(fourier_candidates)) {

      sent_options <- if (include_sent) {
        sentinella_candidates
      } else {
        NA_character_
      }

      for (sent_var in sent_options) {

        predictors <- c(
          ar_candidates[[ar_name]],
          fourier_candidates[[fourier_name]],
          if (include_sent) sent_var
        )

        model_formula <- stats::as.formula(
          paste(
            "target_oblig_cases ~",
            paste(predictors, collapse = " + "),
            "+ offset(log(target_population))"
          )
        )

        fitted_model <- tryCatch(
          suppressWarnings(
            MASS::glm.nb(
              formula = model_formula,
              data = train_complete
            )
          ),
          error = function(e) {
            fit_errors <<- c(
              fit_errors,
              paste(
                ar_name,
                fourier_name,
                sent_var,
                conditionMessage(e),
                sep = " | "
              )
            )
            NULL
          }
        )

        if (!is.null(fitted_model)) {
          model_aic <- stats::AIC(fitted_model)

          if (is.finite(model_aic)) {
            j <- j + 1L
            candidates[[j]] <- list(
              model = fitted_model,
              formula = model_formula,
              predictors = predictors,
              AR = ar_name,
              Fourier = fourier_name,
              Sentinella = sent_var,
              AIC = model_aic
            )
          }
        }
      }
    }
  }

  if (length(candidates) == 0) {
    cat("Candidate NB GLM fitting errors:\n")
    print(utils::head(fit_errors, 10))
    stop("All candidate NB GLMs failed to fit.")
  }

  # Select the candidate with the lowest AIC.
  aic_values <- vapply(
    candidates,
    function(x) x$AIC,
    numeric(1)
  )

  best <- candidates[[which.min(aic_values)]]

  list(
    model = best$model,
    predictors = best$predictors,
    AR = best$AR,
    Fourier = best$Fourier,
    Sentinella = best$Sentinella,
    AIC = best$AIC,
    n_train = nrow(train_complete)
  )
}

# -----------------------------------------------------------------------------
# 3. Define the common complete-case predictor set
# -----------------------------------------------------------------------------

# Models 1, 2, and 3 use the same eligible test weeks.
# This allows evaluation on common target weeks.

common_predictors <- unique(c(
  unlist(ar_candidates, use.names = FALSE),
  unlist(fourier_candidates, use.names = FALSE),
  sentinella_candidates
))


# Model 3 uses the predictors selected by Model 2
# separately within each training window.

# -----------------------------------------------------------------------------
# 4. Expanding-window forecasting function
# -----------------------------------------------------------------------------

run_expanding_model <- function(
  data,
  model_type = c("NB_oblig", "NB_combined", "GBM"),
  model_name
) {

  model_type <- match.arg(model_type)

  # ---------------------------------------------------------------------------
  # 4.1 Select eligible test weeks
  # ---------------------------------------------------------------------------

  test_rows <- data |>
    dplyr::filter(
      target_season %in% TEST_SEASONS,

      !is.na(target_week_start),
      !is.na(week_start),

      !is.na(target_oblig_inc_100k),
      is.finite(target_oblig_inc_100k),

      !is.na(target_population),
      is.finite(target_population),
      target_population > 0,

      # Require all candidate predictors to be available.
      # This ensures a common evaluation sample across Models 1–3.
      dplyr::if_all(
        dplyr::all_of(common_predictors),
        ~ !is.na(.x) & is.finite(.x)
      )
    ) |>
    dplyr::arrange(target_week_start)

  if (nrow(test_rows) == 0) {
    stop("No eligible test weeks remain after filtering.")
  }

  # ---------------------------------------------------------------------------
  # 4.2 Generate one-week-ahead forecasts at each forecast origin
  # ---------------------------------------------------------------------------

  results <- vector("list", nrow(test_rows))

  for (i in seq_len(nrow(test_rows))) {

    new_data <- test_rows[i, ]

    # Forecast origin: start of the predictor week.
    origin_date <- as.Date(new_data$week_start[[1]])

  # Conservative training cutoff:
  # Only use observations whose target-week start date is at least
  # `cutoff_days` days before the forecast origin.
  # This corresponds to target weeks up to week t - (cutoff_days / 7).
  # The cutoff avoids assuming that the outcome for the forecast-origin
  # week (week t) is already available when the forecast is issued.
    
    train_data <- data |>
      dplyr::filter(
        !is.na(target_week_start),
        target_week_start <= origin_date - 7,

        !is.na(target_oblig_cases),
        is.finite(target_oblig_cases),
        target_oblig_cases >= 0,

        !is.na(target_oblig_inc_100k),
        is.finite(target_oblig_inc_100k),

        !is.na(target_population),
        is.finite(target_population),
        target_population > 0
      )


    # Initialise model-selection metadata.
    selected_AR <- NA_character_
    selected_Fourier <- NA_character_
    selected_Sentinella <- NA_character_
    selected_AIC <- NA_real_


    # -------------------------------------------------------------------------
    # 4.3 Models 1 and 2: Negative binomial GLM
    # -------------------------------------------------------------------------

    if (model_type %in% c("NB_oblig", "NB_combined")) {

      # Use the same complete-case training observations for both GLMs.
      common_train <- train_data |>
        dplyr::filter(
          dplyr::if_all(
            dplyr::all_of(common_predictors),
            ~ !is.na(.x) & is.finite(.x)
          )
        )

      if (nrow(common_train) == 0) {
        stop(
          "No common training observations at origin: ",
          as.character(origin_date)
        )
      }

      # Re-select the model specification inside this training window.
      if (model_type == "NB_oblig") {

        # Model 1: Oblig-only NB GLM.
        selected_model <- select_nb_model(
          train_data = common_train,
          include_sent = FALSE
        )

      } else {

        # Model 2: Combined Oblig + Sentinella NB GLM.
        selected_model <- select_nb_model(
          train_data = common_train,
          include_sent = TRUE
        )

      }

      fit <- selected_model$model

      # Save selected model structure for later auditing.
      selected_AR <- selected_model$AR
      selected_Fourier <- selected_model$Fourier
      selected_AIC <- selected_model$AIC

      if (model_type == "NB_combined") {
        selected_Sentinella <- selected_model$Sentinella
      }

      # Predict weekly case counts.
      predicted_cases <- stats::predict(
        fit,
        newdata = new_data,
        type = "response"
      )

      # Convert predicted counts to incidence per 100,000.
      prediction <- as.numeric(
        predicted_cases /
          new_data$target_population * 100000
      )

      n_train <- selected_model$n_train


    # -------------------------------------------------------------------------
    # 4.4 Model 3: Gradient Boosting using Model 2's selected predictors
    # -------------------------------------------------------------------------

    } else {

      # First select the Model 2 NB specification using this training window.
      # Reuse its selected predictors for Gradient Boosting.

      common_train <- train_data |>
        dplyr::filter(
          dplyr::if_all(
            dplyr::all_of(common_predictors),
            ~ !is.na(.x) & is.finite(.x)
          )
        )

      if (nrow(common_train) == 0) {
        stop(
          "No common training observations for Model 3 at origin: ",
          as.character(origin_date)
        )
      }

      selected_m2 <- select_nb_model(
        train_data = common_train,
        include_sent = TRUE
      )

      model3_predictors <- selected_m2$predictors

      # Store the same selected structure used by Model 2.
      selected_AR <- selected_m2$AR
      selected_Fourier <- selected_m2$Fourier
      selected_Sentinella <- selected_m2$Sentinella
      selected_AIC <- selected_m2$AIC

      # Gradient Boosting predicts incidence directly.
      model3_formula <- stats::reformulate(
        model3_predictors,
        response = "target_oblig_inc_100k"
      )

      gbm_train <- common_train |>
        dplyr::filter(
          !is.na(target_oblig_inc_100k),
          is.finite(target_oblig_inc_100k),

          dplyr::if_all(
            dplyr::all_of(model3_predictors),
            ~ !is.na(.x) & is.finite(.x)
          )
        )

      if (nrow(gbm_train) == 0) {
        stop(
          "No complete GBM training observations at origin: ",
          as.character(origin_date)
        )
      }

      set.seed(121)

      fit <- gbm::gbm(
        formula = model3_formula,
        data = gbm_train,
        distribution = "gaussian",
        n.trees = 500,
        interaction.depth = 2,
        shrinkage = 0.01,
        n.minobsinnode = 10,
        bag.fraction = 0.8,
        train.fraction = 1,
        verbose = FALSE
      )

      prediction <- as.numeric(
        stats::predict(
          fit,
          newdata = new_data,
          n.trees = 500,
          type = "response"
        )
      )

      n_train <- nrow(gbm_train)
    }


    # -------------------------------------------------------------------------
    # 4.5 Save forecast and model-selection metadata
    # -------------------------------------------------------------------------

    results[[i]] <- tibble::tibble(
      model = model_name,

      origin_week = as.character(
        new_data$iso_week[[1]]
      ),

      target_week = as.character(
        new_data$target_week[[1]]
      ),

      target_week_start = as.Date(
        new_data$target_week_start[[1]]
      ),

      target_season = as.character(
        new_data$target_season[[1]]
      ),

      target_in_season = new_data$target_in_season[[1]],

      actual = as.numeric(
        new_data$target_oblig_inc_100k[[1]]
      ),

      prediction = prediction,

      n_train = n_train,

      selected_AR = selected_AR,
      selected_Fourier = selected_Fourier,
      selected_Sentinella = selected_Sentinella,
      selected_AIC = selected_AIC
    )

  }


  # ---------------------------------------------------------------------------
  # 5. Return forecasts for all eligible test weeks
  # ---------------------------------------------------------------------------

  dplyr::bind_rows(results)
}

# Define the simple naive forecasting method
# Forecast next week's incidence using the latest observed incidence.

pred_method1 <- forecast_data |>
  dplyr::filter(target_test_season %in% TRUE) |>
  dplyr::transmute(
    method = "Simple naive",
    origin_week,
    target_week,
    target_week_start,
    target_season,
    target_in_season,
    actual = target_oblig_inc_100k,
    prediction = oblig_inc_100k
  )

# Keep forecasts with available observations and predictions for plotting
plot_method1 <- pred_method1 |>
  dplyr::filter(
    !is.na(actual),
    !is.na(prediction),
    !is.na(target_week_start)
  ) |>
  dplyr::arrange(target_week_start)

# Plot observed and predicted influenza incidence
ggplot2::ggplot(
  plot_method1,
  ggplot2::aes(x = target_week_start)
) +
  ggplot2::geom_line(
    ggplot2::aes(y = actual, color = "Observed"),
    linewidth = 0.7
  ) +
  ggplot2::geom_line(
    ggplot2::aes(y = prediction, color = "Simple naive forecast"),
    linewidth = 0.7,
    linetype = "dashed"
  ) +
  ggplot2::facet_wrap(
    ~target_season,
    scales = "free_x"
  ) +
  ggplot2::scale_x_date(                      
    date_breaks = "2 months",
    date_labels = "%b"
  ) +
  ggplot2::scale_color_manual(
    values = c(
      "Observed" = "#0B3C8C",
      "Simple naive forecast" = "#FDBF6F"
    )
  ) +
  ggplot2::labs(
    title = "Simple naive forecasting method",
    subtitle = "One-week-ahead forecasts during the test seasons",
    x = "Target week",
    y = "Oblig incidence per 100,000 population",
    color = NULL
  ) +
  ggplot2::theme_minimal() +
  ggplot2::theme(
    legend.position = "bottom"
  )

# Define the seasonal naive forecasting method
# Forecast next week's incidence using the incidence observed 52 weeks earlier.

seasonal_lookup <- national |>
  dplyr::transmute(
    seasonal_reference_week = week_start,
    seasonal_prediction = oblig_inc_100k
  )

pred_method2 <- forecast_data |>
  dplyr::filter(
    target_test_season %in% TRUE,
    !is.na(target_week_start)
  ) |>
  dplyr::mutate(
    seasonal_reference_week = target_week_start - 364
  ) |>
  dplyr::left_join(
    seasonal_lookup,
    by = "seasonal_reference_week"
  ) |>
  dplyr::transmute(
    method = "Seasonal naive",
    origin_week,
    target_week,
    target_week_start,
    target_season,
    target_in_season,
    actual = target_oblig_inc_100k,
    prediction = seasonal_prediction
  )

# Keep forecasts with available observations and predictions for plotting
plot_method2 <- pred_method2 |>
  dplyr::filter(
    !is.na(actual),
    !is.na(prediction),
    !is.na(target_week_start)
  ) |>
  dplyr::arrange(target_week_start)

# Plot observed and predicted influenza incidence
ggplot2::ggplot(
  plot_method2,
  ggplot2::aes(x = target_week_start)
) +
  ggplot2::geom_line(
    ggplot2::aes(y = actual, color = "Observed"),
    linewidth = 0.7
  ) +
  ggplot2::geom_line(
    ggplot2::aes(y = prediction, color = "Seasonal naive forecast"),
    linewidth = 0.7,
    linetype = "dashed"
  ) +
  ggplot2::facet_wrap(
    ~target_season,
    scales = "free_x"
  ) +
  ggplot2::scale_x_date(                      
    date_breaks = "2 months",
    date_labels = "%b"
  ) +
  ggplot2::scale_color_manual(
    values = c(
      "Observed" = "#0B3C8C",
      "Seasonal naive forecast" = "#FDBF6F"
    )
  ) +
  ggplot2::labs(
    title = "Seasonal naive forecasting method",
    subtitle = "One-week-ahead forecasts based on incidence\n52 weeks earlier",
    x = "Target week",
    y = "Oblig incidence per 100,000 population",
    color = NULL
) +
  ggplot2::theme_minimal() +
  ggplot2::theme(
    legend.position = "bottom",
    plot.subtitle = ggplot2::element_text(size = 10)
)

# Model 1: Negative Binomial GLM (Oblig-only)
pred_model1 <- get_or_build_cache(
  "model1",
  function() {
    run_expanding_model(
      data = forecast_data,
      model_type = "NB_oblig",
      model_name = "Model 1: Negative Binomial GLM (Oblig-only)"
    )
  }
)

if (nrow(pred_model1) == 0) {
  stop("Model 1 returned no forecasts.")
}

# Check forecast completeness
model1_summary <- pred_model1 |>
  dplyr::summarise(
    n_forecasts = dplyr::n(),
    n_missing_actuals = sum(is.na(actual)),
    n_missing_predictions = sum(is.na(prediction)),
    n_non_finite_predictions = sum(
      !is.na(prediction) & !is.finite(prediction)
    )
  )

print(model1_summary)

# Model 1: Negative Binomial GLM (Oblig-only)
# Extract coefficients, p-values, IRRs, and 95% confidence intervals.

model1_train <- forecast_data |>
  dplyr::filter(
    !is.na(target_week_start),
    target_week_start <= max(target_week_start, na.rm = TRUE) - 7
  )

model1_selected <- select_nb_model(
  train_data = model1_train,
  include_sent = FALSE
)

model1_fit <- model1_selected$model
model1_summary <- summary(model1_fit)$coefficients

# Calculate IRRs and confidence intervals on the unrounded estimates.
model1_coefficients <- as.data.frame(model1_summary) |>
  tibble::rownames_to_column("term") |>
  dplyr::rename(
    coefficient = Estimate,
    standard_error = `Std. Error`,
    test_statistic = `z value`,
    p_value = `Pr(>|z|)`
  ) |>
  dplyr::mutate(
    IRR = exp(coefficient),
    IRR_lower_95 = exp(coefficient - 1.96 * standard_error),
    IRR_upper_95 = exp(coefficient + 1.96 * standard_error)
  ) |>
  dplyr::mutate(
    dplyr::across(
      -term,
      ~ signif(.x, 4)
    )
  )

print(model1_coefficients, row.names = FALSE)

# Model 2: Negative Binomial GLM (Oblig + Sentinella)

# Generate expanding-window forecasts.
pred_model2 <- get_or_build_cache(
  "model2",
  function() {
    run_expanding_model(
      data = forecast_data,
      model_type = "NB_combined",
      model_name = "Model 2: Negative Binomial GLM (Oblig + Sentinella)"
    )
  }
)

# Check that forecasts were generated.
if (nrow(pred_model2) == 0) {
  stop("Model 2 returned no forecasts.")
}

# Inspect the first 10 forecasts.
pred_model2 |>
  dplyr::select(
    origin_week,
    target_week,
    target_season,
    actual,
    prediction,
    n_train,
    selected_AR,
    selected_Fourier,
    selected_Sentinella,
    selected_AIC
  ) |>
  print(n = 10, width = Inf)

# Calculate summary statistics using finite predictions only.
finite_predictions <- pred_model2$prediction[
  is.finite(pred_model2$prediction)
]

model2_summary <- pred_model2 |>
  dplyr::summarise(
    n_forecasts = dplyr::n(),
    n_missing_actuals = sum(is.na(actual)),
    n_missing_predictions = sum(is.na(prediction)),
    n_non_finite_predictions = sum(
      !is.na(prediction) & !is.finite(prediction)
    )
  ) |>
  dplyr::mutate(
    mean_prediction = if (length(finite_predictions) > 0) {
      mean(finite_predictions)
    } else {
      NA_real_
    },
    min_prediction = if (length(finite_predictions) > 0) {
      min(finite_predictions)
    } else {
      NA_real_
    },
    max_prediction = if (length(finite_predictions) > 0) {
      max(finite_predictions)
    } else {
      NA_real_
    }
  )

print(model2_summary)

# Inspect how often each model specification was selected.
model2_specification_counts <- pred_model2 |>
  dplyr::count(
    selected_AR,
    selected_Fourier,
    selected_Sentinella,
    name = "n_forecasts"
  ) |>
  dplyr::arrange(dplyr::desc(n_forecasts))

print(model2_specification_counts, n = Inf)

# Model 2: Negative Binomial GLM (Oblig + Sentinella)
# Extract coefficients, p-values, IRRs, and 95% Wald confidence intervals.
# Fit the illustrative model at the first eligible test forecast origin.

# Identify the first target week in the generated forecasts.
first_target_date <- pred_model2$target_week_start[[1]]

# Recover the corresponding forecast-origin row from forecast_data.
first_test_row <- forecast_data |>
  dplyr::filter(
    target_week_start == first_target_date
  ) |>
  dplyr::slice(1)

if (nrow(first_test_row) != 1) {
  stop("Could not identify the first test forecast row.")
}

# Use the same forecast-origin date and training cutoff as the forecasting function.
origin_date <- as.Date(first_test_row$week_start[[1]])

model2_train <- forecast_data |>
  dplyr::filter(
    !is.na(target_week_start),
    target_week_start <= origin_date - 7,

    !is.na(target_oblig_cases),
    is.finite(target_oblig_cases),
    target_oblig_cases >= 0,

    !is.na(target_oblig_inc_100k),
    is.finite(target_oblig_inc_100k),

    !is.na(target_population),
    is.finite(target_population),
    target_population > 0
  ) |>
  dplyr::filter(
    dplyr::if_all(
      dplyr::all_of(common_predictors),
      ~ !is.na(.x) & is.finite(.x)
    )
  )

if (nrow(model2_train) == 0) {
  stop("No eligible training observations for Model 2.")
}

# Select the combined NB GLM using the existing model-selection function.
model2_selected <- select_nb_model(
  train_data = model2_train,
  include_sent = TRUE
)

model2_fit <- model2_selected$model

# Extract coefficient estimates and standard errors.
model2_coef_raw <- as.data.frame(
  summary(model2_fit)$coefficients
) |>
  tibble::rownames_to_column("term") |>
  dplyr::rename(
    coefficient = Estimate,
    standard_error = `Std. Error`,
    test_statistic = `z value`,
    p_value = `Pr(>|z|)`
  )

# Calculate IRRs and 95% Wald confidence intervals.
model2_coefficients <- model2_coef_raw |>
  dplyr::mutate(
    IRR = exp(coefficient),
    IRR_lower_95 = exp(coefficient - 1.96 * standard_error),
    IRR_upper_95 = exp(coefficient + 1.96 * standard_error)
  ) |>
  dplyr::mutate(
    dplyr::across(
      -term,
      ~ signif(.x, 4)
    )
  )

print(model2_coefficients, row.names = FALSE)

# Report the selected model specification and diagnostics.
cat("Illustrative forecast origin:", as.character(origin_date), "\n")
cat("Selected AR structure:", model2_selected$AR, "\n")
cat("Selected Fourier terms:", model2_selected$Fourier, "\n")
cat("Selected Sentinella predictor:", model2_selected$Sentinella, "\n")
cat("Selected AIC:", model2_selected$AIC, "\n")
cat("Theta:", model2_fit$theta, "\n")
cat("Number of training observations:", model2_selected$n_train, "\n")

# Model 3: Gradient Boosting
pred_model3 <- get_or_build_cache(
  "model3",
  function() {
    run_expanding_model(
      data = forecast_data,
      model_type = "GBM",
      model_name = "Model 3: Gradient Boosting"
    )
  }
)

# Check that forecasts were generated
if (nrow(pred_model3) == 0) {
  stop("Model 3 produced no forecasts. Check the test-season and training filters.")
}

# Keep only finite predictions for summary statistics
finite_predictions_model3 <- pred_model3$prediction[
  is.finite(pred_model3$prediction)
]

# Inspect forecasts and the predictor specification selected at each origin
pred_model3 |>
  dplyr::select(
    origin_week,
    target_week,
    target_season,
    actual,
    prediction,
    n_train,
    selected_AR,
    selected_Fourier,
    selected_Sentinella,
    selected_AIC
  ) |>
  print(n = 10, width = Inf)

# Summarise forecast coverage and prediction validity
model3_summary <- pred_model3 |>
  dplyr::summarise(
    n_forecasts = dplyr::n(),
    n_missing_actuals = sum(is.na(actual)),
    n_missing_predictions = sum(is.na(prediction)),
    n_non_finite_predictions = sum(
      !is.na(prediction) & !is.finite(prediction)
    ),
    mean_prediction = if (length(finite_predictions_model3) > 0) {
      mean(finite_predictions_model3)
    } else {
      NA_real_
    },
    min_prediction = if (length(finite_predictions_model3) > 0) {
      min(finite_predictions_model3)
    } else {
      NA_real_
    },
    max_prediction = if (length(finite_predictions_model3) > 0) {
      max(finite_predictions_model3)
    } else {
      NA_real_
    }
  )

print(model3_summary)

# ---------------------------------------------------------------------------
# Model 4a and 4b: Sensitivity analyses
# ---------------------------------------------------------------------------

run_nb_indicator_sensitivity <- function(data, indicator, model_name) {

  # Identify eligible one-week-ahead test forecasts.
  test_rows <- data |>
    dplyr::filter(
      target_season %in% TEST_SEASONS,
      !is.na(target_week_start),
      !is.na(week_start),
      !is.na(target_oblig_inc_100k),
      is.finite(target_oblig_inc_100k),
      !is.na(target_population),
      is.finite(target_population),
      target_population > 0,
      !is.na(.data[[indicator]]),
      dplyr::if_all(
        dplyr::all_of(common_predictors),
        ~ !is.na(.x) & is.finite(.x)
      )
    ) |>
    dplyr::arrange(target_week_start)

  if (nrow(test_rows) == 0) {
    stop("No eligible test weeks for ", model_name)
  }

  results <- vector("list", nrow(test_rows))

  for (i in seq_len(nrow(test_rows))) {

    new_data <- test_rows[i, ]
    origin_date <- as.Date(new_data$week_start[[1]])

    # Expanding training window; exclude information unavailable
    # at the forecast origin.
    train_data <- data |>
      dplyr::filter(
        !is.na(target_week_start),
        target_week_start <= origin_date - 7,
        !is.na(target_oblig_cases),
        is.finite(target_oblig_cases),
        target_oblig_cases >= 0,
        !is.na(target_oblig_inc_100k),
        is.finite(target_oblig_inc_100k),
        !is.na(target_population),
        is.finite(target_population),
        target_population > 0,
        !is.na(.data[[indicator]]),
        dplyr::if_all(
          dplyr::all_of(common_predictors),
          ~ !is.na(.x) & is.finite(.x)
        )
      )

    if (nrow(train_data) == 0) {
      stop(
        "No eligible training observations for ",
        model_name, " at origin: ",
        as.character(origin_date)
      )
    }

    # Select the base NB GLM specification using Model 2.
    selected_model <- select_nb_model(
      train_data = train_data,
      include_sent = TRUE
    )

    # Add the sensitivity indicator to the selected specification.
    sensitivity_predictors <- c(
      selected_model$predictors,
      indicator
    )

    sensitivity_formula <- stats::as.formula(
      paste(
        "target_oblig_cases ~",
        paste(sensitivity_predictors, collapse = " + "),
        "+ offset(log(target_population))"
      )
    )

    fit <- MASS::glm.nb(
      sensitivity_formula,
      data = train_data
    )

    predicted_cases <- stats::predict(
      fit,
      newdata = new_data,
      type = "response"
    )

    prediction <- as.numeric(
      predicted_cases /
        new_data$target_population * 100000
    )

    results[[i]] <- tibble::tibble(
      model = model_name,
      origin_week = new_data$week_start[[1]],
      target_week = new_data$target_week[[1]],
      target_week_start = new_data$target_week_start[[1]],
      target_season = new_data$target_season[[1]],
      target_in_season = new_data$target_in_season[[1]],
      actual = new_data$target_oblig_inc_100k[[1]],
      prediction = prediction,
      n_train = selected_model$n_train,
      selected_AR = selected_model$AR,
      selected_Fourier = selected_model$Fourier,
      selected_Sentinella = selected_model$Sentinella,
      selected_AIC = selected_model$AIC
    )
  }

  dplyr::bind_rows(results)
}


# ---------------------------------------------------------------------------
# Model 4a: Model 2 + COVID-season indicator
# ---------------------------------------------------------------------------


model4a_covid <- get_or_build_cache(
  "model4a",
  function() {
    run_nb_indicator_sensitivity(
      data = forecast_data,
      indicator = "target_covid_season",
      model_name = "Model 4a: NB GLM + COVID-season indicator"
    )
  }
)


# ---------------------------------------------------------------------------
# Model 4b: Model 2 + post-2020 indicator
# ---------------------------------------------------------------------------


model4b_post2020 <- get_or_build_cache(
  "model4b",
  function() {
    run_nb_indicator_sensitivity(
      data = forecast_data,
      indicator = "target_post2020",
      model_name = "Model 4b: NB GLM + post-2020 indicator"
    )
  }
)


# ---------------------------------------------------------------------------
# Basic checks
# ---------------------------------------------------------------------------

cat("Model 4a rows:", nrow(model4a_covid), "\n")
cat("Model 4b rows:", nrow(model4b_post2020), "\n")

print(table(model4a_covid$target_season))
print(table(model4b_post2020$target_season))

summary(model4a_covid$prediction)
summary(model4b_post2020$prediction)

# Check the target week in the updated model predictions.

pred_model1 |>
  dplyr::filter(target_week == "2023-W40") |>
  dplyr::select(target_week, actual, prediction, dplyr::everything()) |>
  print()

pred_model2 |>
  dplyr::filter(target_week == "2023-W40") |>
  dplyr::select(target_week, actual, prediction, dplyr::everything()) |>
  print()

pred_model3 |>
  dplyr::filter(target_week == "2023-W40") |>
  dplyr::select(target_week, actual, prediction, dplyr::everything()) |>
  print()

# Check matching rows in forecast_data.
sum(forecast_data$target_week == "2023-W40", na.rm = TRUE)

# Inspect target_week formats.
head(pred_model1$target_week, 10)
head(pred_model2$target_week, 10)
head(pred_model3$target_week, 10)
head(forecast_data$target_week, 10)

# Check for duplicate target weeks in forecast_data.
forecast_data |>
  dplyr::filter(target_week == "2023-W40") |>
  dplyr::select(target_week, week_start, target_week_start) |>
  print()

# =============================================================================
# Negative Binomial Model Diagnostics
# Check convergence of the two primary NB GLMs across forecast origins:
# Model 1: NB Oblig-only
# Model 2: NB Oblig + Sentinella
# =============================================================================

# Define the diagnostic function before using it.
diagnose_nb_convergence <- function(predictions, model_label) {

  diagnostic_results <- vector("list", nrow(predictions))

  for (i in seq_len(nrow(predictions))) {

    target_week_i <- predictions$target_week[i]
    target_week_start_i <- predictions$target_week_start[i]

    # Identify the forecast origin.
    new_data <- forecast_data |>
      dplyr::filter(
        target_week_start == target_week_start_i
      )

    if (nrow(new_data) != 1) {
      stop(
        "Expected exactly one row for target week: ",
        target_week_i,
        "; found ",
        nrow(new_data)
      )
    }

    origin_date <- as.Date(new_data$week_start[1])

    # Reconstruct the eligible training data using the same cutoff.
    train_data <- forecast_data |>
      dplyr::filter(
        !is.na(target_week_start),
        target_week_start <= origin_date - 7,
        !is.na(target_oblig_cases),
        is.finite(target_oblig_cases),
        target_oblig_cases >= 0,
        !is.na(target_oblig_inc_100k),
        is.finite(target_oblig_inc_100k),
        !is.na(target_population),
        is.finite(target_population),
        target_population > 0,
        dplyr::if_all(
          dplyr::all_of(common_predictors),
          ~ !is.na(.x) & is.finite(.x)
        )
      )

    # Reconstruct the predictor set selected at this forecast origin.
    selected_ar <- as.character(
      predictions$selected_AR[i]
    )

    selected_fourier <- as.character(
      predictions$selected_Fourier[i]
    )

    predictors <- c(
      ar_candidates[[selected_ar]],
      fourier_candidates[[selected_fourier]]
    )

    selected_sent <- as.character(
      predictions$selected_Sentinella[i]
    )

    if (
      length(selected_sent) > 0 &&
      !is.na(selected_sent) &&
      nzchar(selected_sent)
    ) {
      predictors <- c(predictors, selected_sent)
    }

    # Refit the selected Negative Binomial GLM.
    model_formula <- stats::as.formula(
      paste(
        "target_oblig_cases ~",
        paste(predictors, collapse = " + "),
        "+ offset(log(target_population))"
      )
    )

    fit_warnings <- character()
    fit_error <- NA_character_

    fit <- tryCatch(
      withCallingHandlers(
        MASS::glm.nb(
          formula = model_formula,
          data = train_data
        ),
        warning = function(w) {
          fit_warnings <<- c(
            fit_warnings,
            conditionMessage(w)
          )
          invokeRestart("muffleWarning")
        }
      ),
      error = function(e) {
        fit_error <<- conditionMessage(e)
        NULL
      }
    )

    # Record failed fits.
    if (is.null(fit)) {

      diagnostic_results[[i]] <- tibble::tibble(
        model = model_label,
        target_week = target_week_i,
        n_train = nrow(train_data),
        theta = NA_real_,
        converged = FALSE,
        pearson_dispersion = NA_real_,
        warnings = paste(
          unique(fit_warnings),
          collapse = " | "
        ),
        fit_error = fit_error
      )

    } else {

      residual_df <- stats::df.residual(fit)

      pearson_dispersion <- if (
        is.finite(residual_df) && residual_df > 0
      ) {
        sum(
          stats::residuals(fit, type = "pearson")^2
        ) / residual_df
      } else {
        NA_real_
      }

      diagnostic_results[[i]] <- tibble::tibble(
        model = model_label,
        target_week = target_week_i,
        n_train = nrow(train_data),
        theta = fit$theta,
        converged = isTRUE(fit$converged),
        pearson_dispersion = pearson_dispersion,
        warnings = paste(
          unique(fit_warnings),
          collapse = " | "
        ),
        fit_error = fit_error
      )
    }
  }

  dplyr::bind_rows(diagnostic_results)
}


# Run diagnostics using the existing cache.
# If the cache exists, the diagnostic models will not be refitted.
nb_diagnostics <- get_or_build_cache(
  "nb_diagnostics",
  function() {
    dplyr::bind_rows(
      diagnose_nb_convergence(
        predictions = pred_model1,
        model_label = "Model 1: NB Oblig-only"
      ),
      diagnose_nb_convergence(
        predictions = pred_model2,
        model_label = "Model 2: NB Oblig + Sentinella"
      )
    )
  }
)


# Summarise convergence, warnings, errors and dispersion.
nb_diagnostic_summary <- nb_diagnostics |>
  dplyr::group_by(model) |>
  dplyr::summarise(
    n_fits = dplyr::n(),
    n_not_converged = sum(!converged),
    n_fits_with_warnings = sum(warnings != ""),
    n_fit_errors = sum(!is.na(fit_error)),
    min_theta = if (all(is.na(theta))) {
      NA_real_
    } else {
      min(theta, na.rm = TRUE)
    },
    median_theta = if (all(is.na(theta))) {
      NA_real_
    } else {
      median(theta, na.rm = TRUE)
    },
    median_pearson_dispersion = if (
      all(is.na(pearson_dispersion))
    ) {
      NA_real_
    } else {
      median(pearson_dispersion, na.rm = TRUE)
    },
    .groups = "drop"
  )

print(nb_diagnostic_summary, n = Inf)


# Inspect any warnings or fitting errors.
nb_diagnostic_issues <- nb_diagnostics |>
  dplyr::filter(
    warnings != "" | !is.na(fit_error)
  ) |>
  dplyr::select(
    model,
    target_week,
    theta,
    converged,
    pearson_dispersion,
    warnings,
    fit_error
  )

print(nb_diagnostic_issues, n = Inf, width = Inf)

nb_diagnostic_summary |>
  dplyr::rename(
    Model = model,
    `Number of fits` = n_fits,
    `Non-converged` = n_not_converged,
    `Fits with warnings` = n_fits_with_warnings,
    `Fit errors` = n_fit_errors,
    `Minimum theta` = min_theta,
    `Median theta` = median_theta,
    `Median Pearson dispersion` = median_pearson_dispersion
  ) |>
  knitr::kable(
    digits = 3,
    caption = "Diagnostic summary for negative binomial models"
  )

# =============================================================================
# Forecast validation: Check forecast integrity
# =============================================================================

prediction_list <- list(
  `Method 1: Naive` = pred_method1,
  `Method 2: Seasonal Naive` = pred_method2,
  `Model 1: NB Oblig-only` = pred_model1,
  `Model 2: NB Oblig + Sentinella` = pred_model2,
  `Model 3: Gradient Boosting` = pred_model3,
  `Model 4a: NB + COVID indicator` = model4a_covid,
  `Model 4b: NB + post-2020 indicator` = model4b_post2020
)

# Check that every method and model produced forecasts.
if (any(vapply(prediction_list, nrow, integer(1)) == 0)) {
  stop("At least one forecasting method or model produced no forecasts.")
}

# Check for missing target weeks.
if (any(vapply(
  prediction_list,
  function(x) any(is.na(x$target_week)),
  logical(1)
))) {
  stop("At least one forecasting method or model has missing target weeks.")
}

# Check for duplicate predictions per target week.
if (any(vapply(
  prediction_list,
  function(x) anyDuplicated(x$target_week) > 0,
  logical(1)
))) {
  stop("At least one forecasting method or model has duplicate predictions per target week.")
}

cat("Forecast integrity checks passed for both methods and all five models.\n")

# =============================================================================
# Forecast evaluation:
# - MAE and RMSE
# - Overall and in-season performance
# - MAE skill score relative to Method 1: Naive
# - Evaluation on common target weeks
# =============================================================================

# =============================================================================
# Step 1: Combine all methods and models on common target weeks
# =============================================================================

validation_data <- pred_method1 |>
  dplyr::select(
    target_week,
    target_season,
    target_in_season,
    actual,
    prediction_method1 = prediction
  ) |>
  dplyr::inner_join(
    pred_method2 |>
      dplyr::select(
        target_week,
        actual_method2 = actual,
        prediction_method2 = prediction
      ),
    by = "target_week"
  ) |>
  dplyr::inner_join(
    pred_model1 |>
      dplyr::select(
        target_week,
        actual_model1 = actual,
        prediction_model1 = prediction
      ),
    by = "target_week"
  ) |>
  dplyr::inner_join(
    pred_model2 |>
      dplyr::select(
        target_week,
        actual_model2 = actual,
        prediction_model2 = prediction
      ),
    by = "target_week"
  ) |>
  dplyr::inner_join(
    pred_model3 |>
      dplyr::select(
        target_week,
        actual_model3 = actual,
        prediction_model3 = prediction
      ),
    by = "target_week"
  ) |>
  dplyr::inner_join(
    model4a_covid |>
      dplyr::select(
        target_week,
        actual_model4a = actual,
        prediction_model4a = prediction
      ),
    by = "target_week"
  ) |>
  dplyr::inner_join(
    model4b_post2020 |>
      dplyr::select(
        target_week,
        actual_model4b = actual,
        prediction_model4b = prediction
      ),
    by = "target_week"
  )

# Check actual values before filtering invalid predictions.
actual_columns <- c(
  "actual",
  "actual_method2",
  "actual_model1",
  "actual_model2",
  "actual_model3",
  "actual_model4a",
  "actual_model4b"
)

actual_values <- as.matrix(validation_data[, actual_columns])

if (
  any(!is.finite(actual_values)) ||
  any(abs(actual_values - actual_values[, 1]) > 1e-8)
) {
  stop("Actual values are missing, non-finite, or differ across methods/models.")
}

# Keep common target weeks with finite predictions from every method/model.
validation_data <- validation_data |>
  dplyr::filter(
    dplyr::if_all(
      dplyr::starts_with("prediction_"),
      ~ is.finite(.x)
    )
  )

if (nrow(validation_data) == 0) {
  stop(
    "No common valid target weeks across both methods and all five models. ",
    "Check forecast coverage and missing predictions."
  )
}

cat(
  "Number of common valid target weeks across all methods and models:",
  nrow(validation_data),
  "\n"
)

# Remove duplicate actual-value columns after consistency checks.
validation_data <- validation_data |>
  dplyr::select(-dplyr::all_of(actual_columns[-1]))

# Report common evaluation weeks by test season.
common_weeks_by_season <- validation_data |>
  dplyr::count(target_season, name = "n_common_weeks")

print(common_weeks_by_season, n = Inf)

# =============================================================================
# Step 2: Reshape predictions into long format
# =============================================================================

validation_long <- validation_data |>
  tidyr::pivot_longer(
    cols = dplyr::starts_with("prediction_"),
    names_to = "model",
    values_to = "prediction"
  ) |>
  dplyr::mutate(
    model = dplyr::recode(
      model,
      prediction_method1 = "Method 1: Naive",
      prediction_method2 = "Method 2: Seasonal Naive",
      prediction_model1 = "Model 1: NB Oblig-only",
      prediction_model2 = "Model 2: NB Oblig + Sentinella",
      prediction_model3 = "Model 3: Gradient Boosting",
      prediction_model4a = "Model 4a: NB + COVID indicator",
      prediction_model4b = "Model 4b: NB + post-2020 indicator"
    ),
    abs_error = abs(actual - prediction),
    squared_error = (actual - prediction)^2
  )

# =============================================================================
# Step 3: Define overall and in-season evaluation groups
# =============================================================================

validation_groups <- dplyr::bind_rows(
  validation_long |>
    dplyr::mutate(evaluation = "All weeks"),

  validation_long |>
    dplyr::filter(target_in_season %in% TRUE) |>
    dplyr::mutate(evaluation = "In-season")
)

# =============================================================================
# Step 4: Calculate overall and in-season metrics
# =============================================================================

validation_metrics <- validation_groups |>
  dplyr::group_by(evaluation, model) |>
  dplyr::summarise(
    n = dplyr::n(),
    MAE = mean(abs_error),
    RMSE = sqrt(mean(squared_error)),
    .groups = "drop"
  ) |>
  dplyr::group_by(evaluation) |>
  dplyr::mutate(
    naive_MAE = MAE[model == "Method 1: Naive"][1],
    MAE_skill = 1 - MAE / naive_MAE
  ) |>
  dplyr::ungroup() |>
  dplyr::arrange(evaluation, MAE)

validation_metrics |>
  print(n = Inf, width = Inf)

# =============================================================================
# Step 5: Calculate metrics separately for each test season
# =============================================================================

validation_metrics_by_season <- validation_groups |>
  dplyr::group_by(evaluation, target_season, model) |>
  dplyr::summarise(
    n = dplyr::n(),
    MAE = mean(abs_error),
    RMSE = sqrt(mean(squared_error)),
    .groups = "drop"
  ) |>
  dplyr::group_by(evaluation, target_season) |>
  dplyr::mutate(
    naive_MAE = MAE[model == "Method 1: Naive"][1],
    MAE_skill = 1 - MAE / naive_MAE
  ) |>
  dplyr::ungroup() |>
  dplyr::arrange(evaluation, target_season, MAE)

validation_metrics_by_season |>
  print(n = Inf, width = Inf)

plot_mae <- validation_metrics |>
  dplyr::filter(evaluation == "All weeks") |>
  dplyr::mutate(
    model_type = dplyr::if_else(
      model %in% c("Method 1: Naive", "Method 2: Seasonal Naive"),
      "Baseline methods",
      "Research models"
    ),
    model = forcats::fct_reorder(model, MAE)
  ) |>
  ggplot2::ggplot(
    ggplot2::aes(x = MAE, y = model, fill = model_type)
  ) +
  ggplot2::geom_col(width = 0.65) +
  ggplot2::geom_text(
    ggplot2::aes(label = sprintf("%.2f", MAE)),
    hjust = -0.25,
    size = 5,
    show.legend = FALSE
  ) +
  ggplot2::scale_fill_manual(
    values = c(
      "Research models" = "#0B3C8C",
      "Baseline methods" = "#FDBF6F"
    )
  ) +
  ggplot2::scale_x_continuous(
    expand = ggplot2::expansion(mult = c(0, 0.30))
  ) +
  ggplot2::labs(
    title = "MAE Comparison Across Models and Baselines",
    subtitle = "Lower MAE indicates better predictive performance",
    x = "MAE (incidence per 100,000)",
    y = NULL,
    fill = NULL
  ) +
  ggplot2::theme_minimal(base_size = 8) +
  ggplot2::theme(
    plot.title = ggplot2::element_text(face = "bold"),
    axis.text.y = ggplot2::element_text(size = 8.5),  
    legend.text = ggplot2::element_text(size = 9),
    panel.grid.major.y = ggplot2::element_blank(),
    legend.position = "bottom"
  )

print(plot_mae)

# Prepare Figure 2 interpretation data
research_models <- c(
  "Model 1: NB Oblig-only",
  "Model 2: NB Oblig + Sentinella",
  "Model 3: Gradient Boosting",
  "Model 4a: NB + COVID indicator",
  "Model 4b: NB + post-2020 indicator"
)

fig2_data <- validation_metrics_by_season |>
  dplyr::filter(evaluation == "All weeks")

fig2_best_by_season <- fig2_data |>
  dplyr::filter(model %in% research_models) |>
  dplyr::group_by(target_season) |>
  dplyr::slice_min(MAE, n = 1, with_ties = FALSE) |>
  dplyr::ungroup()

fig2_naive <- fig2_data |>
  dplyr::filter(model == "Method 1: Naive") |>
  dplyr::select(target_season, naive_MAE = MAE)

fig2_seasonal_naive <- fig2_data |>
  dplyr::filter(model == "Method 2: Seasonal Naive") |>
  dplyr::select(
    target_season,
    seasonal_naive_MAE = MAE
  )

fig2_comparison <- fig2_best_by_season |>
  dplyr::select(
    target_season,
    best_model = model,
    best_MAE = MAE
  ) |>
  dplyr::left_join(fig2_naive, by = "target_season") |>
  dplyr::left_join(
    fig2_seasonal_naive,
    by = "target_season"
  ) |>
  dplyr::arrange(target_season)

fig2_comparison

plot_season_mae <- validation_metrics_by_season |>
  dplyr::filter(evaluation == "All weeks") |>
  ggplot2::ggplot(ggplot2::aes(x = target_season, y = MAE, fill = model)) +
  ggplot2::geom_col(position = ggplot2::position_dodge(width= 0.8),width= 0.7) +
  ggplot2::labs(title = "MAE by Test Season",
                subtitle = "Comparison of the five research models and two baseline methods",
                x = "Test season", y = "MAE (incidence per 100,000)",
                fill = "Model") +
  ggplot2::theme_minimal(base_size = 8) +
  ggplot2::theme(plot.title = ggplot2::element_text(face = "bold"),
                 legend.position = "bottom",
                 legend.box = "vertical",
                 legend.text = ggplot2::element_text(size = 8),
                 legend.title = ggplot2::element_text(size = 9)) +
  ggplot2::guides(fill = ggplot2::guide_legend(nrow = 4, byrow = TRUE))

print(plot_season_mae)

# ---- 1. Define the model order ---------------------------------------------

plot_model_levels <- c(
  "Method 1: Naive",
  "Method 2: Seasonal Naive",
  "Model 1: NB Oblig-only",
  "Model 2: NB Oblig + Sentinella",
  "Model 3: Gradient Boosting",
  "Model 4a: NB + COVID indicator",
  "Model 4b: NB + post-2020 indicator"
)

# Check the actual model labels before plotting.
available_models <- unique(as.character(validation_long$model))

missing_models <- setdiff(plot_model_levels, available_models)

if (length(missing_models) > 0) {
  stop(
    "The following methods/models are missing from validation_long: ",
    paste(missing_models, collapse = ", "),
    "\nAvailable models: ",
    paste(available_models, collapse = ", ")
  )
}

# ---- 2. Create a target-week lookup -----------------------------------------

season_week_lookup <- validation_data |>
  dplyr::distinct(target_season, target_week) |>
  dplyr::mutate(
    iso_year = as.integer(substr(target_week, 1, 4)),
    iso_week = as.integer(sub(".*-W", "", target_week))
  ) |>
  dplyr::arrange(target_season, iso_year, iso_week) |>
  dplyr::group_by(target_season) |>
  dplyr::mutate(
    week_in_season = dplyr::row_number()
  ) |>
  dplyr::ungroup() |>
  dplyr::select(
    target_season,
    target_week,
    iso_week,
    week_in_season
  )

# ---- 3. Prepare prediction data ---------------------------------------------

Plot_Act.vs.Pre <- validation_long |>
  dplyr::filter(
    as.character(model) %in% plot_model_levels
  ) |>
  dplyr::left_join(
    season_week_lookup,
    by = c("target_season", "target_week")
  ) |>
  dplyr::mutate(
    model = factor(
      as.character(model),
      levels = plot_model_levels
    )
  ) |>
  dplyr::select(
    target_week,
    target_season,
    actual,
    prediction,
    model,
    iso_week,
    week_in_season
  )

# Keep one actual observation per target week and season.
Actual_Panels <- Plot_Act.vs.Pre |>
  dplyr::distinct(
    target_season,
    target_week,
    week_in_season,
    actual
  )

# ---- 4. Configure the peak-period x-axis ------------------------------------

brk <- seq(9, 29, by = 2)

lab <- c(
  "48", "50", "52", "2", "4", "6",
  "8", "10", "12", "14", "16"
)

# ---- 5. Print diagnostic information ----------------------------------------

message(
  "Number of methods/models: ",
  dplyr::n_distinct(Plot_Act.vs.Pre$model)
)

message("Prediction rows: ", nrow(Plot_Act.vs.Pre))

message(
  "Unique season-week combinations: ",
  nrow(season_week_lookup)
)

message(
  "Missing week indices: ",
  sum(is.na(Plot_Act.vs.Pre$week_in_season))
)

message(
  "Missing model labels: ",
  sum(is.na(Plot_Act.vs.Pre$model))
)

message(
  "Methods/models included: ",
  paste(
    levels(droplevels(Plot_Act.vs.Pre$model)),
    collapse = "; "
  )
)

# ---- 6. Create the plot -----------------------------------------------------

plot_figure3 <- ggplot2::ggplot() +
  ggplot2::geom_line(
    data = Actual_Panels,
    ggplot2::aes(
      x = week_in_season,
      y = actual,
      colour = "Actual"
    ),
    linewidth = 0.4,
    na.rm = TRUE
  ) +
  ggplot2::geom_line(
    data = Plot_Act.vs.Pre,
    ggplot2::aes(
      x = week_in_season,
      y = prediction,
      colour = "Prediction"
    ),
    linewidth = 0.4,
    na.rm = TRUE
  ) +
  ggplot2::geom_point(
    data = Plot_Act.vs.Pre,
    ggplot2::aes(
      x = week_in_season,
      y = prediction,
      colour = "Prediction"
    ),
    size = 0.4,
    na.rm = TRUE
  ) +
  ggplot2::facet_grid(
    rows = ggplot2::vars(model),
    cols = ggplot2::vars(target_season),
    switch = "y"
  ) +
  ggplot2::scale_x_continuous(
    breaks = brk,
    labels = lab,
    expand = ggplot2::expansion(mult = c(0.02, 0.02))
  ) +
  ggplot2::scale_y_continuous(
    breaks = c(0, 20, 40),
    expand = ggplot2::expansion(mult = c(0.05, 0.10))
  ) +
  ggplot2::scale_colour_manual(
    values = c(
      "Actual" = "#0B3C8C",
      "Prediction" = "#FDBF6F"
    )
  ) +
  ggplot2::coord_cartesian(
    xlim = c(9, 29)
  ) +
  ggplot2::labs(
    title = "Actual vs. Predicted Influenza Incidence",
    subtitle = paste(
      "Peak period (ISO weeks 48–16):",
      "two baseline methods and five research models"
    ),
    x = "ISO week of target week",
    y = "Incidence per 100,000",
    colour = NULL
  ) +
  ggplot2::theme_minimal(base_size = 8) +
  ggplot2::theme(
    plot.title = ggplot2::element_text(
      face = "bold",
      size = 10,
      hjust = 0.5
    ),
    plot.subtitle = ggplot2::element_text(
      size = 8,
      hjust = 0.5
    ),
    strip.text.x = ggplot2::element_text(
      face = "bold",
      size = 8
    ),
    strip.text.y.left = ggplot2::element_text(
      angle = 0,
      hjust = 1,
      size = 6,
      face = "bold",
      lineheight = 0.85
    ),
    strip.placement = "outside",
    strip.background = ggplot2::element_blank(),
    axis.title.x = ggplot2::element_text(size = 10),
    axis.title.y = ggplot2::element_text(size = 7),
    axis.text.x = ggplot2::element_text(size = 6),
    axis.text.y = ggplot2::element_text(size = 4.5),
    legend.position = "bottom",
    legend.text = ggplot2::element_text(size = 7),
    panel.grid.minor = ggplot2::element_blank(),
    panel.spacing = grid::unit(0.8, "lines"),
    panel.spacing.y = grid::unit(0.5, "lines"),
    plot.margin = ggplot2::margin(8, 10, 6, 8)
  )

# ---- 7. Display the plot ----------------------------------------------------

print(plot_figure3)

