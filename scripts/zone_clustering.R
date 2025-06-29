script_file <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
project_root <- normalizePath(file.path(dirname(script_file), ".."), mustWork = TRUE)
source(file.path(project_root, "R", "io.R"))
options <- parse_arguments(commandArgs(TRUE), defaults = list(
  "input-root" = "data", "input" = "training.csv", "locations" = "zone_locations.csv",
  "formula" = "", "clusters" = "", "seed" = "123", "nstart" = "5000",
  "output" = "outputs/zone_clustering.rds"
), required = c("formula", "clusters"))
for (module in c("preprocessing", "resampling", "quantile_regression", "zones")) {
  source(file.path(project_root, "R", paste0(module, ".R")))
}
source(file.path(project_root, "config", "quantile.R"))
config <- housing_quantile_config()
formula <- read_housing_formula(input_file(project_root, ".", options$formula), config$target)
cluster_counts <- as.integer(strsplit(options$clusters, ",", fixed = TRUE)[[1L]])
if (anyNA(cluster_counts) || any(cluster_counts < 1L) || anyDuplicated(cluster_counts)) {
  stop("--clusters needs a comma-separated list of distinct positive integers.")
}
data <- read_housing_data(input_file(project_root, options[["input-root"]], options$input), labelled = TRUE)
locations <- utils::read.csv(input_file(project_root, options[["input-root"]], options$locations),
                             stringsAsFactors = FALSE, check.names = FALSE)
comparison <- evaluate_zone_clustering(data, locations, formula, cluster_counts, config,
                                       seed = as.integer(options$seed), nstart = as.integer(options$nstart))
saveRDS(comparison, project_output_path(project_root, options$output))
