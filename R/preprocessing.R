# Read listing fields without changing IDs or UTF-8 neighbourhood names.
read_housing_data <- function(path, labelled = TRUE) {
  header <- utils::read.csv(path, nrows = 0, check.names = FALSE,
                            fileEncoding = "UTF-8", stringsAsFactors = FALSE)
  if (!"ID" %in% names(header) || anyDuplicated(names(header))) {
    stop("The input must contain ID and have unique column names.")
  }
  column_classes <- rep(NA_character_, ncol(header))
  column_classes[match("ID", names(header))] <- "character"
  data <- utils::read.csv(path, check.names = FALSE, fileEncoding = "UTF-8",
                          stringsAsFactors = FALSE, colClasses = column_classes)
  validate_housing_fields(data, labelled)
  data
}

validate_housing_fields <- function(data, labelled) {
  fields <- c("ID", "bathrooms_number", "rooms_number", "square_meters",
              "year_of_construction", "total_floors_in_building", "car_parking",
              "availability", "floor", "energy_efficiency_class", "other_features",
              "lift", "condominium_fees", "conditions", "heating_centralized", "zone")
  if (labelled) fields <- c(fields, "selling_price")
  missing_fields <- setdiff(fields, names(data))
  if (length(missing_fields)) {
    stop("Missing listing fields: ", paste(missing_fields, collapse = ", "))
  }
  if (!nrow(data) || anyNA(data$ID) || any(data$ID == "") || anyDuplicated(data$ID)) {
    stop("Listing IDs must be present and unique, and the input must have rows.")
  }
}

housing_numeric <- function(values, field, replacements = NULL) {
  values <- as.character(values)
  values[values == ""] <- NA_character_
  if (length(replacements)) {
    for (label in names(replacements)) {
      values[!is.na(values) & values == label] <- replacements[[label]]
    }
  }
  numbers <- suppressWarnings(as.numeric(values))
  if (any(!is.na(values) & is.na(numbers))) {
    stop("Unsupported nonnumeric values in ", field, ".")
  }
  numbers
}

recode_housing_zones <- function(zone, replacements) {
  zone <- enc2utf8(as.character(zone))
  for (index in seq_len(nrow(replacements))) {
    matched <- !is.na(zone) & zone == replacements$from[index]
    zone[matched] <- replacements$to[index]
  }
  zone
}

extract_parking_counts <- function(values, type = c("box", "shared")) {
  type <- match.arg(type)
  pattern <- if (type == "box") "(\\d+) in garage/box" else "(\\d+) in shared parking"
  counts <- integer(length(values))
  matched <- !is.na(values) & grepl(pattern, values)
  matches <- regmatches(values[matched], regexpr(pattern, values[matched]))
  counts[matched] <- as.integer(sub(" .*", "", matches))
  counts
}

split_housing_features <- function(values) {
  values <- gsub("pvcexposure", "pvc | exposure", values, fixed = TRUE)
  values <- gsub("pvcdouble exposure", "pvc | double exposure", values, fixed = TRUE)
  strsplit(values, " \\| ")
}

housing_feature_matrix <- function(tokens, vocabulary) {
  encoded <- matrix(0, nrow = length(tokens), ncol = length(vocabulary))
  for (index in seq_along(tokens)) {
    encoded[index, ] <- as.integer(vocabulary %in% trimws(tokens[[index]]))
  }
  encoded
}

# Fits are stored in the returned state; ordinal predictions retain factor codes.
apply_housing_imputer <- function(data, state, field, predictors, method, fitting) {
  missing_rows <- which(is.na(data[[field]]))
  if (method == "ordinal" && (fitting || length(missing_rows)) &&
      !requireNamespace("MASS", quietly = TRUE)) {
    stop("Package 'MASS' is required for ordinal imputation.")
  }
  if (fitting) {
    observed <- data[!is.na(data[[field]]), , drop = FALSE]
    model_formula <- stats::reformulate(predictors, response = field)
    if (method == "ordinal") {
      observed[[field]] <- as.factor(observed[[field]])
      if (nlevels(observed[[field]]) < 3L) {
        stop("Ordinal imputation needs at least three observed levels in ", field, ".")
      }
      state$imputers[[field]] <- MASS::polr(model_formula, data = observed,
                                           na.action = stats::na.omit)
    } else if (method == "logistic") {
      observed[[field]] <- as.factor(observed[[field]])
      if (nlevels(observed[[field]]) != 2L) stop("Lift imputation needs both lift classes.")
      state$imputers[[field]] <- stats::glm(
        model_formula, data = observed, family = stats::binomial(link = "logit"),
        na.action = stats::na.omit
      )
    } else {
      state$imputers[[field]] <- stats::lm(model_formula, data = observed,
                                          na.action = stats::na.omit)
    }
  }
  if (length(missing_rows)) {
    prediction_type <- if (method == "logistic") "response" else if (method == "ordinal") "class" else "response"
    predictions <- stats::predict(state$imputers[[field]],
                                   newdata = data[missing_rows, , drop = FALSE],
                                   type = prediction_type)
    data[[field]][missing_rows] <- as.numeric(predictions)
  }
  list(data = data, state = state)
}

apply_housing_mean <- function(values, state, field, fitting) {
  if (fitting) {
    state$means[[field]] <- mean(values, na.rm = TRUE)
    if (!is.finite(state$means[[field]])) stop("No finite mean for ", field, ".")
  }
  values[is.na(values)] <- state$means[[field]]
  list(values = values, state = state)
}

# Apply recoding and fitted imputers in the consolidated script's order.
prepare_housing_fields <- function(data, state, fitting) {
  settings <- state$config
  data$ID <- as.character(data$ID)
  data$square_meters <- housing_numeric(data$square_meters, "square_meters")
  if (fitting) {
    observed_area <- data$square_meters[is.finite(data$square_meters)]
    if (!length(observed_area)) stop("Area-bin construction needs observed square_meters.")
    state$area_breaks <- seq(floor(min(observed_area)), ceiling(max(observed_area)), by = 10)
    if (length(state$area_breaks) < 2L) stop("Area-bin construction needs a range of at least 10 square metres.")
  }
  area_bins <- cut(data$square_meters, breaks = state$area_breaks,
                   include.lowest = TRUE, right = FALSE)
  data$bathrooms_number <- housing_numeric(data$bathrooms_number, "bathrooms_number", c("3+" = "4"))
  processed <- apply_housing_imputer(data, state, "bathrooms_number", "square_meters", "ordinal", fitting)
  data <- processed$data
  state <- processed$state
  data$rooms_number <- housing_numeric(data$rooms_number, "rooms_number", c("5+" = "6"))
  small_area <- !is.na(data$square_meters) & data$square_meters < settings$area_minimum
  inconsistent_area <- !is.na(area_bins) & area_bins == settings$inconsistent_area_bin &
    !is.na(data$rooms_number) & data$rooms_number == settings$inconsistent_rooms
  data$square_meters[small_area | inconsistent_area] <- NA_real_
  processed <- apply_housing_imputer(data, state, "square_meters", "rooms_number", "linear", fitting)
  data <- processed$data
  state <- processed$state
  if (any(!is.na(data$square_meters) & (!is.finite(data$square_meters) | data$square_meters <= 0))) {
    stop("Positive finite square_meters are needed for reciprocals and price transforms.")
  }
  if ("selling_price" %in% names(data)) {
    data$selling_price <- housing_numeric(data$selling_price, "selling_price")
    if (any(!is.na(data$selling_price) & (!is.finite(data$selling_price) | data$selling_price <= 0))) {
      stop("Observed selling prices must be positive and finite.")
    }
    data$sqm_price <- log(data$selling_price / data$square_meters)
  } else {
    data$selling_price <- NA_real_
    data$sqm_price <- NA_real_
  }
  data$sqm_1 <- 1 / data$square_meters
  processed_mean <- apply_housing_mean(housing_numeric(data$year_of_construction, "year_of_construction"), state,
                                        "year_of_construction", fitting)
  data$year_of_construction <- processed_mean$values
  state <- processed_mean$state
  data$new <- ifelse(data$year_of_construction > settings$new_after_year, 1, 0)
  data$total_floors_in_building <- housing_numeric(data$total_floors_in_building,
                                                   "total_floors_in_building", c("1 floor" = "1"))
  processed <- apply_housing_imputer(data, state, "total_floors_in_building", "year_of_construction", "linear", fitting)
  data <- processed$data
  state <- processed$state
  if (any(!is.na(data$total_floors_in_building) & (!is.finite(data$total_floors_in_building) | data$total_floors_in_building <= 0))) {
    stop("Positive finite building-floor totals are needed for floor ratios.")
  }
  data$garage_box <- extract_parking_counts(data$car_parking, "box")
  data$shared_parking <- extract_parking_counts(data$car_parking, "shared")
  availability <- ifelse(is.na(data$availability), NA_real_, as.numeric(data$availability == "available"))
  processed_mean <- apply_housing_mean(availability, state, "availability", fitting)
  data$availability <- processed_mean$values
  state <- processed_mean$state
  floor_labels <- as.character(data$floor)
  data$ground <- as.numeric(!is.na(floor_labels) & floor_labels == "ground floor")
  data$basement <- as.numeric(!is.na(floor_labels) & floor_labels == "semi-basement")
  data$mezzanine <- as.numeric(!is.na(floor_labels) & floor_labels == "mezzanine")
  data$floor <- housing_numeric(floor_labels, "floor",
                                c("ground floor" = "0", "mezzanine" = "0", "semi-basement" = "0"))
  data$ratio <- data$floor / data$total_floors_in_building
  energy_class <- as.character(data$energy_efficiency_class)
  energy_class[energy_class %in% c(",", "")] <- NA_character_
  if (any(!is.na(energy_class) & !energy_class %in% letters[1:7])) stop("Energy classes must be a through g or missing.")
  data$energy_efficiency_class <- as.numeric(setNames(1:7, letters[1:7])[energy_class])
  processed <- apply_housing_imputer(data, state, "energy_efficiency_class", "year_of_construction", "ordinal", fitting)
  data <- processed$data
  state <- processed$state
  feature_tokens <- split_housing_features(as.character(data$other_features))
  if (fitting) {
    vocabulary <- unique(unlist(feature_tokens, use.names = FALSE))
    encoded <- housing_feature_matrix(feature_tokens, vocabulary)
    feature_order <- order(colSums(encoded), decreasing = TRUE)
    state$feature_vocabulary <- vocabulary[feature_order]
  } else {
    unseen <- setdiff(unique(unlist(feature_tokens, use.names = FALSE)), state$feature_vocabulary)
    unseen <- unseen[!is.na(unseen)]
    if (length(unseen)) stop("The input contains other_features outside the fitted vocabulary.")
  }
  encoded <- housing_feature_matrix(feature_tokens, state$feature_vocabulary)
  colnames(encoded) <- state$feature_vocabulary
  data <- cbind(data, as.data.frame(encoded))
  data$lift <- housing_numeric(data$lift, "lift", c("no" = "1", "yes" = "0"))
  processed <- apply_housing_imputer(data, state, "lift", c("year_of_construction", "total_floors_in_building"), "logistic", fitting)
  data <- processed$data
  state <- processed$state
  data$floor_lift <- data$floor * data$lift
  fees <- housing_numeric(data$condominium_fees, "condominium_fees", c("No condominium fees" = "0")) / data$square_meters
  processed_mean <- apply_housing_mean(fees, state, "condominium_fees", fitting)
  data$condominium_fees <- processed_mean$values
  state <- processed_mean$state
  data$conditions <- as.character(data$conditions)
  data$conditions[is.na(data$conditions)] <- settings$missing_conditions
  heating <- as.character(data$heating_centralized)
  heating[is.na(heating)] <- settings$missing_heating
  data$heating_centralized <- housing_numeric(heating, "heating_centralized", c("central" = "1", "independent" = "0"))
  data$zone <- recode_housing_zones(data$zone, settings$zone_replacements)
  data$main_zone <- data$zone
  list(data = data, state = state)
}

# Learn imputation fits, vocabulary, and factor levels from explicitly supplied rows.
fit_preprocessor <- function(data, config) {
  validate_housing_fields(data, labelled = TRUE)
  if (config$target != "sqm_price" || config$target_transformation != "log_price_per_sqm" ||
      config$ordinal_output != "factor_codes") {
    stop("This preprocessor supports the consolidated log-price-per-square-metre configuration.")
  }
  retained <- !as.character(data$ID) %in% as.character(config$excluded_ids)
  excluded_ids <- as.character(data$ID[!retained])
  data <- data[retained, , drop = FALSE]
  validate_housing_fields(data, labelled = TRUE)
  state <- list(config = config, target = config$target,
                target_transformation = config$target_transformation, imputers = list(), means = list(),
                raw_columns = names(data), excluded_ids = excluded_ids)
  processed <- prepare_housing_fields(data, state, fitting = TRUE)
  data <- processed$data
  state <- processed$state
  state$feature_names <- data.frame(original = names(data),
                                    prepared = make.names(names(data), unique = TRUE),
                                    stringsAsFactors = FALSE)
  names(data) <- state$feature_names$prepared
  categorical <- names(data)[vapply(data, is.character, logical(1))]
  categorical <- setdiff(categorical, c("ID", "other_features", "car_parking"))
  state$factor_levels <- list()
  for (field in categorical) {
    levels <- sort(unique(enc2utf8(data[[field]][!is.na(data[[field]])])), method = "radix")
    state$factor_levels[[field]] <- levels
    data[[field]] <- factor(enc2utf8(data[[field]]), levels = levels)
    if (length(levels) > 1L) contrasts(data[[field]]) <- stats::contr.treatment(levels, base = 1)
  }
  state$prepared_columns <- names(data)
  state$predictors <- setdiff(names(data), c(config$predictor_exclusions, "sqm_price"))
  state$predictor_columns <- state$predictors
  list(data = data, state = state)
}

# Reuse fitted statistics and schema; keep every requested ID in its original order.
transform_housing_data <- function(data, state) {
  validate_housing_fields(data, labelled = FALSE)
  required_raw <- setdiff(state$raw_columns, "selling_price")
  if (length(setdiff(required_raw, names(data)))) stop("Input columns differ from the fitted raw schema.")
  if (!"selling_price" %in% names(data)) data$selling_price <- NA_real_
  data <- data[, state$raw_columns, drop = FALSE]
  processed <- prepare_housing_fields(data, state, fitting = FALSE)
  data <- processed$data
  if (!identical(names(data), state$feature_names$original)) stop("Prepared feature schema differs from the fitted schema.")
  names(data) <- state$feature_names$prepared
  for (field in names(state$factor_levels)) {
    values <- enc2utf8(as.character(data[[field]]))
    levels <- state$factor_levels[[field]]
    if (any(!is.na(values) & !values %in% levels)) stop("Unseen categorical levels in ", field, ".")
    data[[field]] <- factor(values, levels = levels)
    if (length(levels) > 1L) contrasts(data[[field]]) <- stats::contr.treatment(levels, base = 1)
  }
  data[, state$prepared_columns, drop = FALSE]
}
