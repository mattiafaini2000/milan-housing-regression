# Evaluate a workflow with a local seed, restoring the caller's RNG state.
with_local_seed <- function(seed, expression) {
  if (is.null(seed)) return(eval(substitute(expression), parent.frame()))
  had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  if (had_seed) previous_seed <- get(".Random.seed", envir = .GlobalEnv)
  on.exit({
    if (had_seed) assign(".Random.seed", previous_seed, envir = .GlobalEnv)
    else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
      rm(".Random.seed", envir = .GlobalEnv)
    }
  }, add = TRUE)
  set.seed(seed)
  eval(substitute(expression), parent.frame())
}

# Sample within zones using round(train_size / n_rows * zone_count).
# Missing zones are absent from the training strata and remain in the holdout.
zone_stratified_split <- function(data, train_size = 6000L,
                                  zone_column = "zone") {
  row_count <- nrow(data)
  if (!zone_column %in% names(data)) stop("Missing stratification column: ", zone_column)
  if (row_count < 2L || train_size < 1L || train_size >= row_count) {
    stop("train_size must be positive and smaller than the number of observations.")
  }
  strata <- split(seq_len(row_count), data[[zone_column]], drop = TRUE)
  sampled <- lapply(strata, function(row_indices) {
    count <- round(train_size / row_count * length(row_indices))
    if (count == 0L) return(integer())
    row_indices[sample.int(length(row_indices), size = count)]
  })
  training_rows <- as.integer(unlist(sampled, use.names = FALSE))
  holdout_rows <- setdiff(seq_len(row_count), training_rows)
  if (!length(training_rows) || !length(holdout_rows)) stop("The split has an empty partition.")
  zone_levels <- names(strata)
  counts <- data.frame(
    zone = zone_levels,
    total = lengths(strata),
    training = lengths(sampled),
    stringsAsFactors = FALSE
  )
  counts$holdout <- counts$total - counts$training
  list(training = training_rows, holdout = holdout_rows, counts = counts,
       missing_zone_rows = sum(is.na(data[[zone_column]])))
}
