## ----setup, include=FALSE-------------------------------------------------------------
library(tidyverse)
library(ranger)
library(caret)
library(visdat)
library(vip)
library(pdp)


## -------------------------------------------------------------------------------------
df <- read_csv("~/data/LeafNP_tiandi/Global_total_leaf_N_P_Di/soil_property_extraction_20210323/global_leaf_NP_with_soil_property_from_HWSD_WISE_GSDE_Pmodel_Ndep_GTI_CO2_25032021.csv")

trgts <- c("leafN", "leafP", "LeafNP")
preds <- c("ORGC",  "TOTN",  "CNrt",  "ALSA",  "elv", "AWC_CLASS", "T_GRAVEL",  "T_SAND",  "T_SILT",  "T_CLAY",  "T_REF_BULK_DENSITY",  "T_BULK_DENSITY",  "T_OC",  "T_PH_H2O", "T_CEC_CLAY",  "T_CEC_SOIL",  "T_BS",  "T_TEB",  "T_CACO3",  "T_ESP",  "T_ECE",  "PBR", "PHH2O",  "gti",  "ndep",  "co2",  "mat",  "matgs",  "tmonthmin",  "tmonthmax", "ndaysgs",  "mai",  "maigs",  "map",  "pmonthmin",  "mapgs",  "mavgs",  "mav", "alpha",  "vcmax25",  "jmax25",  "gs_accl",  "aet",  "ai",  "cwdx80")


## -------------------------------------------------------------------------------------
dfs <- df %>% 
  mutate(elv_grp = elv) %>% 
  group_by(lon, lat, elv_grp, sitename) %>% 
  summarise(across(c(preds, trgts), ~(mean(.x, na.rm = TRUE)))) %>% 
  left_join(df %>% 
              group_by(sitename) %>% 
              summarise(nobs = n()),
            by = "sitename")


## -------------------------------------------------------------------------------------
vis_miss(dfs)


## -------------------------------------------------------------------------------------
# dfs <- dfs %>% 
#   dplyr::filter(nobs >= 3)


## -------------------------------------------------------------------------------------
mod_rf_leafn <- ranger(
  leafN ~ ., 
  data = dfs %>% 
    drop_na() %>% 
    dplyr::select(leafN, preds),
  mtry = floor(length(preds) / 3),
  respect.unordered.factors = "order",
  seed = 123
)

## RMSE and R2
sqrt(mod_rf_leafn$prediction.error)
mod_rf_leafn$r.squared


## -------------------------------------------------------------------------------------
# create hyperparameter grid
hyper_grid <- expand.grid(
  mtry = floor(length(preds) * c(.1, .15, .25, .333, .4)),
  min.node.size = c(3, 5, 10), 
  replace = c(TRUE, FALSE),                               
  sample.fraction = c(.5, .7, .8),                       
  rmse = NA                                               
)

# execute full cartesian grid search
for(i in seq_len(nrow(hyper_grid))) {
  # fit model for ith hyperparameter combination
  fit <- ranger(
    formula         = leafN ~ ., 
    data = dfs %>% 
      ungroup() %>% 
      drop_na() %>% 
      dplyr::select(leafN, preds),
    num.trees       = length(preds) * 10,
    mtry            = hyper_grid$mtry[i],
    min.node.size   = hyper_grid$min.node.size[i],
    replace         = hyper_grid$replace[i],
    sample.fraction = hyper_grid$sample.fraction[i],
    verbose         = FALSE,
    seed            = 123,
    respect.unordered.factors = 'order',
  )
  # export OOB error 
  hyper_grid$rmse[i] <- sqrt(fit$prediction.error)
}

# assess top 10 models
hyper_grid %>%
  arrange(rmse) %>%
  head(10)

## save the best combination
best_hyper <- hyper_grid %>% 
  arrange(rmse) %>% 
  slice(1)


## -------------------------------------------------------------------------------------
traincotrlParams <- trainControl( 
  method="cv", 
  number=5, 
  verboseIter=FALSE,
  savePredictions = "final"
  )

tune_grid <- expand.grid( .mtry = best_hyper$mtry, 
                          .min.node.size = best_hyper$min.node.size,
                          .splitrule = "variance"
                          ) 

set.seed(1982)

mod_rf_caret_leafn <- train(
  leafN ~ .,
  data = dfs %>% 
    ungroup() %>% 
    drop_na() %>% 
    dplyr::select(leafN, preds),
  metric    = "RMSE",
  method    = "ranger",
  tuneGrid  = tune_grid,
  trControl = traincotrlParams,
  replace = best_hyper$replace,
  sample.fraction = best_hyper$sample.fraction,
  na.action = na.omit,
  num.trees = 2000,         # boosted for the final model
  importance = "impurity"   # for variable importance analysis, alternative: "permutation"
  )


## -------------------------------------------------------------------------------------
## get predicted values from cross-validation resamples, take mean across repetitions
df_cv <- mod_rf_caret_leafn$pred %>% 
  as_tibble() %>% 
  dplyr::filter(mtry == mod_rf_caret_leafn$bestTune$mtry, 
                splitrule == mod_rf_caret_leafn$bestTune$splitrule, 
                min.node.size == mod_rf_caret_leafn$bestTune$min.node.size) %>%
  mutate(fold = as.integer(stringr::str_remove(Resample, "Fold"))) %>% 
  dplyr::rename(idx = rowIndex) %>% 
  left_join(
    dfs %>% 
      ungroup() %>% 
      drop_na() %>% 
      dplyr::select(leafN) %>% 
      mutate(idx = seq(nrow(.))),
    by = "idx"
    ) %>% 
  dplyr::select(obs = leafN, mod = pred)

out <- df_cv %>% 
  rbeni::analyse_modobs2("mod", "obs", type = "heat")
out$gg +
  ylim(5,40) + xlim(5,40)


## -------------------------------------------------------------------------------------
p1 <- vip(mod_rf_caret_leafn$finalModel, num_features = 45, bar = FALSE)
p1


## -------------------------------------------------------------------------------------
pdp_pred <- function(object, newdata){
  results <- mean(predict(object, newdata))$predictions
  return(results)
}

out <- partial(mod_rf_caret_leafn$finalModel, 
        train = dfs %>% 
          ungroup() %>% 
          drop_na() %>% 
          dplyr::select(leafN, preds),
        pred.var = "vcmax25",
        # pred.fun = pdp_pred,
        grid.resolution = 50
)
head(out)
autoplot(out, rug = TRUE, train = as.data.frame(dfs %>% 
          ungroup() %>% 
          drop_na() %>% 
          dplyr::select(leafN, preds)))

