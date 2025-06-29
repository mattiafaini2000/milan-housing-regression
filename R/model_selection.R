# Choose a removable formula term from kernel-based coefficient p-values.
# Factor coefficients are mapped back to their complete formula term.
worst_quantile_term <- function(model, protected_patterns = c("zone", "conditions")) {
  coefficient_table <- stats::coef(summary(model, se = "ker"))
  p_values <- coefficient_table[, "Pr(>|t|)"]
  design <- stats::model.matrix(model)
  term_names <- attr(stats::terms(model), "term.labels")
  assignments <- attr(design, "assign")
  matched <- match(names(p_values), colnames(design))
  assigned <- assignments[matched]
  term_by_coefficient <- rep(NA_character_, length(p_values))
  is_term <- !is.na(assigned) & assigned > 0L
  term_by_coefficient[is_term] <- term_names[assigned[is_term]]
  protected <- rep(FALSE, length(p_values))
  for (pattern in protected_patterns) {
    protected <- protected | grepl(pattern, names(p_values)) |
      (!is.na(term_by_coefficient) & grepl(pattern, term_by_coefficient))
  }
  eligible <- which(is_term & !protected & is.finite(p_values))
  if (!length(eligible)) return(NULL)
  worst_index <- eligible[which.max(p_values[eligible])]
  list(term = term_by_coefficient[worst_index],
       coefficient = names(p_values)[worst_index], p_value = unname(p_values[worst_index]))
}

# Select the minimum holdout MAE along the source backward-elimination path.
backward_quantile_selection <- function(training, heldout, formula, config) {
  terms <- attr(stats::terms(formula), "term.labels")
  predictors <- all.vars(formula)[-1L]
  if (length(terms) != length(predictors) ||
      !identical(sort(gsub("`", "", terms, fixed = TRUE)), sort(predictors))) {
    stop("Backward selection requires an explicit additive formula without interactions.")
  }
  formulas <- list()
  scores <- list()
  current_formula <- formula
  maximum_fits <- max(1L, length(predictors) - 3L)
  for (step in seq_len(maximum_fits)) {
    model <- fit_quantile_model(training, current_formula, config$tau)
    score <- price_error_summary(heldout$selling_price, predict_quantile_prices(model, heldout))
    if (!is.finite(score$mae)) stop("A backward-selection fit produced nonfinite MAE.")
    worst <- worst_quantile_term(model, config$protected_patterns)
    formulas[[step]] <- current_formula
    scores[[step]] <- cbind(
      data.frame(step = step, predictor_count = length(predictors),
                 removed_term = if (is.null(worst)) "" else worst$term,
                 removed_coefficient = if (is.null(worst)) "" else worst$coefficient,
                 removed_p_value = if (is.null(worst)) NA_real_ else worst$p_value), score)
    if (is.null(worst)) break
    predictors <- setdiff(predictors, gsub("`", "", worst$term, fixed = TRUE))
    current_formula <- housing_formula(predictors, target = config$target)
  }
  score_table <- do.call(rbind, scores)
  best_step <- which.min(score_table$mae)
  list(formula = formulas[[best_step]], selected_step = best_step,
       selection_mae = score_table$mae[best_step], path = score_table,
       formulas = formulas)
}

selection_data_pool <- function(data, config) {
  included <- !as.character(data$ID) %in% as.character(config$excluded_ids)
  data <- data[included, , drop = FALSE]
  data$zone <- recode_housing_zones(data$zone, config$zone_replacements)
  data
}

prepare_selection_split <- function(data, split, config, preprocessing, global) {
  if (identical(preprocessing, "global")) {
    list(training = global$data[split$training, , drop = FALSE],
         heldout = global$data[split$holdout, , drop = FALSE], state = global$state)
  } else {
    fitted <- fit_preprocessor(data[split$training, , drop = FALSE], config)
    list(training = fitted$data,
         heldout = transform_housing_data(data[split$holdout, , drop = FALSE], fitted$state),
         state = fitted$state)
  }
}

# Repeat candidate generation and re-evaluation, recording bounded retry failures.
# 'global' follows the supplied preprocessing order; 'split' learns imputation
# and feature vocabulary on each training partition.
evaluate_quantile_selection <- function(data, config, formula = NULL,
                                        selection_repeats = 50L,
                                        evaluation_repeats = 50L,
                                        max_attempts = 100L,
                                        preprocessing = c("global", "split"),
                                        seed = 1234L) {
  preprocessing <- match.arg(preprocessing)
  if (any(c(selection_repeats, evaluation_repeats) < 1L) ||
      max_attempts < max(selection_repeats, evaluation_repeats)) {
    stop("Repeats must be positive, with max_attempts at least as large as either repeat count.")
  }
  with_local_seed(seed, {
    pool <- selection_data_pool(data, config)
    global <- if (preprocessing == "global") fit_preprocessor(pool, config) else NULL
    split_data <- if (preprocessing == "global") global$data else pool
    candidates <- list()
    failures <- list()
    selection_splits <- list()
    attempt <- 0L
    while (length(candidates) < selection_repeats && attempt < max_attempts) {
      attempt <- attempt + 1L
      outcome <- tryCatch({
        split <- zone_stratified_split(split_data, train_size = config$train_size)
        prepared <- prepare_selection_split(pool, split, config, preprocessing, global)
        initial_formula <- if (is.null(formula)) {
          housing_formula(prepared$state$predictors, config$target)
        } else formula
        candidate <- backward_quantile_selection(prepared$training, prepared$heldout,
                                                initial_formula, config)
        list(candidate = candidate, split = split)
      }, error = function(error) error)
      if (inherits(outcome, "error")) {
        failures[[length(failures) + 1L]] <- data.frame(
          phase = "selection", attempt = attempt, error = conditionMessage(outcome))
      } else {
        outcome$candidate$attempt <- attempt
        candidates[[length(candidates) + 1L]] <- outcome$candidate
        selection_splits[[length(selection_splits) + 1L]] <- outcome$split
      }
    }
    selection_attempts <- attempt
    if (!length(candidates)) {
      return(list(candidates = candidates, completed_selection = 0L,
                  requested_selection = selection_repeats, completed_evaluation = 0L,
                  requested_evaluation = evaluation_repeats, failures = do.call(rbind, failures),
                  selection_splits = selection_splits, evaluation_splits = list(),
                  row_ids = as.character(split_data$ID), config = config,
                  preprocessing = preprocessing, seed = seed,
                  selection_attempts = selection_attempts, evaluation_attempts = 0L))
    }
    evaluation_scores <- list()
    evaluation_splits <- list()
    completed <- 0L
    attempt <- 0L
    while (completed < evaluation_repeats && attempt < max_attempts) {
      attempt <- attempt + 1L
      outcome <- tryCatch({
        split <- zone_stratified_split(split_data, train_size = config$train_size)
        prepared <- prepare_selection_split(pool, split, config, preprocessing, global)
        scores <- lapply(seq_along(candidates), function(candidate_id) {
          model <- fit_quantile_model(prepared$training, candidates[[candidate_id]]$formula, config$tau)
          cbind(data.frame(candidate = candidate_id),
                price_error_summary(prepared$heldout$selling_price,
                                    predict_quantile_prices(model, prepared$heldout)))
        })
        scores <- do.call(rbind, scores)
        if (any(!is.finite(scores$mae))) stop("A candidate produced nonfinite evaluation MAE.")
        list(scores = scores, split = split)
      }, error = function(error) error)
      if (inherits(outcome, "error")) {
        failures[[length(failures) + 1L]] <- data.frame(
          phase = "evaluation", attempt = attempt, error = conditionMessage(outcome))
      } else {
        completed <- completed + 1L
        outcome$scores$repeat_id <- completed
        outcome$scores$attempt <- attempt
        evaluation_scores[[completed]] <- outcome$scores
        evaluation_splits[[completed]] <- outcome$split
      }
    }
    scores <- if (length(evaluation_scores)) do.call(rbind, evaluation_scores) else NULL
    summary <- if (is.null(scores)) NULL else do.call(rbind, lapply(seq_along(candidates), function(candidate_id) {
      candidate_scores <- scores[scores$candidate == candidate_id, , drop = FALSE]
      data.frame(candidate = candidate_id, mean_mae = mean(candidate_scores$mae),
                 sd_mae = stats::sd(candidate_scores$mae),
                 successful_repeats = nrow(candidate_scores),
                 predictor_count = length(attr(stats::terms(candidates[[candidate_id]]$formula), "term.labels")))
    }))
    list(candidates = candidates, summary = summary, scores = scores,
         failures = if (length(failures)) do.call(rbind, failures) else
           data.frame(phase = character(), attempt = integer(), error = character()),
         selection_splits = selection_splits, evaluation_splits = evaluation_splits,
         row_ids = as.character(split_data$ID), completed_selection = length(candidates),
         requested_selection = selection_repeats, completed_evaluation = completed,
         requested_evaluation = evaluation_repeats, selection_attempts = selection_attempts,
         evaluation_attempts = attempt, preprocessing = preprocessing, seed = seed,
         config = config)
  })
}
