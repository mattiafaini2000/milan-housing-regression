script_file <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
project_root <- normalizePath(file.path(dirname(script_file), ".."), mustWork = TRUE)
source(file.path(project_root, "R", "io.R"))
options <- parse_arguments(commandArgs(TRUE), defaults = list(
  "input-root" = "data", "input" = "training.csv", "formula" = "",
  "selection-repeats" = "50", "evaluation-repeats" = "50", "max-attempts" = "100",
  "preprocessing" = "global", "seed" = "1234", "output" = "outputs/selection.rds"
))
for (module in c("preprocessing", "resampling", "quantile_regression", "model_selection")) {
  source(file.path(project_root, "R", paste0(module, ".R")))
}
source(file.path(project_root, "config", "quantile.R"))
config <- housing_quantile_config()
formula <- if (nzchar(options$formula)) {
  read_housing_formula(input_file(project_root, ".", options$formula), config$target)
} else NULL
data <- read_housing_data(input_file(project_root, options[["input-root"]], options$input), labelled = TRUE)
selection <- evaluate_quantile_selection(
  data, config, formula = formula,
  selection_repeats = as.integer(options[["selection-repeats"]]),
  evaluation_repeats = as.integer(options[["evaluation-repeats"]]),
  max_attempts = as.integer(options[["max-attempts"]]),
  preprocessing = options$preprocessing, seed = as.integer(options$seed)
)
saveRDS(selection, project_output_path(project_root, options$output))
message("Candidates completed: ", selection$completed_selection, "/", selection$requested_selection,
        "; evaluation repeats completed: ", selection$completed_evaluation, "/", selection$requested_evaluation)
