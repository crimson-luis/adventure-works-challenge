get_products <- function(con) {
    tbl(con, in_schema("production", "product")) %>% collect() %>%
    select(
        productid, 
        name, 
        daystomanufacture, 
        standardcost, 
        listprice
    ) %>% mutate(profit=listprice - standardcost)
}

get_purchase_orders <- function(con) {
    tbl(con, in_schema("purchasing", "purchaseorderheader")) %>% filter(
        status %in% c("1", "2", "4")
    ) %>% collect() %>% select(
        purchaseorderid,
        orderdate,
        shipdate,
        subtotal,
        taxamt,
        freight
    ) %>% mutate(totaldue=subtotal + taxamt + freight)
}

get_purchase_details <- function(con) {
    tbl(con, in_schema("purchasing", "purchaseorderdetail")) %>% collect() %>%
    select(
        purchaseorderid,
        # duedate,
        orderqty,
        productid,
        unitprice
    ) %>% mutate(totalcost=orderqty * unitprice)
}

get_sales_orders <- function(con) {
    tbl(con, in_schema("sales", "salesorderheader")) %>%
    left_join(
        tbl(con, in_schema("sales", "salesterritory")), 
        by="territoryid"
    ) %>% filter(
        status %in% c("1", "2", "5")
    ) %>% collect() %>%
    select(
        salesorderid,
        orderdate,
        # duedate, 
        shipdate,
        group,
        subtotal
    )
}

get_sales_details <- function(con) {
    tbl(con, in_schema("sales", "salesorderdetail")) %>% collect() %>% 
    select(
        salesorderid,
        salesorderdetailid,
        productid,
        orderqty,
        unitprice,
        unitpricediscount
    ) %>% mutate(
        finalprice=unitprice * (1 - unitpricediscount),
        totalprice=orderqty * finalprice
    )
}

chain_service_time <- function(data1, data2, data3, data4, data5) {
    #  COMPRAS (9 ou 25 dias)
    daystoshippurchase <- data1 %>% left_join(
        data2, by="purchaseorderid"
    ) %>% mutate(
        daystoshippurchase = as.numeric(difftime(ymd(shipdate), 
        ymd(orderdate), units = "days"))
    ) %>% select(productid, daystoshippurchase) %>% distinct()
    #  PRODUÇÃO (0, 1, 2 ou 4 dias)
    daystomanufactureproduct <- data3 %>% select(
        productid,
        daystomanufacture
    ) %>% distinct()
    #  ENTREGAS (7 ou 8 dias)
    daystoshipsale <- data4 %>% left_join(
        data5, by="salesorderid"
    ) %>% mutate(
        daystoshipsale = as.numeric(difftime(ymd(shipdate), 
        ymd(orderdate), units = "days"))
    ) %>% select(productid, daystoshipsale) %>% distinct()

    daystoshippurchase %>% full_join(
        daystomanufactureproduct, 
        by="productid"
    ) %>% full_join(
        daystoshipsale, 
        by="productid"
    )
}

group_product_data <- function(data1, data2, data3) {
    grouped_sales_details <- data1 %>% left_join(
        data2, by="productid"
    ) %>% collect() %>% select(
        # product_data
        productid,
        name,
        # sales_details
        orderqty,
        totalprice
    ) %>% group_by(productid, name) %>% summarise(
        sumorders=sum(orderqty),
        sumprice=sum(totalprice)
        )
    grouped_purchase_details <- data3 %>%
    group_by(productid) %>% summarise(
        sumcost=sum(totalcost)
    )
    grouped_sales_details %>% left_join(
        grouped_purchase_details, by="productid"
    ) %>% mutate(sumprofit=sumprice - sumcost)
}

clean_data <- function(data1, data2, data3) {
    top_products <- data1 %>% as.data.frame() %>% slice_max(
        order_by = sumorders, n = 5
    ) %>% pull(productid)
    
    data2 %>% left_join(
        data3, by="salesorderid"
    ) %>% rename(
        region=group,
        date=orderdate,
        value=orderqty
    ) %>% select(
        date,
        productid,
        region,
        # onlineorderflag,
        # freight,
        # unitpricediscount,
        # unitprice,
        value
    ) %>% filter(productid %in% top_products) %>% group_by(
        productid, 
        region, 
        date
    ) %>% summarise(value=sum(value))
}

extend_data <- function(data) {
    data %>% distinct() %>% group_by(
        productid,
        region
    ) %>% future_frame(
        date, 
        .length_out=24, 
        .bind_data=TRUE
    ) %>% ungroup() %>% distinct()
}

split_ts_data <- function(data) {
    data <- ungroup(data)
    splits <- timetk::time_series_split(
        data, date_var=date, cumulative=TRUE, assess=24
    )
    tibble(
        tar_group=data$tar_group %>% unique(),
        splits=list(splits)
    )
}

fit_arima <- function(splits_table) {
    tar_group <- splits_table %>% pull(tar_group) %>% unique()
    train_table <- splits_table %>% pull(splits) %>% pluck(1) %>% training()
    workflow_fit <- workflow() %>% add_model(
        spec=arima_reg() %>% set_engine("auto_arima")
    ) %>% add_recipe(
        recipe=recipe(value ~ date, train_table)
    ) %>% fit(train_table)
    final <- tibble(tar_group=tar_group, workflow_fit=list(workflow_fit))
    final <- splits_table %>% mutate(workflow_fit=list(workflow_fit))
    return(final)
}

test_accuracy <- function(model_table) {
    tar_group <- model_table %>% pull(tar_group) %>% unique()
    test_table <- model_table %>% pull(splits) %>% pluck(1) %>% testing()
    workflow_fit <- model_table %>% pull(workflow_fit) %>% pluck(1)
    modeltime_table(workflow_fit) %>% modeltime_accuracy(
        test_table
    ) %>% add_column(tar_group = tar_group, .before=1)
}

refit_model <- function(model_table, data) {
    tar_group <- model_table %>% pull(tar_group) %>% unique()
    modeltime_table(
        model_table$workflow_fit[[1]]
    ) %>% modeltime_refit(data) %>% mutate(tar_group=tar_group)
}

forecast_future <- function(refit_table, future_data, data) {
    refit_table %>% select(-tar_group) %>% modeltime_forecast(
        new_data=future_data,
        actual_data=data,
        keep_data=TRUE
    )
}

check_accuracy <- function(accuracy_table) {
    accuracy_check <- accuracy_table %>% filter(
        rsq < 0.15
    ) %>% select(tar_group) %>% mutate(
        error_desc = "R2 menor que 0.15. Previsão com baixa variância"
    )
}
