# ================================================================================================
# Description: generate xgboost solution
#
# Input: 
# train = model build dataset
# valid = roc validation hold out dataset
# test = dataset used for kaggle submission
#
# Output: 
# final_xgb_model = parameted tuned gradient boosted model
# predictions = predicted values using xgboost
#
# Author: E Walsh
#
# Dependencies: 
# run via main script to load all the packages and data
#
# Notes:
#
# Issues:
#
# History (reverse order): 
# 04 Feb 2018 EW researched suggested hyper tuning parameters and implemented
# 01 Feb 2018 EW v1
# ================================================================================================

print("Building xgboost solution...")


# note that data must be in matrix format to run xgboost



train.matrix = xgb.DMatrix(data = as.matrix(train %>% select(-is_female, -id)), label = as.numeric(as.character(train$is_female)))
valid.matrix = xgb.DMatrix(data = as.matrix(valid %>% select(-is_female, -id)), label = as.numeric(as.character(valid$is_female)))
test.matrix = xgb.DMatrix(data = as.matrix(test %>% select(-id) ))


# ensure both the training and validation data is evaluated at each iteration
watch_sets = list(train = train.matrix, valid = valid.matrix)


# an initial stab at parameters for the grid search as suggested by Zhang (2018) and  Abhishek (2018)
# https://machinelearningmastery.com/configure-gradient-boosting-algorithm/
# if this takes too long to run faster methods are shown in the links below
# https://cambridgespark.com/content/tutorials/hyperparameter-tuning-in-xgboost/index.html
# https://www.analyticsvidhya.com/blog/2016/03/complete-guide-parameter-tuning-xgboost-with-codes-python/
tuning_grid <- expand.grid(
  max_depth         = c(6, 8, 10),            # depth of the tree - note we do have a large number of variables to choose from
  eta               = c(0.01, 0.05),          # learning rate
  subsample         = c(.75, 1.0),        # proportion of obs supplied to the tree
  colsample_bytree  = c(0.6, 0.8),       # proportion of features supplied to the tree
  gamma             = c(0.05), # regularisation gamma - probably need to look at train vs valid error to decide value
  min_child_weight  = c(1.36, 2),             # minimum weight to stop the node from splitting first val is 1/sqrt(event)
  alpha             = c(0)     # L1 regularisation - extra feature selection Lasso style
)

# perform a grid search on the parameters 
hyper_parameters <- apply(tuning_grid, 1, function(grid_values){
  # pull the columns out of the data frame
  max_depth_col        = grid_values[["max_depth"]];
  eta_col              = grid_values[["eta"]];
  subsample_col        = grid_values[["subsample"]];
  colsample_bytree_col = grid_values[["colsample_bytree"]];
  gamma_col            = grid_values[["gamma"]];
  min_child_weight_col = grid_values[["min_child_weight"]];
  alpha_col            = grid_values[["alpha"]];
  
  print(paste0("Depth: ", max_depth_col, " Eta: ", eta_col, " Subsample: ", subsample_col, 
               " Colsample: ", colsample_bytree_col, " Gamma: ", gamma_col, 
               " Minchild weight: ", min_child_weight_col, " Alpha: ", alpha_col))
  
  opt_cv <- xgb.cv(data = train.matrix, 
                   nrounds          = 500, 
                   nfold            = 10, 
                   classProbs       = TRUE,
                   showsd           = TRUE,
                   objective        = "binary:logistic", 
                   metrics          = list("auc", "error"),
                   verbose          = 1,
                   nthread          = 4,
                   max_depth        = max_depth_col,
                   eta              = eta_col,
                   subsample        = subsample_col,
                   colsample_bytree = colsample_bytree_col,
                   gamma            = gamma_col,
                   min_child_weight = min_child_weight_col,
                   alpha            = alpha_col,
                   early.stop.round = 50,
                   maximize         = FALSE
                   
  );
  
  
  validation_scores <- as.data.frame(opt_cv$evaluation_log);
  error_val <- tail(validation_scores$test_error_mean, 1);
  auc_val <- tail(validation_scores$test_auc_mean, 1);
  best_iter <- which.max(validation_scores[, "test_auc_mean"]);
  
  return(c(max_depth_col, 
           eta_col, 
           subsample_col, 
           colsample_bytree_col, 
           best_iter, 
           gamma_col,
           min_child_weight_col,
           alpha_col,
           auc_val, 
           error_val))
});


# find the optimal parameters for the model
opt_max_depth <- hyper_parameters[1 , which(hyper_parameters[9, ] == max(hyper_parameters[9, ]))];
opt_eta <- hyper_parameters[2 , which(hyper_parameters[9, ] == max(hyper_parameters[9, ]))];
opt_subsample <- hyper_parameters[3 , which(hyper_parameters[9, ] == max(hyper_parameters[9, ]))];
opt_colsample <- hyper_parameters[4 , which(hyper_parameters[9, ] == max(hyper_parameters[9, ]))];
opt_num_rounds <- hyper_parameters[5 , which(hyper_parameters[9, ] == max(hyper_parameters[9, ]))];
opt_gamma <- hyper_parameters[6 , which(hyper_parameters[9, ] == max(hyper_parameters[9, ]))];
opt_min_child_weight <- hyper_parameters[7 , which(hyper_parameters[9, ] == max(hyper_parameters[9, ]))];
opt_alpha <- hyper_parameters[8 , which(hyper_parameters[9, ] == max(hyper_parameters[9, ]))];


# run the final model based on the results from the tuning
opt_param <- list(booster          = "gbtree",
                  max_depth        = opt_max_depth, 
                  eta              = opt_eta, 
                  subsample        = opt_subsample,
                  colsample_bytree = opt_colsample,
                  nrounds          = opt_num_rounds,
                  gamma            = opt_gamma,
                  min_child_weight = opt_min_child_weight,
                  alpha            = opt_alpha
                  
)


final_xgb_model <- xgb.train(
  params      = opt_param, 
  data        = train.matrix, 
  objective   = "binary:logistic", 
  eval_metric = "auc",
  maximize    = FALSE,
  watchlist   = watch_sets,
  nrounds     = opt_num_rounds
);

# check out the feature importance
final_model_dump <- xgb.dump(final_xgb_model, with_stats = TRUE);
importance_mat <- xgb.importance (feature_names = colnames(train), model = final_xgb_model)
xgb.plot.importance(importance_mat, cex=0.7);


# generate predictions
predictions<- data.frame(test_id = test$id, predictions = predict(final_xgb_model, newdata = test.matrix))
submit_predictions(predictions, paste("./output/submission",
                                      format(Sys.time(), "%Y%m%d"),
                                      ".csv", 
                                      sep = ""))
