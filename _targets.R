# Load packages required to define the pipeline:
library(targets)
library(tarchetypes)
library(RPostgres)

# Set target options:
tar_option_set(
  packages = c("DBI", "dbplyr", "tidyverse", "timetk", "tidymodels", "modeltime", "lubridate"), # packages that your targets need to run
  format = "rds"  # Tentei usar parquet porém os modelos davam erro para salvar.
)

# Configure the backend of tar_make_clustermq() (recommended):
options(clustermq.scheduler = "multicore")

# Configure the backend of tar_make_future() (optional):
future::plan(future.callr::callr)

# Load the R scripts with your custom functions:
lapply(list.files("R", full.names = TRUE), source)
# source("other_functions.R") # Source other scripts as needed. # nolint

# Conexão não pode ser definida como target. (?)
con <- dbConnect(
    RPostgres::Postgres(),
    # bigint = "integer",  
    host = "localhost",
    port = 5432,
    user = "postgres",
    password = "postgres",
    dbname = "Adventureworks"
)
# dbDisconnect(con)
# Replace the target list below with your own:
list(
  tar_target(product_data, get_products(con)),
  tar_target(sales_details, get_sales_details(con)),
  tar_target(sales_data, get_sales_orders(con)),
  tar_target(purchase_details, get_purchase_details(con)),
  tar_target(purchase_data, get_purchase_orders(con)),
  tar_target(chain_service_time_data, chain_service_time(purchase_data, purchase_details, product_data, sales_data, sales_details)),
  tar_target(grouped_product_data, group_product_data(sales_details, product_data, purchase_details)),
  tar_target(clean_sales_data, clean_data(grouped_product_data, sales_data, sales_details)),
  tar_target(extended_sales_data, extend_data(clean_sales_data)),
  tar_target(prepared_sales_data, extended_sales_data %>% drop_na()),
  tar_target(future_sales_data, extended_sales_data %>% filter(is.na(value))),
  tar_group_by(
    grouped_prepared_sales_data, 
    prepared_sales_data, 
    productid, 
    region),
  tar_group_by(
    grouped_future_sales_data, 
    future_sales_data, 
    productid, 
    region),
  tar_target(
    name=prepared_sales_data_branched, 
    command=grouped_prepared_sales_data, 
    pattern=map(grouped_prepared_sales_data)
  ),
  tar_target(
    name=future_sales_data_branched, 
    command=grouped_future_sales_data, 
    pattern=map(grouped_future_sales_data)
  ),
  tar_target(
    name=splits_sales_data, 
    command=split_ts_data(prepared_sales_data_branched),
    pattern=map(prepared_sales_data_branched)
  ),
  tar_target(
    name=fit_arima_model, 
    command=fit_arima(splits_sales_data),
    pattern=map(splits_sales_data)
  ),
  tar_target(
    name=test_accuracy_arima, 
    command=test_accuracy(fit_arima_model),
    pattern=map(fit_arima_model)
  ),
  tar_target(
    name=refitted_models,
    command=refit_model(fit_arima_model, prepared_sales_data_branched),
    pattern=map(fit_arima_model, prepared_sales_data_branched)
  ),
  tar_target(
    name=final_forecast,
    pattern=map(
      refitted_models, 
      future_sales_data_branched, 
      prepared_sales_data_branched
    ),
    command=forecast_future(
      refitted_models, 
      future_sales_data_branched, 
      prepared_sales_data_branched
    )
  )
  # tar_target(model, fit_model(data)),
  # tar_target(plot, plot_model(model, data))
)
