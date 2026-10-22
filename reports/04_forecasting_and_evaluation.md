WP 4.4 & 4.5 – Forecasting and evaluation
================
Q. Xu (responsible), H. Wang (feedback)
22 Oktober 2026

- [1 Load data](#1-load-data)
- [2 Build the forecasting dataset](#2-build-the-forecasting-dataset)
- [3 Define the forecasting models](#3-define-the-forecasting-models)
  - [Model 1 — Naive baseline](#model-1--naive-baseline)
  - [Model 2 — Seasonal naive](#model-2--seasonal-naive)
  - [Model 3 — Negative Binomial GLM
    (Oblig-only)](#model-3--negative-binomial-glm-oblig-only)
  - [Model 4 — Negative Binomial GLM (Oblig +
    Sentinella)](#model-4--negative-binomial-glm-oblig--sentinella)
  - [Model 5 — Gradient Boosting](#model-5--gradient-boosting)
  - [Model 6 — Sensitivity analysis for COVID and post-2020
    indicators](#model-6--sensitivity-analysis-for-covid-and-post-2020-indicators)
    - [Model 6a: NB GLM from Model 4 + COVID-season indicator  
      ](#model-6a-nb-glm-from-model-4--covid-season-indicator-)
    - [Model 6b: NB GLM from Model 4 + post2020 level-shift indicator  
      ](#model-6b-nb-glm-from-model-4--post2020-level-shift-indicator-)
- [4 Validate the models](#4-validate-the-models)
- [5 Plot the results](#5-plot-the-results)
  - [Figure 1: Overall MAE Comparison](#figure-1-overall-mae-comparison)
  - [Figure 2: MAE by Test Season](#figure-2-mae-by-test-season)
  - [Figure 3: Actual vs. Predicted Influenza
    Incidence](#figure-3-actual-vs-predicted-influenza-incidence)
- [6 Conclusion](#6-conclusion)

**Objective**

Forecast next-week influenza incidence in Switzerland and assess whether
Sentinella surveillance information improves predictive performance
beyond mandatory reporting (Oblig), while comparing statistical and
machine-learning forecasting approaches.

**Evaluation strategy**

- Expanding-window, rolling-origin evaluation across three test seasons
  (2023/24–2025/26).  

- Metrics: mean absolute error (MAE) and root mean squared error (RMSE),
  evaluated across all forecast weeks and during in-season weeks.  

- MAE skill score relative to the naive baseline:

  $$\text{MAE skill}=1-\frac{\text{MAE}_{\text{model}}}{\text{MAE}_{\text{naive}}}$$

  Positive values indicate lower MAE than the naive baseline, zero
  indicates equal MAE, and negative values indicate higher MAE.

**Key comparison**

Model 3 (NB Oblig-only) versus Model 4 (NB Oblig + Sentinella) assesses
the incremental predictive value of Sentinella information under the
specified model-selection procedure. Models 6a and 6b provide
sensitivity analyses by adding COVID-season and post-2020 indicators,
respectively.

# 1 Load data

The processed national dataset contains weekly influenza surveillance
data from Oblig and Sentinella.  
The in-season classification identifies the weeks considered part of the
influenza season.

# 2 Build the forecasting dataset

Purpose: Prepare the dataset for one-week-ahead forecasting by defining
the forecast origin and next-week target, constructing lagged
predictors, aligning target-week indicators, and identifying candidate
predictors for model selection.

| Component | Candidate rules for the formal model | Rationale |
|:---|:---|:---|
| Oblig AR terms | Consecutive lag combinations: 1; 1–2; 1–3; 1–4 weeks | Consistent with the original protocol’s requirement for multiple autoregressive terms |
| Fourier terms | $K = 1, 2, 3$, i.e., considering 1, 2, or 3 pairs of annual sine/cosine terms | Consistent with the original protocol’s requirements for seasonality modelling and within-window selection |
| Sentinella lag | The same-week observation at the forecast-origin week is the preferred candidate; the previous week’s observation is a conservative candidate | In WP 4.3, the same-week association was strongest, but the evidence that Sentinella leads Oblig was insufficient |
| Earlier Sentinella lags | Not included as default candidates in the main models | WP 4.3 showed no stable evidence of a 2–3 week lead |
| Parameter selection | Selected separately within each expanding training window | Avoids using the test seasons to select the model |

    ## # A tibble: 1 × 4
    ##   missing_target_incidence missing_target_cases missing_target_population
    ##                      <int>                <int>                     <int>
    ## 1                        1                    1                         1
    ## # ℹ 1 more variable: missing_candidate_predictors <int>

    ## Number of rows: 715

    ## # A tibble: 6 × 3
    ##   target_season target_in_season     n
    ##   <chr>         <lgl>            <int>
    ## 1 2023/24       FALSE               38
    ## 2 2023/24       TRUE                14
    ## 3 2024/25       FALSE               41
    ## 4 2024/25       TRUE                11
    ## 5 2025/26       FALSE               40
    ## 6 2025/26       TRUE                10

The forecasting dataset contains 715 weekly observations. One
observation lacks the target incidence, target case count, and target
population, while seven observations have missing candidate predictors.
Missing values are not imputed; observations are excluded from model
fitting or evaluation when the required variables are unavailable.

Across the three test seasons, the number of in-season evaluation weeks
ranged from (2025/26 )10 to (2023/24)14 per season.

**Target-week indicators and COVID-related data validation**

    ## # A tibble: 1 × 3
    ##   n_rows missing_covid missing_post2020
    ##    <int>         <int>            <int>
    ## 1    715             1                1

    ##  logi [1:715] FALSE FALSE FALSE FALSE FALSE FALSE ...

    ##  logi [1:715] FALSE FALSE FALSE FALSE FALSE FALSE ...

    ## # A tibble: 4 × 3
    ##   target_covid_season target_post2020     n
    ##   <lgl>               <lgl>           <int>
    ## 1 FALSE               FALSE             403
    ## 2 FALSE               TRUE              206
    ## 3 TRUE                FALSE             105
    ## 4 NA                  NA                  1

    ## # A tibble: 1 × 6
    ##   origin_week target_week origin_week_start target_week_start
    ##   <chr>       <chr>       <date>            <date>           
    ## 1 2026-W37    <NA>        2026-09-07        NA               
    ## # ℹ 2 more variables: target_covid_season <lgl>, target_post2020 <lgl>

    ## # A tibble: 5 × 6
    ##   origin_week target_week origin_week_start target_week_start
    ##   <chr>       <chr>       <date>            <date>           
    ## 1 2026-W33    2026-W34    2026-08-10        2026-08-17       
    ## 2 2026-W34    2026-W35    2026-08-17        2026-08-24       
    ## 3 2026-W35    2026-W36    2026-08-24        2026-08-31       
    ## 4 2026-W36    2026-W37    2026-08-31        2026-09-07       
    ## 5 2026-W37    <NA>        2026-09-07        NA               
    ## # ℹ 2 more variables: target_oblig_inc_100k <dbl>, target_oblig_cases <dbl>

    ## # A tibble: 1 × 4
    ##   rows_without_target_week rows_without_target_date rows_without_target_incide…¹
    ##                      <int>                    <int>                        <int>
    ## 1                        1                        1                            1
    ## # ℹ abbreviated name: ¹​rows_without_target_incidence
    ## # ℹ 1 more variable: rows_without_target_cases <int>

The COVID-related indicators were successfully mapped to the target
weeks. Among the 714 observations with valid target-week indicators, 403
belong to neither the COVID seasons nor the post-2020 period, 206 belong
to the post-2020 period, and 105 belong to the COVID seasons.

The final row has no target week or target outcome because the dataset
ends at the latest observed origin week. This is expected for
one-week-ahead forecasting and does not indicate a data-joining error.

# 3 Define the forecasting models

We compare baseline forecasting methods with statistical and
machine-learning models to assess the predictive value of Oblig
incidence and the additional information provided by Sentinella. Models
3 and 4 use negative binomial GLMs with autoregressive terms and Fourier
terms selected by AIC within each expanding training window. Model 3
uses Oblig information only, while Model 4 additionally selects a
Sentinella predictor from the predefined candidates. These models follow
the candidate-selection procedure described above. Model 5 uses Gradient
Boosting to allow for more flexible relationships and temporal patterns,
using the selected lagged predictors and Fourier terms. Models 6a and 6b
extend Model 4 with COVID-season and post-2020 indicators, respectively,
as sensitivity analyses.

## Model 1 — Naive baseline

Purpose: Use the most recent available Oblig incidence to forecast next
week’s incidence.

| n_forecasts | n_missing_actuals | n_missing_predictions | mean_prediction | min_prediction | max_prediction |
|---:|---:|---:|---:|---:|---:|
| 154 | 0 | 0 | 5.177 | 0.055 | 36.452 |

Model 1: Naive baseline output

***Interpretation***

The model generated 154 forecasts, with 0 missing actual values and 0
missing predictions. Predicted incidence ranged from 0.055 to 36.452 per
100,000 population, with a mean of 5.177. This naive baseline assumes
that next week’s incidence will equal the observed Oblig incidence in
the forecast-origin week.

## Model 2 — Seasonal naive

Purpose: Use the incidence from the corresponding week in the previous
season as a seasonal benchmark.

| n_forecasts | n_missing_actuals | n_missing_predictions | mean_prediction | min_prediction | max_prediction |
|---:|---:|---:|---:|---:|---:|
| 154 | 0 | 0 | 5.233 | 0.045 | 42.812 |

Model 2: Seasonal naive output

***Interpretation***

The model generated 154 forecasts, with 0 missing actual values and 0
missing predictions. Predicted incidence ranged from 0.045 to 42.812 per
100,000 population, with a mean of 5.233. This seasonal naive baseline
uses the observed incidence from 364 days before the target week as the
prediction for the target week.

**Rolling-origin expanding-window forecasts**

Purpose: Rolling-origin expanding-window forecasts were generated for
seven models across the three test seasons (2023/24, 2024/25 and
2025/26). At each forecast origin, models were fitted using the
available historical data and used to predict influenza incidence one
week ahead. The training window expanded as new observations became
available, while the training cutoff ensured that the target outcome was
not used before it could reasonably be observed.

The resulting forecasts were subsequently aligned on common target weeks
and evaluated using MAE and RMSE.

## Model 3 — Negative Binomial GLM (Oblig-only)

The model predicts Oblig incidence for the target week using reported
Oblig cases. The response variable is `target_oblig_cases`, and a
population offset is included to account for population size. Predicted
case counts are converted to incidence per 100,000 population. At each
forecast origin, AIC is used to select the autoregressive lag structure
(AR1–AR4) and the number of Fourier terms (K1–K3) from the candidate
specifications, using only the training data available at that origin.

    ## # A tibble: 154 × 9
    ##    origin_week target_week target_season actual prediction n_train selected_AR
    ##    <chr>       <chr>       <chr>          <dbl>      <dbl>   <int> <chr>      
    ##  1 2023-W39    2023-W40    2023/24        0.178     0.0462     553 AR4        
    ##  2 2023-W40    2023-W41    2023/24        0.167     0.0574     554 AR4        
    ##  3 2023-W41    2023-W42    2023/24        0.268     0.0644     555 AR4        
    ##  4 2023-W42    2023-W43    2023/24        0.268     0.101      556 AR4        
    ##  5 2023-W43    2023-W44    2023/24        0.435     0.120      557 AR4        
    ##  6 2023-W44    2023-W45    2023/24        0.658     0.212      558 AR4        
    ##  7 2023-W45    2023-W46    2023/24        0.748     0.376      559 AR4        
    ##  8 2023-W46    2023-W47    2023/24        0.904     0.438      560 AR4        
    ##  9 2023-W47    2023-W48    2023/24        1.70      0.674      561 AR4        
    ## 10 2023-W48    2023-W49    2023/24        3.53      2.10       562 AR4        
    ##    selected_Fourier selected_AIC
    ##    <chr>                   <dbl>
    ##  1 K3                      4471.
    ##  2 K3                      4480.
    ##  3 K3                      4490.
    ##  4 K3                      4499.
    ##  5 K3                      4511.
    ##  6 K3                      4520.
    ##  7 K3                      4532.
    ##  8 K3                      4544.
    ##  9 K3                      4555.
    ## 10 K3                      4566.
    ## # ℹ 144 more rows

    ## # A tibble: 1 × 7
    ##   n_forecasts n_missing_actuals n_missing_predictions n_non_finite_predictions
    ##         <int>             <int>                 <int>                    <int>
    ## 1         154                 0                     0                        0
    ## # ℹ 3 more variables: mean_prediction <dbl>, min_prediction <dbl>,
    ## #   max_prediction <dbl>

Note: The coefficient estimates, AIC, and theta reported below are from
the illustrative fit at the first test forecast origin. The final
forecasting evaluation is based on the rolling-origin expanding-window
procedure, in which the model is re-selected and refitted at each
forecast origin.

***Interpretation***

The model generated 154 forecasts, with 0 missing actual values, 0
missing predictions, and 0 non-finite predictions. Predicted incidence
ranged from 0.044 to 168.025 per 100,000 population, with a mean of
14.045. At each forecast origin, AIC was used to select the
autoregressive lag structure and Fourier terms from the candidate
specifications, using the available training data.

## Model 4 — Negative Binomial GLM (Oblig + Sentinella)

This model uses the same candidate autoregressive lag structures and
Fourier terms as Model 3, while additionally selecting between
`sent_log_origin` and `sent_log_prev1`. Model selection is performed
separately within each expanding training window using AIC, without
using information from the future test period.

    ## # A tibble: 154 × 10
    ##    origin_week target_week target_season actual prediction n_train selected_AR
    ##    <chr>       <chr>       <chr>          <dbl>      <dbl>   <int> <chr>      
    ##  1 2023-W39    2023-W40    2023/24        0.178     0.0542     553 AR4        
    ##  2 2023-W40    2023-W41    2023/24        0.167     0.0796     554 AR4        
    ##  3 2023-W41    2023-W42    2023/24        0.268     0.101      555 AR4        
    ##  4 2023-W42    2023-W43    2023/24        0.268     0.157      556 AR4        
    ##  5 2023-W43    2023-W44    2023/24        0.435     0.195      557 AR4        
    ##  6 2023-W44    2023-W45    2023/24        0.658     0.292      558 AR4        
    ##  7 2023-W45    2023-W46    2023/24        0.748     0.606      559 AR4        
    ##  8 2023-W46    2023-W47    2023/24        0.904     0.692      560 AR4        
    ##  9 2023-W47    2023-W48    2023/24        1.70      1.07       561 AR4        
    ## 10 2023-W48    2023-W49    2023/24        3.53      3.09       562 AR4        
    ##    selected_Fourier selected_Sentinella selected_AIC
    ##    <chr>            <chr>                      <dbl>
    ##  1 K3               sent_log_origin            4416.
    ##  2 K3               sent_log_origin            4424.
    ##  3 K3               sent_log_origin            4434.
    ##  4 K3               sent_log_origin            4442.
    ##  5 K3               sent_log_origin            4451.
    ##  6 K3               sent_log_origin            4460.
    ##  7 K3               sent_log_origin            4470.
    ##  8 K3               sent_log_origin            4481.
    ##  9 K3               sent_log_origin            4491.
    ## 10 K3               sent_log_origin            4501.
    ## # ℹ 144 more rows

    ## # A tibble: 1 × 7
    ##   n_forecasts n_missing_actuals n_missing_predictions n_non_finite_predictions
    ##         <int>             <int>                 <int>                    <int>
    ## 1         154                 0                     0                        0
    ## # ℹ 3 more variables: mean_prediction <dbl>, min_prediction <dbl>,
    ## #   max_prediction <dbl>

    ## # A tibble: 1 × 4
    ##   selected_AR selected_Fourier selected_Sentinella n_forecasts
    ##   <chr>       <chr>            <chr>                     <int>
    ## 1 AR4         K3               sent_log_origin             154

Note: The coefficient estimates, AIC, and theta reported below are from
the illustrative fit at the first test forecast origin. The final
forecasting evaluation is based on the rolling-origin expanding-window
procedure, in which the model is re-selected and refitted at each
forecast origin.

***Interpretation***

The model generated 154 forecasts, with 0 missing actual values, 0
missing predictions, and 0 non-finite predictions. Predicted incidence
ranged from 0.048 to 129.679 per 100,000 population, with a mean of
10.358. At each forecast origin, AIC was used to select the
autoregressive lag structure, the number of Fourier terms, and the
Sentinella predictor from the candidate specifications, using only the
available training data.

## Model 5 — Gradient Boosting

At each forecast origin, the AIC-based selection procedure used in Model
4 is applied first. The selected predictor set is then used to fit the
Gradient Boosting model. Unlike Model 4, which models case counts using
a negative binomial GLM with a population offset, Model 5 directly
predicts `target_oblig_inc_100k`. This allows the two modelling
approaches to be compared while keeping predictor selection consistent.

    ## # A tibble: 154 × 10
    ##    origin_week target_week target_season actual prediction n_train selected_AR
    ##    <chr>       <chr>       <chr>          <dbl>      <dbl>   <int> <chr>      
    ##  1 2023-W39    2023-W40    2023/24        0.178      0.126     553 AR4        
    ##  2 2023-W40    2023-W41    2023/24        0.167      0.126     554 AR4        
    ##  3 2023-W41    2023-W42    2023/24        0.268      0.125     555 AR4        
    ##  4 2023-W42    2023-W43    2023/24        0.268      0.166     556 AR4        
    ##  5 2023-W43    2023-W44    2023/24        0.435      0.249     557 AR4        
    ##  6 2023-W44    2023-W45    2023/24        0.658      0.322     558 AR4        
    ##  7 2023-W45    2023-W46    2023/24        0.748      0.541     559 AR4        
    ##  8 2023-W46    2023-W47    2023/24        0.904      0.721     560 AR4        
    ##  9 2023-W47    2023-W48    2023/24        1.70       1.08      561 AR4        
    ## 10 2023-W48    2023-W49    2023/24        3.53       1.87      562 AR4        
    ##    selected_Fourier selected_Sentinella selected_AIC
    ##    <chr>            <chr>                      <dbl>
    ##  1 K3               sent_log_origin            4416.
    ##  2 K3               sent_log_origin            4424.
    ##  3 K3               sent_log_origin            4434.
    ##  4 K3               sent_log_origin            4442.
    ##  5 K3               sent_log_origin            4451.
    ##  6 K3               sent_log_origin            4460.
    ##  7 K3               sent_log_origin            4470.
    ##  8 K3               sent_log_origin            4481.
    ##  9 K3               sent_log_origin            4491.
    ## 10 K3               sent_log_origin            4501.
    ## # ℹ 144 more rows

    ## # A tibble: 1 × 7
    ##   n_forecasts n_missing_actuals n_missing_predictions n_non_finite_predictions
    ##         <int>             <int>                 <int>                    <int>
    ## 1         154                 0                     0                        0
    ## # ℹ 3 more variables: mean_prediction <dbl>, min_prediction <dbl>,
    ## #   max_prediction <dbl>

***Interpretation***

The model generated 154 forecasts, with 0 missing actual values, 0
missing predictions, and 0 non-finite predictions. Predicted incidence
ranged from 0.125 to 31.712 per 100,000 population, with a mean of
4.787. At each forecast origin, the predictor set selected by the
AIC-based procedure used in Model 4 was used to fit the Gradient
Boosting model.

## Model 6 — Sensitivity analysis for COVID and post-2020 indicators

### Model 6a: NB GLM from Model 4 + COVID-season indicator 

### Model 6b: NB GLM from Model 4 + post2020 level-shift indicator 

    ## Model 6a rows: 154

    ## Model 6b rows: 154

    ## # A tibble: 3 × 2
    ##   target_season     n
    ##   <chr>         <int>
    ## 1 2023/24          52
    ## 2 2024/25          52
    ## 3 2025/26          50

    ## # A tibble: 3 × 2
    ##   target_season     n
    ##   <chr>         <int>
    ## 1 2023/24          52
    ## 2 2024/25          52
    ## 3 2025/26          50

    ##      Min.   1st Qu.    Median      Mean   3rd Qu.      Max. 
    ##   0.05236   0.09487   0.25910  10.96192   4.28872 136.51931

    ##      Min.   1st Qu.    Median      Mean   3rd Qu.      Max. 
    ##   0.07515   0.12930   0.39849  14.62018   7.11373 152.03322

***Interpretation***

The model Model 6a generated 154 forecasts across 3 test seasons. The
number of forecasts by season was 2023/24: 52; 2024/25: 52; 2025/26: 50.
Predicted incidence ranged from 0.052 to 136.519 per 100,000 population,
with a mean of 10.962. This sensitivity model extends Model 4 by
including a COVID-season indicator to assess whether accounting for the
COVID seasons affects predictive performance.

The model Model 6b generated 154 forecasts across 3 test seasons. The
number of forecasts by season was 2023/24: 52; 2024/25: 52; 2025/26: 50.
Predicted incidence ranged from 0.075 to 152.033 per 100,000 population,
with a mean of 14.62. This sensitivity model extends Model 4 by
including a post-2020 indicator to assess whether accounting for the
period from the 2022/23 season onward affects predictive performance.

**Negative Binomial Model Diagnostics**

    ## # A tibble: 1 × 13
    ##   target_week model origin_week target_week_start target_season target_in_season
    ##   <chr>       <chr> <chr>       <date>            <chr>         <lgl>           
    ## 1 2023-W40    Mode… 2023-W39    2023-10-02        2023/24       FALSE           
    ## # ℹ 7 more variables: actual <dbl>, prediction <dbl>, n_train <int>,
    ## #   selected_AR <chr>, selected_Fourier <chr>, selected_Sentinella <chr>,
    ## #   selected_AIC <dbl>

    ## [1] 1

    ##  [1] "2023-W40" "2023-W41" "2023-W42" "2023-W43" "2023-W44" "2023-W45"
    ##  [7] "2023-W46" "2023-W47" "2023-W48" "2023-W49"

    ##  [1] "2013-W02" "2013-W03" "2013-W04" "2013-W05" "2013-W06" "2013-W07"
    ##  [7] "2013-W08" "2013-W09" "2013-W10" "2013-W11"

    ## # A tibble: 1 × 3
    ##   target_week week_start target_week_start
    ##   <chr>       <date>     <date>           
    ## 1 2023-W40    2023-09-25 2023-10-02

    ## # A tibble: 4 × 7
    ##   model    n_fits n_not_converged n_fits_with_warnings n_fit_errors max_theta
    ##   <chr>     <int>           <int>                <int>        <int>     <dbl>
    ## 1 Model 3     154               0                    0            0      1.18
    ## 2 Model 4     154               0                    0            0      1.47
    ## 3 Model 6a    154               0                    0            0      1.54
    ## 4 Model 6b    154               0                    0            0      1.72
    ## # ℹ 1 more variable: median_pearson_dispersion <dbl>

    ## # A tibble: 0 × 7
    ## # ℹ 7 variables: model <chr>, target_week <chr>, theta <dbl>, converged <lgl>, pearson_dispersion <dbl>, warnings <chr>, fit_error <chr>

***Negative binomial model convergence diagnostics***

Convergence diagnostics were performed for the selected negative
binomial models across the expanding-window evaluation. Across 4 models,
a total of 616 fits were assessed, with 154 to 154 fits per model. No
non-converged fits, recorded fitting warnings, or fitting errors were
detected.

The maximum estimated dispersion parameter ($\theta$) across the models
ranged from 1.18 to 1.72, while the median Pearson dispersion ratios
ranged from 0.785 to 0.96. These results indicate no detected numerical
convergence problems in the evaluated model fits. However, they do not
establish overall model adequacy or predictive superiority.

# 4 Validate the models

    ## Forecast integrity checks passed for all seven models.

    ## Number of common valid target weeks: 154

    ## # A tibble: 3 × 2
    ##   target_season n_common_weeks
    ##   <chr>                  <int>
    ## 1 2023/24                   52
    ## 2 2024/25                   52
    ## 3 2025/26                   50

    ## # A tibble: 14 × 7
    ##    evaluation model                                  n   MAE  RMSE naive_MAE
    ##    <chr>      <chr>                              <int> <dbl> <dbl>     <dbl>
    ##  1 All weeks  Model 5: Gradient Boosting           154  1.14  2.51      1.31
    ##  2 All weeks  Model 1: Naive                       154  1.31  2.48      1.31
    ##  3 All weeks  Model 2: Seasonal naive              154  3.17  6.44      1.31
    ##  4 All weeks  Model 4: NB Oblig + Sentinella       154  5.61 16.1       1.31
    ##  5 All weeks  Model 6a: NB + COVID indicator       154  6.15 17.8       1.31
    ##  6 All weeks  Model 3: NB Oblig-only               154  9.28 25.1       1.31
    ##  7 All weeks  Model 6b: NB + post-2020 indicator   154  9.59 24.6       1.31
    ##  8 In-season  Model 5: Gradient Boosting            35  3.81  5.07      4.06
    ##  9 In-season  Model 1: Naive                        35  4.06  4.69      4.06
    ## 10 In-season  Model 2: Seasonal naive               35 10.2  12.5       4.06
    ## 11 In-season  Model 4: NB Oblig + Sentinella        35 23.2  33.7       4.06
    ## 12 In-season  Model 6a: NB + COVID indicator        35 25.6  37.1       4.06
    ## 13 In-season  Model 3: NB Oblig-only                35 38.4  52.4       4.06
    ## 14 In-season  Model 6b: NB + post-2020 indicator    35 39.5  51.3       4.06
    ##    MAE_skill
    ##        <dbl>
    ##  1    0.131 
    ##  2    0     
    ##  3   -1.42  
    ##  4   -3.28  
    ##  5   -3.69  
    ##  6   -6.09  
    ##  7   -6.33  
    ##  8    0.0629
    ##  9    0     
    ## 10   -1.52  
    ## 11   -4.70  
    ## 12   -5.29  
    ## 13   -8.44  
    ## 14   -8.72

    ## # A tibble: 42 × 8
    ##    evaluation target_season model                                  n   MAE  RMSE
    ##    <chr>      <chr>         <chr>                              <int> <dbl> <dbl>
    ##  1 All weeks  2023/24       Model 5: Gradient Boosting            52  1.04  2.11
    ##  2 All weeks  2023/24       Model 1: Naive                        52  1.09  2.05
    ##  3 All weeks  2023/24       Model 4: NB Oblig + Sentinella        52  2.92  8.63
    ##  4 All weeks  2023/24       Model 6a: NB + COVID indicator        52  3.03  9.04
    ##  5 All weeks  2023/24       Model 2: Seasonal naive               52  3.65  7.89
    ##  6 All weeks  2023/24       Model 6b: NB + post-2020 indicator    52  6.82 17.6 
    ##  7 All weeks  2023/24       Model 3: NB Oblig-only                52  6.89 19.7 
    ##  8 All weeks  2024/25       Model 5: Gradient Boosting            52  1.28  3.13
    ##  9 All weeks  2024/25       Model 1: Naive                        52  1.38  2.51
    ## 10 All weeks  2024/25       Model 2: Seasonal naive               52  1.90  3.56
    ## 11 All weeks  2024/25       Model 4: NB Oblig + Sentinella        52  6.55 16.8 
    ## 12 All weeks  2024/25       Model 6a: NB + COVID indicator        52  7.45 19.2 
    ## 13 All weeks  2024/25       Model 3: NB Oblig-only                52 10.4  26.1 
    ## 14 All weeks  2024/25       Model 6b: NB + post-2020 indicator    52 11.7  28.0 
    ## 15 All weeks  2025/26       Model 5: Gradient Boosting            50  1.09  2.15
    ## 16 All weeks  2025/26       Model 1: Naive                        50  1.47  2.84
    ## 17 All weeks  2025/26       Model 2: Seasonal naive               50  3.99  7.06
    ## 18 All weeks  2025/26       Model 4: NB Oblig + Sentinella        50  7.41 20.8 
    ## 19 All weeks  2025/26       Model 6a: NB + COVID indicator        50  8.03 22.5 
    ## 20 All weeks  2025/26       Model 6b: NB + post-2020 indicator    50 10.2  27.0 
    ## 21 All weeks  2025/26       Model 3: NB Oblig-only                50 10.6  28.8 
    ## 22 In-season  2023/24       Model 1: Naive                        14  3.03  3.63
    ## 23 In-season  2023/24       Model 5: Gradient Boosting            14  3.05  3.91
    ## 24 In-season  2023/24       Model 4: NB Oblig + Sentinella        14 10.1  16.6 
    ## 25 In-season  2023/24       Model 6a: NB + COVID indicator        14 10.5  17.4 
    ## 26 In-season  2023/24       Model 2: Seasonal naive               14 11.6  15.0 
    ## 27 In-season  2023/24       Model 6b: NB + post-2020 indicator    14 23.8  33.8 
    ## 28 In-season  2023/24       Model 3: NB Oblig-only                14 24.0  37.8 
    ## 29 In-season  2024/25       Model 1: Naive                        11  4.18  4.68
    ## 30 In-season  2024/25       Model 5: Gradient Boosting            11  4.70  6.62
    ## 31 In-season  2024/25       Model 2: Seasonal naive               11  7.14  7.50
    ## 32 In-season  2024/25       Model 4: NB Oblig + Sentinella        11 28.6  36.2 
    ## 33 In-season  2024/25       Model 6a: NB + COVID indicator        11 32.9  41.4 
    ## 34 In-season  2024/25       Model 3: NB Oblig-only                11 45.3  56.0 
    ## 35 In-season  2024/25       Model 6b: NB + post-2020 indicator    11 50.9  60.0 
    ## 36 In-season  2025/26       Model 5: Gradient Boosting            10  3.89  4.50
    ## 37 In-season  2025/26       Model 1: Naive                        10  5.38  5.88
    ## 38 In-season  2025/26       Model 2: Seasonal naive               10 11.8  13.0 
    ## 39 In-season  2025/26       Model 4: NB Oblig + Sentinella        10 35.5  46.4 
    ## 40 In-season  2025/26       Model 6a: NB + COVID indicator        10 38.6  50.2 
    ## 41 In-season  2025/26       Model 6b: NB + post-2020 indicator    10 49.0  60.3 
    ## 42 In-season  2025/26       Model 3: NB Oblig-only                10 50.8  64.4 
    ##    naive_MAE MAE_skill
    ##        <dbl>     <dbl>
    ##  1      1.09   0.0394 
    ##  2      1.09   0      
    ##  3      1.09  -1.69   
    ##  4      1.09  -1.79   
    ##  5      1.09  -2.37   
    ##  6      1.09  -5.28   
    ##  7      1.09  -5.35   
    ##  8      1.38   0.0734 
    ##  9      1.38   0      
    ## 10      1.38  -0.379  
    ## 11      1.38  -3.75   
    ## 12      1.38  -4.40   
    ## 13      1.38  -6.55   
    ## 14      1.38  -7.51   
    ## 15      1.47   0.257  
    ## 16      1.47   0      
    ## 17      1.47  -1.72   
    ## 18      1.47  -4.05   
    ## 19      1.47  -4.46   
    ## 20      1.47  -5.97   
    ## 21      1.47  -6.21   
    ## 22      3.03   0      
    ## 23      3.03  -0.00689
    ## 24      3.03  -2.33   
    ## 25      3.03  -2.48   
    ## 26      3.03  -2.82   
    ## 27      3.03  -6.85   
    ## 28      3.03  -6.92   
    ## 29      4.18   0      
    ## 30      4.18  -0.123  
    ## 31      4.18  -0.707  
    ## 32      4.18  -5.83   
    ## 33      4.18  -6.86   
    ## 34      4.18  -9.83   
    ## 35      4.18 -11.2    
    ## 36      5.38   0.277  
    ## 37      5.38   0      
    ## 38      5.38  -1.19   
    ## 39      5.38  -5.60   
    ## 40      5.38  -6.17   
    ## 41      5.38  -8.10   
    ## 42      5.38  -8.45

***Interpretation of Model Validation***

All seven models were evaluated on 154 common valid target weeks across
the three test seasons: 2023/24 (52 weeks), 2024/25 (52 weeks), 2025/26
(50 weeks). The evaluation dataset contained no missing or non-finite
actual outcomes or predictions.

**Overall performance.** Across all weeks, Model 5: Gradient Boosting
achieved the lowest MAE (1.14 per 100,000 population), compared with
1.31 for the naive baseline. The MAE skill of the model with the lowest
MAE was 0.131 relative to the naive baseline. However, the naive
baseline achieved a slightly lower overall RMSE (2.48) than Gradient
Boosting (2.51), indicating that the relative ranking depends on the
evaluation metric.

**In-season performance.** During in-season weeks, Model 5: Gradient
Boosting achieved the lowest MAE (3.81 per 100,000 population). Gradient
Boosting had an MAE of 3.81, compared with 4.06 for the naive baseline.
The naive baseline achieved an in-season RMSE of 4.69, compared with
5.07 for Gradient Boosting.

Season-specific results should also be considered because performance
varied across test seasons. Gradient Boosting achieved the lowest
overall MAE in each of the three test seasons, but its in-season
advantage was not consistent across seasons. Therefore, the results
support Gradient Boosting as a strong candidate based on MAE, but do not
establish that it is uniformly superior across all metrics and
evaluation periods.

# 5 Plot the results

## Figure 1: Overall MAE Comparison

![](figures/04_fig_1-1.png)<!-- -->

Across the seven models, Model 5: Gradient Boosting achieved the lowest
overall MAE of 1.14 per 100,000 population. This was lower than the
naive baseline (Model 1), which had an MAE of 1.31. The MAE skill score
of the model with the lowest MAE was 0.131, indicating its relative
improvement in MAE over the naive baseline.

However, the naive model achieved a slightly lower RMSE (2.48) than
Gradient Boosting (2.51). Thus, Gradient Boosting performed best in
terms of average absolute error, but did not minimize every error
metric. The negative binomial models had higher overall MAE than the two
simple baselines and Gradient Boosting.

## Figure 2: MAE by Test Season

![](figures/04_fig_2-1.png)<!-- -->

Model performance varied across the three test seasons. Gradient
Boosting achieved the lowest all-week MAE in 3 test seasons out of 3.
This suggests that its advantage in overall MAE was observed across
multiple test seasons.

Nevertheless, the relative performance differed when the evaluation was
restricted to in-season weeks. The naive baseline achieved a lower
in-season MAE than Gradient Boosting in 2 of the 3 test seasons.
Therefore, although Gradient Boosting performed well in terms of overall
MAE, its advantage during periods of influenza activity was not
consistent across all seasons. This seasonal variation supports
reporting both overall and in-season metrics.

## Figure 3: Actual vs. Predicted Influenza Incidence

![](figures/04_fig_3-1.png)<!-- -->

Figure 3 compares actual and predicted influenza incidence during the
peak period (ISO weeks 48–16) across the three test seasons.

The naive baseline (Model 1) generally follows the observed changes in
incidence, although its predictions may appear to lag behind rapid
changes in influenza activity. Gradient Boosting (Model 5) produces
relatively smooth predictions and visually follows the overall patterns
shown in the peak-period plots. In contrast, the predictions from Models
3, 4, 6a and 6b show pronounced peaks above the observed incidence in
some test seasons, suggesting possible overestimation of peak activity.
The seasonal naive model (Model 2) also shows varying agreement with the
observed incidence across seasons.

These visual observations can be considered alongside the quantitative
evaluation across all common test weeks. Gradient Boosting achieved the
lowest overall MAE (1.14 per 100,000 population), compared with 1.31 for
the naive baseline. However, the naive baseline had a slightly lower
overall RMSE (2.48) than Gradient Boosting (2.51), indicating that their
relative performance depends on the error metric.

Overall, Figure 3 provides a visual comparison of model predictions
during the peak period, while the evaluation metrics quantify
performance across the full set of common test weeks. Gradient Boosting
performed best in terms of overall MAE, but the visual comparison and
RMSE results do not establish that it is uniformly superior across all
evaluation criteria. Both quantitative metrics and variation across test
seasons should therefore be considered when assessing predictive
performance.

# 6 Conclusion

This study evaluated seven forecasting models for predicting weekly
influenza incidence in Switzerland using an expanding-window evaluation
across three test seasons (2023/24, 2024/25 and 2025/26). Model
performance was assessed using MAE and RMSE, with additional evaluation
during in-season weeks.

Overall, **Model 5: Gradient Boosting was the best-performing model in
terms of overall MAE**, achieving an MAE of 1.14 per 100,000 population.
This was lower than the naive baseline’s MAE of 1.31, corresponding to
an MAE skill score of 0.131 relative to the naive baseline. Gradient
Boosting also achieved the lowest all-week MAE in 3 of the three test
seasons.

However, the naive baseline achieved a slightly lower overall RMSE
(2.48) than Gradient Boosting (2.51). During in-season weeks, Gradient
Boosting achieved an MAE of 3.81, compared with 4.06 for the naive
baseline. Its advantage during in-season periods was not consistent
across all three test seasons.

The negative binomial models, including those incorporating Sentinella
information or COVID-related indicators, did not outperform the naive
baseline in overall MAE in this evaluation. Thus, adding these
predictors and model components did not translate into improved
predictive accuracy under the current modelling and evaluation setup.

In conclusion, Gradient Boosting is the preferred model when the primary
selection criterion is overall MAE, while the naive baseline remains a
competitive and simpler benchmark, particularly when considering RMSE
and season-specific in-season performance. These findings support
selecting Gradient Boosting as the leading candidate for further
evaluation rather than claiming that it is universally superior. The
conclusions are limited to the three evaluated test seasons and the
current model specifications.
