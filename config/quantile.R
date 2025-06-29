housing_quantile_config <- function() {
  list(
    target = "sqm_price",
    target_transformation = "log_price_per_sqm",
    tau = 0.5,
    excluded_ids = "2571",
    area_minimum = 11,
    inconsistent_area_bin = "[11,21)",
    inconsistent_rooms = 6,
    new_after_year = 2010,
    missing_conditions = "excellent / refurbished",
    missing_heating = "central",
    ordinal_output = "factor_codes",
    predictor_exclusions = c(
      "ID", "selling_price", "other_features", "car_parking",
      "X8.balconies", "property.land1.balcony", "zone", "X6.balconies"
    ),
    zone_replacements = data.frame(
      from = c("corso magenta", "largo caioroli 2", "via marignano, 3",
               "via calizzano", "parco lambro", "quadrilatero della moda",
               "via fra' cristoforo"),
      to = c("cadorna - castello", "cadorna - castello", "santa giulia",
             "comasina", "cimiano", "scala - manzoni", "famagosta"),
      stringsAsFactors = FALSE
    ),
    train_size = 6000,
    candidate_runs = 50,
    evaluation_runs = 50,
    selection_seed = 1234,
    protected_patterns = c("zone", "conditions"),
    max_attempts = 100
  )
}
