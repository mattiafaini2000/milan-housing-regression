# Predictions retain the input ID order and use training-fitted preprocessing.
predict_housing_prices <- function(bundle, data) {
  prepared <- transform_housing_data(data, bundle$preprocessing)
  if (!identical(as.character(data$ID), as.character(prepared$ID))) {
    stop("Preprocessing changed prediction row identities.")
  }
  data.frame(ID = data$ID,
             prediction = predict_quantile_prices(bundle$model, prepared),
             stringsAsFactors = FALSE)
}

# Match the source output schema: ID,prediction, no row names or quoted fields.
write_housing_predictions <- function(predictions, output_path) {
  if (!identical(names(predictions), c("ID", "prediction"))) stop("Expected ID,prediction columns.")
  if (anyNA(predictions$ID) || anyDuplicated(predictions$ID)) stop("Prediction IDs must be unique and present.")
  utils::write.table(predictions, file = output_path, sep = ",", quote = FALSE,
                     row.names = FALSE, col.names = TRUE, na = "")
  invisible(output_path)
}
