script_file <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
project_root <- normalizePath(file.path(dirname(script_file), ".."), mustWork = TRUE)
source(file.path(project_root, "R/io.R"))
for (module in c("preprocessing", "tree_models")) source(file.path(project_root, "R", paste0(module, ".R")))
source(file.path(project_root, "config/quantile.R"))
source(file.path(project_root, "config/tree_models.R"))
options <- parse_arguments(commandArgs(TRUE), defaults = list(
  "input-root" = "data", "input" = "training.csv", "config" = NULL,
  "baseline" = NULL, "categories" = "", "output" = "outputs/tree_model.rds"
), required = "config")
configurations <- housing_tree_configurations()
if (!options$config %in% names(configurations)) stop("Unknown named tree configuration.")
baseline <- if (is.null(options$baseline)) NULL else readRDS(input_file(project_root, ".", options$baseline))
categories <- if (nzchar(options$categories)) strsplit(options$categories, ",", fixed = TRUE)[[1L]] else character()
if (configurations[[options$config]]$engine == "catboost" && !length(categories)) {
  stop("CatBoost requires --categories with verified prepared categorical column names.")
}
raw <- read_housing_data(input_file(project_root, options[["input-root"]], options$input), labelled = TRUE)
bundle <- fit_housing_tree(raw, housing_quantile_config(), configurations[[options$config]],
                           baseline = baseline, categorical_features = categories)
saveRDS(bundle, project_output_path(project_root, options$output))
