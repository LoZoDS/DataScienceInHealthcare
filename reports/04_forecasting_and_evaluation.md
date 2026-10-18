WP 4.4 & 4.5 – Forecasting and evaluation
================
Q. Xu (responsible), H. Wang (feedback)
17 Oktober 2026

- [1 Load data](#1-load-data)
- [2 Build the forecasting dataset](#2-build-the-forecasting-dataset)
- [3 Define the forecasting models](#3-define-the-forecasting-models)
- [4 Validate the models](#4-validate-the-models)
  - [Interpretation of Model
    Validation](#interpretation-of-model-validation)
  - [Evaluation of H2](#evaluation-of-h2)
- [5 Plot the results](#5-plot-the-results)

**Objective:**

Forecast next-week influenza incidence and assess whether Sentinella
improves prediction beyond mandatory reporting (Oblig).

**Evaluation strategy：**

- Expanding-window, rolling-origin evaluation across three test seasons
  (2023/24–2025/26).  

- Metrics: MAE and RMSE, overall and during influenza weeks.  

- MAE skill score:  

  $$\text{MAE skill}=1-\frac{\text{MAE}_{\text{model}}}{\text{MAE}_{\text{naive}}}$$
  Positive values indicate lower MAE than the naive baseline, a value of
  zero indicates equal performance, and negative values indicate higher
  MAE than the naive baseline.

**Key comparison:** M3 vs. M4 isolates the incremental predictive value
of Sentinella.

# 1 Load data

The processed national dataset contains weekly influenza surveillance
data from Oblig and Sentinella.  
The in-season classification identifies the weeks considered part of the
influenza season.

# 2 Build the forecasting dataset

Purpose : Define the forecast origin, next-week target, lagged
predictors, target-week seasonality, and predictor sets for all
forecasting models.

    ## # A tibble: 1 × 1
    ##   missing_model_predictors
    ##                      <int>
    ## 1                        9

    ## Number of rows: 715

    ## # A tibble: 1 × 6
    ##   missing_target_incidence missing_target_cases missing_target_population
    ##                      <int>                <int>                     <int>
    ## 1                        1                    1                         1
    ## # ℹ 3 more variables: missing_oblig_lag1 <int>, missing_sentinella_lag1 <int>,
    ## #   missing_model_predictors <int>

    ## # A tibble: 6 × 3
    ##   target_season target_in_season     n
    ##   <chr>         <lgl>            <int>
    ## 1 2023/24       FALSE               38
    ## 2 2023/24       TRUE                14
    ## 3 2024/25       FALSE               41
    ## 4 2024/25       TRUE                11
    ## 5 2025/26       FALSE               40
    ## 6 2025/26       TRUE                10

# 3 Define the forecasting models

We deliberately simplified Models 3 and 4 to keep the negative binomial
models parsimonious and interpretable, while focusing on the incremental
predictive value of Sentinella data. Model 3 uses the most recent Oblig
incidence, and Model 4 adds the most recent Sentinella information. We
retained Fourier terms and additional lags in the more flexible Gradient
Boosting model to capture potentially more complex temporal patterns.
This was a modelling choice, not a conclusion that Fourier terms were
ineffective.

**Model 1 — Naive baseline**

Purpose: Use the most recent assumed-available Oblig incidence to
forecast next week’s incidence.

| n_forecasts | n_missing_predictions | mean_prediction | min_prediction | max_prediction |
|---:|---:|---:|---:|---:|
| 154 | 0 | 5.177 | 0.055 | 36.452 |

Model 1: Naive baseline output

***Interpretation***

The model generated 154 forecasts with no missing predictions. Predicted
incidence ranged from 0.055 to 36.452 per 100,000, with a mean of 5.177.
This baseline assumes that next week’s incidence will equal the most
recently observed incidence.

**Model 2 — Seasonal naive**

Purpose: Use the incidence from the corresponding week in the previous
season as a seasonal benchmark.

| n_forecasts | n_missing_predictions | mean_prediction | min_prediction | max_prediction |
|---:|---:|---:|---:|---:|
| 154 | 0 | 5.233 | 0.045 | 42.812 |

Model 2: Seasonal naive output

***Interpretation***

The model generated 154 forecasts with no missing predictions. Predicted
incidence ranged from 0.045 to 42.812 per 100,000, with a mean of 5.233.
It uses the incidence from approximately the same week in the previous
year as a seasonal benchmark.

**Model 3 — Negative Binomial GLM (Oblig-only)**

Purpose: Predict next week’s Oblig cases using the previous week’s Oblig
incidence, without Fourier seasonal terms.

    ##                  Estimate  Std. Error    z value Pr(>|z|)
    ## (Intercept)    -12.781949 0.007872896 -1623.5385        0
    ## oblig_log_lag1   1.421192 0.003077527   461.7968        0

    ## AIC: 36807.62

    ## Theta: 2236828

***Interpretation***

Lagged Oblig incidence was positively associated with the expected
influenza case count (β = 1.421, p \< 0.001). The model’s AIC was
36,807.62. The very large estimated theta (2,236,828) indicates that the
fitted negative binomial distribution is close to the Poisson limit.

**Model 4 — Negative Binomial GLM (Oblig + Sentinella)**

Purpose: Predict next week’s Oblig cases using the previous week’s Oblig
incidence and Sentinella ILI activity.

    ##                   Estimate  Std. Error     z value Pr(>|z|)
    ## (Intercept)    -13.2030649 0.012801233 -1031.39009        0
    ## oblig_log_lag1   1.2302950 0.005104515   241.02096        0
    ## sent_log_lag1    0.2825915 0.006174046    45.77088        0

    ## AIC: 34530.54

    ## Theta: 2328368

***Interpretation***

Both lagged Oblig incidence (β = 1.230, p \< 0.001) and lagged
Sentinella activity (β = 0.283, p \< 0.001) were positively associated
with the expected case count. Model 4 had a lower AIC (34,530.54) than
Model 3 (36,807.62), indicating a better fit after accounting for model
complexity. However, out-of-sample performance must be assessed
separately. The very large estimated theta (2,328,368) indicates that
the fitted negative binomial distribution is close to the Poisson limit.

**Model 5 — Gradient Boosting (Oblig + Sentinella)**

Purpose: Provide a nonlinear robustness check using the same Oblig and
Sentinella lagged predictors and seasonal terms.

![](figures/04_model%205-1.png)<!-- -->

<div class="kable-table">

|                | var            |    rel.inf |
|:---------------|:---------------|-----------:|
| oblig_log_lag1 | oblig_log_lag1 | 91.6396902 |
| sent_log_lag3  | sent_log_lag3  |  1.9980026 |
| sin1           | sin1           |  1.9066651 |
| sent_log_lag4  | sent_log_lag4  |  1.6524695 |
| cos1           | cos1           |  0.9024849 |
| sent_log_lag2  | sent_log_lag2  |  0.7060018 |
| cos2           | cos2           |  0.5018290 |
| sent_log_lag1  | sent_log_lag1  |  0.3479506 |
| sin2           | sin2           |  0.3449061 |

</div>

***Interpretation***

Lagged Oblig incidence (`oblig_log_lag1`) dominated the model’s relative
influence (91.64%). The remaining predictors, including lagged
Sentinella variables and Fourier terms, had much smaller relative
influence. The Fourier terms capture seasonal patterns. These importance
scores reflect the model’s use of predictors, not causal effects or
guaranteed improvements in forecast accuracy.

**Rolling-origin expanding-window forecasts**

This function fits Models 3 and 4 using Negative Binomial GLM, or Model
5 using Gradient Boosting. It restricts training targets to weeks ending
at least one week before the forecast origin, uses the same
complete-case training rows, and converts predicted counts into
incidence per 100,000.

# 4 Validate the models

    ## # A tibble: 3 × 2
    ##   target_season n_common_weeks
    ##   <chr>                  <int>
    ## 1 2023/24                   52
    ## 2 2024/25                   52
    ## 3 2025/26                   50

    ## # A tibble: 10 × 7
    ##    evaluation model                              n   MAE  RMSE naive_MAE
    ##    <chr>      <chr>                          <int> <dbl> <dbl>     <dbl>
    ##  1 All weeks  Model 5: Gradient Boosting       154  1.13  2.39      1.31
    ##  2 All weeks  Model 1: Naive                   154  1.31  2.48      1.31
    ##  3 All weeks  Model 4: NB Oblig + Sentinella   154  1.60  3.35      1.31
    ##  4 All weeks  Model 3: NB Oblig-only           154  1.70  3.44      1.31
    ##  5 All weeks  Model 2: Seasonal naive          154  3.17  6.44      1.31
    ##  6 In-season  Model 5: Gradient Boosting        35  3.58  4.66      4.06
    ##  7 In-season  Model 1: Naive                    35  4.06  4.69      4.06
    ##  8 In-season  Model 4: NB Oblig + Sentinella    35  5.43  6.63      4.06
    ##  9 In-season  Model 3: NB Oblig-only            35  5.80  6.87      4.06
    ## 10 In-season  Model 2: Seasonal naive           35 10.2  12.5       4.06
    ##    MAE_skill
    ##        <dbl>
    ##  1     0.138
    ##  2     0    
    ##  3    -0.220
    ##  4    -0.299
    ##  5    -1.42 
    ##  6     0.119
    ##  7     0    
    ##  8    -0.336
    ##  9    -0.427
    ## 10    -1.52

    ## # A tibble: 30 × 8
    ##    evaluation target_season model                              n    MAE  RMSE
    ##    <chr>      <chr>         <chr>                          <int>  <dbl> <dbl>
    ##  1 All weeks  2023/24       Model 5: Gradient Boosting        52  0.995  2.03
    ##  2 All weeks  2023/24       Model 1: Naive                    52  1.09   2.05
    ##  3 All weeks  2023/24       Model 4: NB Oblig + Sentinella    52  1.13   2.33
    ##  4 All weeks  2023/24       Model 3: NB Oblig-only            52  1.32   2.60
    ##  5 All weeks  2023/24       Model 2: Seasonal naive           52  3.65   7.89
    ##  6 All weeks  2024/25       Model 5: Gradient Boosting        52  1.16   2.70
    ##  7 All weeks  2024/25       Model 1: Naive                    52  1.38   2.51
    ##  8 All weeks  2024/25       Model 3: NB Oblig-only            52  1.86   3.71
    ##  9 All weeks  2024/25       Model 2: Seasonal naive           52  1.90   3.56
    ## 10 All weeks  2024/25       Model 4: NB Oblig + Sentinella    52  1.92   3.94
    ## 11 All weeks  2025/26       Model 5: Gradient Boosting        50  1.24   2.39
    ## 12 All weeks  2025/26       Model 1: Naive                    50  1.47   2.84
    ## 13 All weeks  2025/26       Model 4: NB Oblig + Sentinella    50  1.75   3.56
    ## 14 All weeks  2025/26       Model 3: NB Oblig-only            50  1.93   3.90
    ## 15 All weeks  2025/26       Model 2: Seasonal naive           50  3.99   7.06
    ## 16 In-season  2023/24       Model 5: Gradient Boosting        14  2.51   3.42
    ## 17 In-season  2023/24       Model 1: Naive                    14  3.03   3.63
    ## 18 In-season  2023/24       Model 4: NB Oblig + Sentinella    14  3.63   4.42
    ## 19 In-season  2023/24       Model 3: NB Oblig-only            14  4.18   4.89
    ## 20 In-season  2023/24       Model 2: Seasonal naive           14 11.6   15.0 
    ## 21 In-season  2024/25       Model 5: Gradient Boosting        11  4.18   5.67
    ## 22 In-season  2024/25       Model 1: Naive                    11  4.18   4.68
    ## 23 In-season  2024/25       Model 3: NB Oblig-only            11  6.18   7.37
    ## 24 In-season  2024/25       Model 4: NB Oblig + Sentinella    11  6.38   7.77
    ## 25 In-season  2024/25       Model 2: Seasonal naive           11  7.14   7.50
    ## 26 In-season  2025/26       Model 5: Gradient Boosting        10  4.42   4.94
    ## 27 In-season  2025/26       Model 1: Naive                    10  5.38   5.88
    ## 28 In-season  2025/26       Model 4: NB Oblig + Sentinella    10  6.91   7.74
    ## 29 In-season  2025/26       Model 3: NB Oblig-only            10  7.65   8.49
    ## 30 In-season  2025/26       Model 2: Seasonal naive           10 11.8   13.0 
    ##    naive_MAE MAE_skill
    ##        <dbl>     <dbl>
    ##  1      1.09  0.0828  
    ##  2      1.09  0       
    ##  3      1.09 -0.0411  
    ##  4      1.09 -0.215   
    ##  5      1.09 -2.37    
    ##  6      1.38  0.160   
    ##  7      1.38  0       
    ##  8      1.38 -0.347   
    ##  9      1.38 -0.379   
    ## 10      1.38 -0.391   
    ## 11      1.47  0.158   
    ## 12      1.47  0       
    ## 13      1.47 -0.190   
    ## 14      1.47 -0.317   
    ## 15      1.47 -1.72    
    ## 16      3.03  0.172   
    ## 17      3.03  0       
    ## 18      3.03 -0.198   
    ## 19      3.03 -0.379   
    ## 20      3.03 -2.82    
    ## 21      4.18  0.000830
    ## 22      4.18  0       
    ## 23      4.18 -0.477   
    ## 24      4.18 -0.525   
    ## 25      4.18 -0.707   
    ## 26      5.38  0.179   
    ## 27      5.38  0       
    ## 28      5.38 -0.284   
    ## 29      5.38 -0.422   
    ## 30      5.38 -1.19

    ## Diebold-Mariano test: Model 3 vs Model 4

    ## Number of paired forecasts: 154

    ## Model 3 MAE: 1.701179

    ## Model 4 MAE: 1.596872

    ## Relative MAE reduction (%): 6.131491

    ## 
    ##  Diebold-Mariano Test
    ## 
    ## data:  error_m3error_m4
    ## DM = 1.6276, Forecast horizon = 1, Loss function power = 1, p-value =
    ## 0.1057
    ## alternative hypothesis: two.sided

## Interpretation of Model Validation

The five forecasting models were evaluated using expanding-window,
rolling-origin validation on 154 common target weeks across three test
seasons (2023/24–2025/26). Model performance was assessed using MAE and
RMSE for all test weeks and for influenza-season weeks.

**Overall model performance.** Gradient Boosting (Model 5) achieved the
best overall performance, with an MAE of 1.13 and an RMSE of 2.39. Its
MAE was approximately 14% lower than that of the naive baseline (Model
1; MAE = 1.31). Model 5 also achieved the lowest in-season MAE (3.58,
compared with 4.06 for Model 1) and the lowest overall MAE in each of
the three test seasons. However, the in-season evaluation included only
10–14 weeks per season.

**Incremental value of Sentinella.** The negative binomial model
incorporating both Oblig and Sentinella data (Model 4) achieved a
slightly lower overall MAE than the Oblig-only model (Model 3). However,
the improvement was modest, and its consistency across test seasons
varied. The statistical significance and the extent of this improvement
are examined separately in the evaluation of H2.

**Comparison with the other benchmarks.** Neither Model 3 nor Model 4
outperformed the naive baseline (Model 1) in overall MAE. The seasonal
naive model (Model 2) had the highest overall MAE (3.17) and RMSE
(6.44), indicating that using incidence from approximately the
corresponding period of the previous year was less effective than using
the most recent available incidence in these test seasons.

Overall, Model 5 was the most accurate of the five evaluated models.
These findings describe predictive performance on the selected test
weeks and do not guarantee similar performance in future influenza
seasons.

## Evaluation of H2

H2 proposed that including lagged Sentinella indicators would reduce
out-of-sample MAE by at least 10% compared with a model based only on
historical mandatory reporting data, with the difference assessed using
the Diebold–Mariano test.

The overall MAE decreased from 1.701 for Model 3 (Oblig only) to 1.597
for Model 4 (Oblig + Sentinella), corresponding to a relative reduction
of 6.13%. Although Model 4 achieved a lower overall MAE, the improvement
did not reach the pre-specified threshold of 10%.

Performance also varied across the three test seasons. Model 4 performed
better than Model 3 in the 2023/24 and 2025/26 seasons, whereas its MAE
was slightly higher in 2024/25. This suggests that the predictive
contribution of Sentinella indicators was not consistent across seasons.

A two-sided Diebold–Mariano test based on absolute forecast errors from
the 154 paired test weeks yielded a test statistic of 1.628 and a
p-value of 0.106. The difference in predictive accuracy was not
statistically significant at the 5% significance level.

Overall, H2 was not supported: the relative MAE reduction was below the
pre-specified 10% threshold, and the Diebold–Mariano test did not
provide sufficient evidence of a statistically significant difference in
predictive accuracy between Models 3 and 4. Given the limited evaluation
period of three test seasons, these findings should be interpreted
cautiously.

# 5 Plot the results

**Figure 1: Overall MAE Comparison**

![](figures/04_unnamed-chunk-7-1.png)<!-- -->

**Figure 2: MAE by Test Season**

![](figures/04_unnamed-chunk-8-1.png)<!-- -->

**Figure 3: Actual vs. Predicted**

![](figures/04_unnamed-chunk-9-1.png)<!-- -->

**Conclusion: Model 5 (Gradient Boosting) Performs Best**

Overall, Model 5 provided the most accurate forecasts among the five
evaluated models. Its performance across the three test seasons and its
ability to capture the observed temporal patterns make it the preferred
model for forecasting weekly influenza incidence in this analysis.

The results suggest that a flexible model combining lagged surveillance
indicators with seasonal information can provide useful predictive
performance. However, the evaluation covers only three test seasons, so
the model’s performance should be reassessed as additional surveillance
data become available.

