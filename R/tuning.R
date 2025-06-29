# Source search ranges, two-fold CV, and a 30-iteration mlrMBO control.
housing_tuning_space <- function(engine, predictor_count) {
  if (engine == "xgboost") {
    ParamHelpers::makeParamSet(
      ParamHelpers::makeNumericParam("nrounds", lower = 2, upper = 3.4, trafo = function(value) as.integer(round(10^value))),
      ParamHelpers::makeNumericParam("eta", lower = -4, upper = 0, trafo = function(value) 10^value),
      ParamHelpers::makeIntegerParam("max_depth", lower = 2, upper = 10),
      ParamHelpers::makeNumericParam("subsample", lower = 0.5, upper = 1),
      ParamHelpers::makeNumericParam("colsample_bytree", lower = 0.5, upper = 1),
      ParamHelpers::makeNumericParam("min_child_weight", lower = 1, upper = 10),
      ParamHelpers::makeNumericParam("gamma", lower = 0, upper = 5))
  } else if (engine == "ranger") {
    ParamHelpers::makeParamSet(
      ParamHelpers::makeIntegerParam("num.trees", lower = 100, upper = 2000),
      ParamHelpers::makeIntegerParam("mtry", lower = 1, upper = max(1L, predictor_count)),
      ParamHelpers::makeIntegerParam("min.node.size", lower = 1, upper = 100),
      ParamHelpers::makeNumericParam("sample.fraction", lower = 0.4, upper = 1),
      ParamHelpers::makeDiscreteParam("replace", values = c("TRUE" = TRUE, "FALSE" = FALSE)),
      ParamHelpers::makeDiscreteParam("splitrule", values = c("variance", "extratrees")))
  } else if (engine == "catboost") {
    ParamHelpers::makeParamSet(
      ParamHelpers::makeNumericParam("iterations", lower = 2, upper = 3.3, trafo = function(value) as.integer(round(10^value))),
      ParamHelpers::makeNumericParam("learning_rate", lower = 0.01, upper = 0.3),
      ParamHelpers::makeIntegerParam("depth", lower = 2, upper = 10),
      ParamHelpers::makeNumericParam("subsample", lower = 0.5, upper = 1),
      ParamHelpers::makeNumericParam("rsm", lower = 0.5, upper = 1),
      ParamHelpers::makeNumericParam("l2_leaf_reg", lower = 1, upper = 10))
  } else stop("Unknown tuning engine.")
}

# Supply an explicitly registered learner for the custom CatBoost experiment.
tune_residual_model <- function(prepared, predictors, engine, learner = NULL) {
  for (package in c("mlr", "mlrMBO", "ParamHelpers")) {
    if (!requireNamespace(package, quietly = TRUE)) stop("Optional tuning package required: ", package)
  }
  if (!"res" %in% names(prepared)) stop("An explicit baseline residual column 'res' is required.")
  task <- mlr::makeRegrTask(data = prepared[, c("res", predictors), drop = FALSE], target = "res")
  if (engine == "xgboost") task <- mlr::createDummyFeatures(task)
  if (is.null(learner)) {
    learner <- switch(engine,
      xgboost = mlr::makeLearner("regr.xgboost", predict.type = "response", par.vals = list(objective = "reg:absoluteerror")),
      ranger = mlr::makeLearner("regr.ranger", predict.type = "response", importance = "impurity", quantreg = TRUE),
      catboost = NULL)
  }
  if (is.null(learner)) stop("Supply the registered custom mlr CatBoost learner.")
  control <- mlrMBO::setMBOControlTermination(mlrMBO::makeMBOControl(), iters = 30)
  mlr::tuneParams(learner = learner, task = task, resampling = mlr::makeResampleDesc("CV", iters = 2),
    measures = if (engine == "xgboost") mlr::mae else mlr::rmse,
    par.set = housing_tuning_space(engine, length(predictors)),
    control = mlr::makeTuneControlMBO(mbo.control = control), show.info = TRUE)
}
