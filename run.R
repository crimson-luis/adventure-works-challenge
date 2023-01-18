#!/usr/bin/env Rscript
library(targets)

# This is a helper script to run the pipeline.
# Choose how to execute the pipeline below.
# See https://books.ropensci.org/targets/hpc.html
# to learn about your options.

# targets::use_targets()
# Call tar_manifest to see if the targets in the commands
# are actually the ones we expect.
targets::tar_manifest()
targets::tar_visnetwork(targets=TRUE, label="branches")
targets::tar_make()
# targets::tar_make_clustermq(workers = 2) # nolint
# targets::tar_make_future(workers = 2) # nolint

# Previsão.
# forecast_data <- targets::tar_read(final_forecast) 
# forecast_data %>% group_by(
#     tar_group, region
# ) %>% plot_modeltime_forecast(
#     .conf_interval_show=FALSE,
#     .facet_ncol=3
# )