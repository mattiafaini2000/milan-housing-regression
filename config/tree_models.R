housing_tree_configurations <- function() {
  xgb_common <- list(booster = "gbtree", objective = "reg:absoluteerror", eval_metric = "mae")
  xgb_config <- function(rounds, eta, depth, subsample, colsample, child_weight, gamma, target = "residual") {
    list(engine = "xgboost", target = target, rounds = rounds,
         parameters = c(xgb_common, list(eta = eta, max_depth = depth, subsample = subsample,
           colsample_bytree = colsample, min_child_weight = child_weight, gamma = gamma)))
  }
  ranger_config <- function(parameters) {
    list(engine = "ranger", target = "residual", prediction = "response", parameters = parameters)
  }
  list(
    xgb_residual_100 = xgb_config(100, 0.01013058, 8, 0.8291179, 0.998852, 8.460045, 3.601617),
    xgb_residual_7500 = xgb_config(7500, 0.0005013058, 9, 0.5, 0.5, 2.07191, 0.000835919),
    xgb_residual_15000 = xgb_config(15000, 0.00025013058, 9, 0.5, 0.5, 2.07191, 0.000835919),
    xgb_residual_15000_subsample_06 = xgb_config(15000, 0.00025013058, 9, 0.6, 0.5, 2.07191, 0.000835919),
    xgb_direct_35000 = xgb_config(35000, 0.00025013058, 9, 0.6, 0.5, 2.07191, 0.000835919, "direct"),
    ranger_residual_1000 = ranger_config(list(num.trees = 1000, importance = "impurity")),
    ranger_residual_937 = ranger_config(list(num.trees = 937, mtry = 6, min.node.size = 3,
      sample.fraction = 0.8516668, replace = FALSE, splitrule = "variance", importance = "impurity")),
    ranger_residual_420 = ranger_config(list(num.trees = 420, mtry = 6, min.node.size = 1,
      sample.fraction = 0.9634623, replace = FALSE, splitrule = "variance", importance = "impurity")),
    ranger_residual_937_quantreg = ranger_config(list(num.trees = 937, mtry = 6, min.node.size = 3,
      sample.fraction = 0.8516668, replace = FALSE, splitrule = "variance", importance = "impurity", quantreg = TRUE)),
    ranger_residual_420_quantreg = ranger_config(list(num.trees = 420, mtry = 6, min.node.size = 1,
      sample.fraction = 0.9634623, replace = FALSE, splitrule = "variance", importance = "impurity", quantreg = TRUE)),
    ranger_residual_1672 = ranger_config(list(num.trees = 1672, mtry = 9, min.node.size = 1,
      sample.fraction = 0.9720008, replace = FALSE, splitrule = "extratrees", importance = "impurity",
      quantreg = TRUE, respect.unordered.factors = "order", num.random.splits = 20)),
    catboost_direct_1000 = list(engine = "catboost", target = "direct", parameters = list(
      loss_function = "MAE", iterations = 1000, learning_rate = 0.05, depth = 6,
      l2_leaf_reg = 3, random_seed = 123, logging_level = "Silent", allow_writing_files = FALSE))
  )
}
