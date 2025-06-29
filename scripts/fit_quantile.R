script_file <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
project_root <- normalizePath(file.path(dirname(script_file), ".."), mustWork = TRUE)
source(file.path(project_root, "R", "io.R"))
options <- parse_arguments(commandArgs(TRUE), defaults = list(
  "input-root" = "data", "input" = "training.csv", "formula" = "",
  "selection" = "", "candidate" = "", "output" = "outputs/quantile_model.rds"
))
for (module in c("preprocessing", "quantile_regression")) {
  source(file.path(project_root, "R", paste0(module, ".R")))
}
source(file.path(project_root, "config", "quantile.R"))
config <- housing_quantile_config()
if (nzchar(options$formula) == nzchar(options$selection)) {
  stop("Choose either --formula or --selection together with --candidate.")
}
formula <- if (nzchar(options$formula)) {
  if (nzchar(options$candidate)) stop("--candidate is only used with --selection.")
  read_housing_formula(input_file(project_root, ".", options$formula), config$target)
} else {
  candidate_id <- as.integer(options$candidate)
  selection <- readRDS(input_file(project_root, ".", options$selection))
  if (length(candidate_id) != 1L || is.na(candidate_id) || candidate_id < 1L ||
      candidate_id > length(selection$candidates)) stop("Supply a valid --candidate number.")
  selection$candidates[[candidate_id]]$formula
}
data <- read_housing_data(input_file(project_root, options[["input-root"]], options$input), labelled = TRUE)
bundle <- fit_housing_quantile(data, config, formula)
saveRDS(bundle, project_output_path(project_root, options$output))
