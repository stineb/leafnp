#!/usr/bin/env Rscript
args = commandArgs(trailingOnly=TRUE)

#args <- c(46, 100)

library(dplyr)
library(purrr)
library(tidyr)
library(magrittr)
library(rlang)
library(lubridate)
library(ingestr)
library(rsofun)
library(rbeni)
library(pryr)

source("R/ingest_run_rsofun.R")

## read sites data frame
df_sites <- read_csv("data/df_sites_leafnp.csv") %>%
  mutate(idx = 1:n()) %>%
  mutate(chunk = rep(1:as.integer(args[2]), each = (nrow(.)/as.integer(args[2])), len = nrow(.)))

## split sites data frame into (almost) equal chunks
list_df_split <- df_sites %>%
  group_by(chunk) %>%
  group_split()

# ## test
# df_test <- list_df_split %>% bind_rows()
# all_equal(df_test, df_sites)

## retain only the one required for this chunk
df_sites_sub <- list_df_split[[as.integer(args[1])]]

print("This chunk contains these rows of the full site data frame:")
print(df_sites_sub$idx)

##------------------------------------------------------------------------
## ingest forcing data, run P-model, and get climate indeces at once
##------------------------------------------------------------------------
filn <- paste0("data/df_pmodel_ichunk_", args[1], "_", args[2], ".RData")
if (!file.exists(filn)){
  df_pmodel <- ingest_run_rsofun(df_sites_sub, ichunk = args[1], totchunk = args[2], verbose = FALSE)
  save(df_pmodel, file = filn)
} else {
  print(paste("File exists already: ", filn))
}

