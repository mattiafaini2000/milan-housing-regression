# Milan Housing Regression

Mattia Faini's Milan Housing project studies property selling-price prediction from housing characteristics and neighbourhood information.

Read the complete [English report](milan_housing_report_en.pdf).

## Report summary

The report begins with cleaning inconsistent listing fields and imputing missing values using ordinal, linear and logistic regression, together with mean and category replacements. It constructs predictors for inverse floor area, construction after 2010, parking spaces, floor characteristics, lift availability and other property features. Neighbourhoods were geocoded and corrected in QGIS, and zones with very few training observations were combined with nearby zones.

The main model is median quantile regression on `log(selling_price / square_meters)`. Predictions return to selling prices through `exp(prediction) * square_meters`, and model comparisons use absolute errors on that price scale. A geographic experiment combined neighbourhoods using k-means on their coordinates. Validation MAE generally increased as the number of zone groups decreased, so the report retained the full zone representation for subsequent analysis.

Backward selection produced different predictor sets across random training and validation splits. The report compares 50 candidate models over another 50 splits and describes selecting a model with the lowest observed MAE and an acceptable variance. It also acknowledges that reusing observations for selection and evaluation, and choosing the minimum observed MAE, biases the estimate; the reported comparison is not an independent validation result.

## Code and requirements

`R/` defines preprocessing, zone handling, stratified splits, fitting, selection, prediction and optional tree-model functions. `scripts/` contains the explicit analysis entry points. `config/` contains the consolidated recoding rules, a starting quantile formula and named tree configurations. The English report PDF is in the repository root. [Methods](docs/methods.md) describes fields, transformations and evaluation.

Quantile regression is the main workflow. Random-forest, XGBoost, CatBoost and residual-correction configurations are separate experiments; no leaderboard score or winning model is attributed to them.

The main R path requires **MASS** and **quantreg**, in addition to base R. Optional trees require **xgboost**, **ranger** or **catboost**; tuning additionally uses **mlr**, **mlrMBO** and **ParamHelpers**. Earlier experiments reference **rqPen**, **ggmap** and **tidygeocoder**. These optional packages are unnecessary for the quantile workflow. [r-dependencies.dcf](r-dependencies.dcf) records this division without claiming historically tested package versions.

Supply UTF-8 comma-delimited `training.csv` with labelled listings and `test.csv` with the same predictor fields and explicit `ID` values. Raw listing data are not included. The optional geographic comparison also requires the zone-level `loc.txt` table with `Zone,Train_Count,Test_Count,lon,lat`; it is not a replacement for listing data. An external read-only directory can be passed through `--input-root`.

## Commands and outputs

Run these examples from the repository root after supplying the required data and packages. They perform model fitting and can be computationally expensive.

```sh
Rscript --vanilla scripts/fit_quantile.R --input-root data --input training.csv --formula config/quantile_formula.txt --output outputs/quantile_model.rds
Rscript --vanilla scripts/predict.R --input-root data --input test.csv --model outputs/quantile_model.rds --output outputs/submission.csv
```

The formula file is an explicit starting specification using the documented core fields. It does not identify the historical selected model. Edit it to supply a chosen specification, or explicitly choose a candidate from a future selection run:

```sh
Rscript --vanilla scripts/evaluate_selection.R --input-root data --input training.csv --selection-repeats 50 --evaluation-repeats 50 --max-attempts 150 --preprocessing global --seed 1234 --output outputs/selection.rds
Rscript --vanilla scripts/fit_quantile.R --input-root data --input training.csv --selection outputs/selection.rds --candidate 1 --output outputs/quantile_model.rds
```

Candidate `1` is an example identifier, not a recommendation. Selection output stores formulas, paths, scores, split indices, scored-row counts and failure records. `global` fits preprocessing before the splits, following the archived analysis order. The opt-in `split` setting fits preprocessing on each training partition and constitutes a separate evaluation procedure.

Optional experiments use explicit inputs and configurations:

```sh
Rscript --vanilla scripts/zone_clustering.R --input-root data --input training.csv --locations loc.txt --formula config/quantile_formula.txt --clusters 100,75,50 --seed 123 --output outputs/zone_clustering.rds
Rscript --vanilla scripts/fit_tree_model.R --input-root data --input training.csv --config xgb_residual_100 --baseline outputs/quantile_model.rds --output outputs/tree_model.rds
```

Cluster counts are example future choices. Tree bundles can be passed to the same prediction script. All output paths must be relative to this project. Fitted bundles retain preprocessing statistics, imputation models, feature vocabulary, factor levels, target transformation and the fitted model. Predictions contain `ID,prediction` in the requested test order; no models, new predictions or selection traces are included.
