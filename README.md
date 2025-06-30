# Milan Housing Regression

Mattia Faini's Milan Housing project studies property selling-price prediction using data cleaning, fitted imputation, engineered housing features and median quantile regression. The model fits `log(selling_price / square_meters)` and converts predictions back to selling prices with `exp(prediction) * square_meters`. Model selection and evaluation use absolute errors on that price scale.

Read the complete [English report](report/milan_housing_report_en.pdf) or the [original Italian report](report/report_faini.pdf). The English report retains the historical figures and results. Figure lettering remains Italian, with English keys immediately below each figure; standalone image files are not included.

The reported geographic experiment found that validation MAE generally increased as neighbourhoods were combined into fewer groups, so the report retained the full zone representation. Repeated backward selection produced different predictor sets across random splits. The report also acknowledges that reusing observations for candidate selection and evaluation, and choosing the lowest observed MAE, biases the resulting estimate.

The code keeps quantile regression central. Random-forest, XGBoost, CatBoost and residual-correction configurations are separate experiments; no leaderboard score or winning model is attributed to them.

## Code and requirements

`R/` defines preprocessing, zone handling, stratified splits, fitting, selection, prediction and optional tree-model functions. `scripts/` contains the explicit analysis entry points. `config/` contains the consolidated recoding rules, a starting quantile formula and named tree configurations. `report/` contains the two PDFs and the clean English LaTeX source. [Methods](docs/methods.md) describes fields, transformations and evaluation.

The main R path requires **MASS** and **quantreg**, in addition to base R. Optional trees require **xgboost**, **ranger** or **catboost**; tuning additionally uses **mlr**, **mlrMBO** and **ParamHelpers**. Earlier experiments reference **rqPen**, **ggmap** and **tidygeocoder**. These optional packages are unnecessary for the quantile workflow or report build. [r-dependencies.dcf](r-dependencies.dcf) records this division without claiming historically tested package versions.

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

## Building the English report

The Windows PowerShell build script uses an installed MiKTeX `pdflatex` engine, `pdfimages` and an existing `pdflatex.fmt`. It extracts only the three historical figure images from the Italian PDF into local build storage, then compiles the English source with package installation and shell escape disabled. It requires no R packages and performs no statistical analysis.

```powershell
powershell -NoProfile -File scripts/build_report.ps1
```

Build intermediates and extracted images are written to `.build/report/`; the completed PDF is written to `report/milan_housing_report_en.pdf`. The script accepts `-FormatFile` if the installed format is in a different location.
