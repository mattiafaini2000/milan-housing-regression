# Methods

The report's main model is median quantile regression, `quantreg::rq(..., tau = 0.5, na.action = na.exclude)`, on `sqm_price = log(selling_price / square_meters)`. Selling-price predictions are `exp(log_prediction) * square_meters`. Its fitted log-scale quantile loss and the original-price MAE used for selection are distinct quantities. No smearing, clipping, target rounding or alternative inverse transform is applied.

## Listing fields and preprocessing

Inputs are comma-delimited UTF-8 tables with unique `ID` values. The training table additionally supplies `selling_price`; test listings need the same raw predictor schema. Additional raw fields used by a chosen formula must be present in both tables.

| Field | Supported values and treatment |
|---|---|
| `ID` | Preserved as text. The consolidated labelled fit excludes ID `2571`; prediction preserves every requested ID. |
| `selling_price` | Positive finite observed selling prices; missing labels retain the model's NA policy. |
| `bathrooms_number` | Numeric strings, with `3+` mapped to 4; missing values use `MASS::polr` with area. |
| `rooms_number` | Numeric counts, with `5+` mapped to 6. |
| `square_meters` | Numeric area. Values below 11 and six-room observations in the literal `[11,21)` cut bin become missing; a linear model on room count imputes them. |
| `year_of_construction` | Numeric year; missing values use the fitted mean. `new` means strictly later than 2010. |
| `total_floors_in_building` | Numeric or `1 floor`; a linear model on year imputes missing values without rounding. |
| `car_parking` | Counts extracted from `N in garage/box` and `N in shared parking`; unmatched or missing text yields zero counts. |
| `availability` | `available` becomes 1; other nonmissing values become 0; missing values use the fitted mean. |
| `floor` | Numeric strings; `ground floor`, `mezzanine` and `semi-basement` become 0 with separate indicators. |
| `energy_efficiency_class` | `a` through `g` map to 1 through 7; `,` denotes missing. Ordinal imputation uses construction year. |
| `other_features` | Tokens separated by ` | `, after the two PVC/exposure text repairs. Indicators follow training frequency order. |
| `lift` | `no` becomes 1 and `yes` becomes 0. Missing values receive logistic probabilities using year and building-floor count. |
| `condominium_fees` | Numeric strings or `No condominium fees`; converted to fees per square metre, then mean-imputed. |
| `conditions` | Category strings; missing values become `excellent / refurbished`. |
| `heating_centralized` | `central` becomes 1, `independent` becomes 0; missing values become `central`. |
| `zone` | UTF-8 neighbourhood names, with the seven active ordered replacements in `config/quantile.R`. |

Engineered fields include `sqm_1`, `new`, `garage_box`, `shared_parking`, `ground`, `basement`, `mezzanine`, `ratio`, `floor_lift`, `main_zone` and the other-feature indicators. `ratio` is floor divided by total building floors; `floor_lift` multiplies the reverse-coded lift value by floor. Positive finite area and building-floor denominators are required; unsupported numeric or categorical strings produce an explicit error.

The area cut breaks depend on the observed minimum and maximum and step by ten square metres. The fitted state stores these breaks; the literal bin label is not replaced with a fixed interval. Ordinal imputation retains `as.numeric(factor_prediction)`, meaning factor codes rather than necessarily the original numeric category labels when response levels are absent. A missing-feature indicator exists only when an NA token occurs in the fitted vocabulary; missing and absent features are not indiscriminately replaced by a new dummy.

`fit_preprocessor()` and `transform_housing_data()` retain fitted imputers, means, vocabulary and column order. The stored name mapping uses `make.names(..., unique = TRUE)`. Character factor levels use UTF-8 ordering and explicit treatment contrasts. Missing factors remain missing; unseen nonmissing factor levels or feature tokens are rejected. Independently preprocessing another dataset is not the supported prediction path.

## Zones, splits and selection

The location table has `Zone,Train_Count,Test_Count,lon,lat` and 149 supplied zone rows. The geographic experiment uses k-means directly on longitude and latitude with `nstart = 5000`. Each cluster takes its first source-order zone as the representative label. Cluster counts and the model formula must be explicit. The longer commented merge list is inactive.

Random splits allocate `round(train_size / n_rows * zone_count)` training observations within each zone, with `train_size = 6000` by default. Rounding need not yield exactly 6000 rows or put each zone in both partitions. Missing zones remain in the holdout. This is repeated zone-stratified random validation, not spatial holdout or forward-in-time validation. Within-stratum index sampling uses `sample.int` to preserve singleton row identity.

Backward selection uses kernel-based coefficient p-values from `summary(rq_fit, se = "ker")`. Names containing `zone` or `conditions` are protected. The selection procedure maps a removable factor coefficient to its full formula term. Each path chooses its lowest original-price holdout MAE; candidates are then evaluated on further random splits. Formula-term counts differ from dummy-coefficient counts.

Attempts are bounded and failures are recorded with phase and attempt indices. Successful candidate and evaluation indices, actual scored-row counts and split indices are saved. Bounded retries and explicit term mapping do not guarantee the same random trajectory as interactive runs. No historical candidate formula is inferred from the figure's highlighted selection, and fitting requires an explicit formula or candidate identifier.

The report describes 50 candidates and another 50 evaluation splits, while acknowledging that observations were reused across selection and evaluation. Choosing the minimum observed MAE also biases that estimate. `global` preprocessing follows the archived dataset-wide order. Optional `split` preprocessing learns imputation and feature schemas inside each training partition and defines a new evaluation procedure. Neither mode turns the reported figures into independent validation results. MAE summaries retain omitted-pair counts and report nonfinite predictions; relative absolute and in-sample errors in earlier experiments are separate quantities.

## Other experiments

Earlier specifications include `log(selling_price)`, unlogged price per square metre, linear rather than ordinal imputation, missingness indicators and area-segmented regressions. Their response scales and inverse transforms remain separate from the supported log-price-per-square-metre bundle.

Named XGBoost configurations preserve 100, 7500, 15000 and 35000 rounds and their original parameter sets. Residual models fit `sqm_price - baseline_prediction` and add predictions on the log scale before exponentiation. The direct 35000-round configuration does not add a baseline. These full-data residual fits are not cross-fitted stacking. A shared fitted dummy schema encodes training and test predictors.

Ranger configurations retain ordinary response predictions, including fits with `quantreg = TRUE`; that fitting flag alone does not identify a median prediction. Direct CatBoost uses the supplied 1000-iteration parameter set. Its categorical columns must be supplied by verified names, including existing factor predictors, rather than inferred from historical positional indices. CatBoost file writing is disabled so its training log directory cannot depend on the caller's working directory.

The optional mlr/mlrMBO functions use two-fold CV and 30 MBO iterations. XGBoost tuning scores MAE; ranger and CatBoost tuning score RMSE. CatBoost's internal MAE loss is separate from its tuning measure. The custom CatBoost tuning learner must be explicitly registered by the caller. None of these experiments establishes a final submission model or a superior result.

## Available material

The English report contains the original three figures. Italian figure lettering is retained with English keys, and the artwork is unchanged. The PDF is published in the repository root; no standalone images are published.

Raw training/test listings, historical split indices, complete selection traces, the selected model specification, the original Google API project and QGIS resources are unavailable. The local `submission_faini.csv` has 4800 `ID,prediction` rows, not ground-truth prices. The saved `rq_bechmark.RData` is preserved locally and was not loaded or assumed to be the selected model.
