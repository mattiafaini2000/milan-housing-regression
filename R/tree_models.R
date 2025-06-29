# A single fitted matrix schema replaces independent train/test dummy encoding.
fit_tree_matrix <- function(data, predictors) {
  terms <- stats::terms(stats::reformulate(predictors))
  frame <- stats::model.frame(terms, data = data, na.action = stats::na.pass)
  matrix <- stats::model.matrix(terms, frame)
  columns <- setdiff(colnames(matrix), "(Intercept)")
  levels <- lapply(frame[vapply(frame, is.factor, logical(1))], levels)
  list(matrix = matrix[, columns, drop = FALSE],
       schema = list(terms = terms, levels = levels, contrasts = attr(matrix, "contrasts"), columns = columns))
}

transform_tree_matrix <- function(data, schema) {
  frame <- stats::model.frame(schema$terms, data = data, na.action = stats::na.pass, xlev = schema$levels)
  matrix <- stats::model.matrix(schema$terms, frame, contrasts.arg = schema$contrasts)
  if (length(setdiff(schema$columns, colnames(matrix)))) stop("Tree predictor columns do not match the fitted schema.")
  matrix[, schema$columns, drop = FALSE]
}

# Categorical column names must be supplied; historical positional indices are not inferred.
catboost_features <- function(data, predictors, categorical_features) {
  if (length(setdiff(categorical_features, predictors))) stop("Unknown categorical predictors.")
  features <- data[, predictors, drop = FALSE]
  existing_factors <- names(features)[vapply(features, is.factor, logical(1))]
  if (length(setdiff(existing_factors, categorical_features))) {
    stop("Categorical feature names must include all existing factor predictors.")
  }
  for (field in categorical_features) features[[field]] <- as.factor(features[[field]])
  features
}

# Fit either log-price-per-square-metre directly or its full-data baseline residual.
fit_housing_tree <- function(raw, preprocessing_config, configuration, predictors = NULL,
                             baseline = NULL, categorical_features = character()) {
  if (configuration$target == "residual") {
    if (is.null(baseline)) stop("Residual models require an explicit fitted quantile baseline.")
    retained <- !as.character(raw$ID) %in% baseline$preprocessing$config$excluded_ids
    prepared <- transform_housing_data(raw[retained, , drop = FALSE], baseline$preprocessing)
    preprocessing <- baseline$preprocessing
  } else {
    fitted <- fit_preprocessor(raw, preprocessing_config)
    prepared <- fitted$data
    preprocessing <- fitted$state
  }
  if (is.null(predictors)) predictors <- preprocessing$predictors
  if (!length(predictors) || length(setdiff(predictors, names(prepared)))) stop("An explicit valid predictor set is needed.")
  target <- prepared$sqm_price
  if (configuration$target == "residual") {
    if (!requireNamespace("quantreg", quietly = TRUE)) stop("quantreg is required for the baseline.")
    target <- target - as.numeric(stats::predict(baseline$model, newdata = prepared))
  }
  if (any(!is.finite(target))) stop("Tree training targets must be finite.")
  engine <- configuration$engine
  if (!requireNamespace(engine, quietly = TRUE)) stop("The optional package is required: ", engine)
  schema <- NULL
  if (engine == "xgboost") {
    encoded <- fit_tree_matrix(prepared, predictors)
    schema <- encoded$schema
    model <- xgboost::xgb.train(params = configuration$parameters,
      data = xgboost::xgb.DMatrix(encoded$matrix, label = target), nrounds = configuration$rounds)
  } else if (engine == "ranger") {
    training <- prepared[, predictors, drop = FALSE]
    training$.tree_target <- target
    model <- do.call(ranger::ranger, c(list(dependent.variable.name = ".tree_target", data = training), configuration$parameters))
  } else if (engine == "catboost") {
    features <- catboost_features(prepared, predictors, categorical_features)
    pool <- catboost::catboost.load_pool(data = features, label = target)
    model <- catboost::catboost.train(learn_pool = pool, test_pool = NULL, params = configuration$parameters)
  } else {
    stop("Unknown tree engine: ", engine)
  }
  list(type = "tree", engine = engine, configuration = configuration, preprocessing = preprocessing,
       predictors = predictors, feature_schema = schema, model = model, baseline = baseline,
       categorical_features = categorical_features, training_ids = prepared$ID)
}

predict_tree_prices <- function(bundle, raw) {
  prepared <- transform_housing_data(raw, bundle$preprocessing)
  if (!requireNamespace(bundle$engine, quietly = TRUE)) stop("The fitted tree engine is required: ", bundle$engine)
  log_prediction <- if (bundle$engine == "xgboost") {
    stats::predict(bundle$model, transform_tree_matrix(prepared, bundle$feature_schema))
  } else if (bundle$engine == "ranger") {
    stats::predict(bundle$model, data = prepared[, bundle$predictors, drop = FALSE],
                   type = bundle$configuration$prediction)$predictions
  } else {
    pool <- catboost::catboost.load_pool(catboost_features(prepared, bundle$predictors, bundle$categorical_features))
    catboost::catboost.predict(bundle$model, pool)
  }
  if (bundle$configuration$target == "residual") {
    if (!requireNamespace("quantreg", quietly = TRUE)) stop("quantreg is required for the baseline.")
    log_prediction <- log_prediction + stats::predict(bundle$baseline$model, newdata = prepared)
  }
  if (length(log_prediction) != nrow(prepared) || !identical(as.character(prepared$ID), as.character(raw$ID))) {
    stop("Tree prediction rows do not match the requested listing IDs.")
  }
  data.frame(ID = raw$ID, prediction = exp(as.numeric(log_prediction)) * prepared$square_meters,
             stringsAsFactors = FALSE)
}
