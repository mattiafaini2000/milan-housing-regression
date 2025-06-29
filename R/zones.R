# Summarize observed zone frequencies without accessing a geocoding service.
zone_observation_counts <- function(training_zones, test_zones) {
  training_counts <- as.data.frame(table(training_zones), stringsAsFactors = FALSE)
  test_counts <- as.data.frame(table(test_zones), stringsAsFactors = FALSE)
  names(training_counts) <- c("Zone", "Train_Count")
  names(test_counts) <- c("Zone", "Test_Count")
  counts <- merge(training_counts, test_counts, by = "Zone", all = TRUE)
  counts$Train_Count[is.na(counts$Train_Count)] <- 0L
  counts$Test_Count[is.na(counts$Test_Count)] <- 0L
  counts[order(counts$Train_Count, decreasing = TRUE), , drop = FALSE]
}

# Fit the exploratory longitude/latitude k-means map without transforming degrees.
# The first zone in each source-order cluster is the representative label.
cluster_housing_zones <- function(locations, centers, nstart = 5000L) {
  required <- c("Zone", "lon", "lat")
  if (any(!required %in% names(locations))) stop("Zone locations need Zone,lon,lat columns.")
  if (anyNA(locations$Zone) || anyDuplicated(locations$Zone)) stop("Zone names must be unique and present.")
  coordinates <- as.matrix(locations[, c("lon", "lat"), drop = FALSE])
  if (!is.numeric(coordinates) || any(!is.finite(coordinates))) {
    stop("Zone coordinates must be finite numeric longitude/latitude values.")
  }
  if (length(centers) != 1L || centers < 1L || centers > nrow(unique(coordinates))) {
    stop("centers must not exceed the number of distinct coordinate pairs.")
  }
  clustering <- stats::kmeans(coordinates, centers = centers, nstart = nstart)
  clusters <- split(as.character(locations$Zone), clustering$cluster)
  names(clusters) <- NULL
  zone_map <- unlist(lapply(clusters, function(zones) {
    stats::setNames(rep(zones[1L], length(zones)), zones)
  }), use.names = TRUE)
  list(map = zone_map, clustering = clustering,
       locations = locations[, required, drop = FALSE], nstart = nstart)
}

apply_zone_map <- function(data, zone_map) {
  mapped <- unname(zone_map[as.character(data$zone)])
  unmatched <- !is.na(data$zone) & is.na(mapped)
  if (any(unmatched)) stop("The location map does not cover every observed zone.")
  data$main_zone <- mapped
  data
}

# Reuse a fixed stratified split while comparing explicitly requested cluster counts.
evaluate_zone_clustering <- function(data, locations, formula, cluster_counts,
                                     config, seed = 123L, nstart = 5000L) {
  with_local_seed(seed, {
    prepared <- fit_preprocessor(data, config)
    split <- zone_stratified_split(prepared$data, train_size = config$train_size)
    scores <- list()
    maps <- list()
    for (centers in cluster_counts) {
      outcome <- tryCatch({
        fitted_map <- cluster_housing_zones(locations, centers, nstart)
        clustered <- apply_zone_map(prepared$data, fitted_map$map)
        model <- fit_quantile_model(clustered[split$training, , drop = FALSE], formula, config$tau)
        heldout <- clustered[split$holdout, , drop = FALSE]
        score <- price_error_summary(heldout$selling_price, predict_quantile_prices(model, heldout))
        maps[[as.character(centers)]] <- fitted_map
        cbind(data.frame(clusters = centers, status = "completed", error = ""), score)
      }, error = function(error) {
        data.frame(clusters = centers, status = "failed", error = conditionMessage(error),
                   mae = NA_real_, total_rows = length(split$holdout), paired_rows = NA_integer_,
                   omitted_rows = NA_integer_, nonfinite_predictions = NA_integer_)
      })
      scores[[length(scores) + 1L]] <- outcome
    }
    list(scores = do.call(rbind, scores), maps = maps, split = split,
         formula = formula, seed = seed, preprocessing = "global", nstart = nstart)
  })
}
