# Build an explicit additive formula from the prepared predictor names.
housing_formula <- function(predictors, target = "sqm_price") {
  if (!length(predictors) || anyDuplicated(predictors)) {
    stop("Supply a nonempty, unique predictor list.")
  }
  quoted <- paste0("`", predictors, "`")
  stats::as.formula(paste0("`", target, "` ~ ", paste(quoted, collapse = " + ")))
}

# A formula file contains one formula as plain text, never an executable R script.
read_housing_formula <- function(path, target = "sqm_price") {
  formula <- stats::as.formula(paste(readLines(path, warn = FALSE), collapse = " "))
  if (length(formula) != 3L || !identical(as.character(formula[[2L]]), target)) {
    stop("The formula response must be ", target, ".")
  }
  if ("." %in% attr(stats::terms(formula), "term.labels")) {
    stop("List predictors explicitly instead of using '.'.")
  }
  formula
}

# Fit median log-price-per-square-metre regression with the source NA policy.
fit_quantile_model <- function(data, formula, tau = 0.5) {
  if (!requireNamespace("quantreg", quietly = TRUE)) stop("Package 'quantreg' is required.")
  if (!identical(as.numeric(tau), 0.5)) stop("The supported model uses tau = 0.5.")
  if (any(!all.vars(formula) %in% names(data))) {
    stop("The supplied formula references columns absent from the prepared data.")
  }
  quantreg::rq(formula, data = data, tau = tau, na.action = stats::na.exclude)
}

# Convert predictions on the log(price/area) scale to selling-price units.
predict_quantile_prices <- function(model, data) {
  if (!requireNamespace("quantreg", quietly = TRUE)) stop("Package 'quantreg' is required.")
  log_price <- as.numeric(stats::predict(model, newdata = data))
  if (length(log_price) != nrow(data)) stop("Prediction rows do not match input rows.")
  exp(log_price) * data$square_meters
}

# MAE uses available pairs, as in the supplied analysis; counts expose omissions.
price_error_summary <- function(observed, predicted) {
  if (length(observed) != length(predicted)) stop("Observed and predicted rows differ.")
  paired <- !is.na(observed) & !is.na(predicted)
  if (!any(paired)) stop("No observed-predicted pairs are available.")
  data.frame(mae = mean(abs(observed - predicted), na.rm = TRUE),
             total_rows = length(observed), paired_rows = sum(paired),
             omitted_rows = sum(!paired),
             nonfinite_predictions = sum(!is.na(predicted) & !is.finite(predicted)))
}

# Persist preprocessing together with an explicitly chosen formula and fitted model.
fit_housing_quantile <- function(data, config, formula) {
  prepared <- fit_preprocessor(data, config)
  model <- fit_quantile_model(prepared$data, formula, tau = config$tau)
  list(type = "quantile", model = model, preprocessing = prepared$state, formula = formula,
       tau = config$tau, training_ids = as.character(prepared$data$ID))
}
