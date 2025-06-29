script_file <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
project_root <- normalizePath(file.path(dirname(script_file), ".."), mustWork = TRUE)
source(file.path(project_root, "R", "io.R"))
options <- parse_arguments(commandArgs(TRUE), defaults = list(
  "input-root" = "data", "input" = "test.csv", "model" = "outputs/quantile_model.rds",
  "output" = "outputs/submission.csv"
))
for (module in c("preprocessing", "quantile_regression", "prediction", "tree_models")) {
  source(file.path(project_root, "R", paste0(module, ".R")))
}
data <- read_housing_data(input_file(project_root, options[["input-root"]], options$input), labelled = FALSE)
bundle <- readRDS(input_file(project_root, ".", options$model))
predictions <- if (identical(bundle$type, "tree")) {
  predict_tree_prices(bundle, data)
} else if (identical(bundle$type, "quantile")) {
  predict_housing_prices(bundle, data)
} else stop("Unknown model bundle type.")
if (!identical(as.character(predictions$ID), as.character(data$ID))) {
  stop("Prediction IDs do not match the input order.")
}
write_housing_predictions(predictions, project_output_path(project_root, options$output))
