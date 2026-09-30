# DAX Measures
 
All measures live in the `_Measures` table, an empty table that holds only measures. Formulas below are exported directly from the model.
 
**Table names in the model**
 
| Model name | Source |
|---|---|
| `rpt vw_valid_sales` | `rpt.vw_valid_sales` (fact table, one row per valid sales line) |
| `rpt vw_customer_summary` | `rpt.vw_customer_summary` (one row per customer) |
| `rpt customer_segments` | `rpt.customer_segments` (RFM segment and churn output from Python, 5,852 rows) |
| `dim product`, `dim customer`, `dim date` | Star schema dimensions |
 
**Guest checkouts:** orders without a customer ID use `customer_key = -1`. Customer-level measures exclude them.
 
## Contents
 
1. [Overview page](#1-overview-page)
2. [Products page](#2-products-page)
3. [Repeat Customer Behavior page](#3-repeat-customer-behavior-page)
4. [Customer Segmentation page](#4-customer-segmentation-page)
5. [Churn Risk page](#5-churn-risk-page)
6. [Calculated columns](#6-calculated-columns)
7. [Notes and overlaps](#7-notes-and-overlaps)
---
 
## 1. Overview page
 
### Total Revenue
Sum of valid sales value in the current filter context.
```DAX
Total Revenue =
SUM('rpt vw_valid_sales'[sales_amount])
```
Used in: KPI card, monthly revenue line, revenue by country bar, Top 10 products by revenue. Feeds `AOV` and the Pareto measures.
 
### Total Orders
Distinct invoices.
```DAX
Total Orders =
DISTINCTCOUNT('rpt vw_valid_sales'[invoice])
```
Used in: KPI card. Feeds `AOV`.
 
### Total Customers
Distinct identified customers. Guests (`customer_key = -1`) are excluded.
```DAX
Total Customers =
CALCULATE(
    DISTINCTCOUNT('rpt vw_valid_sales'[customer_key]),
    'rpt vw_valid_sales'[customer_key] <> -1
)
```
Used in: KPI card.
 
### AOV
Average order value: revenue divided by orders. `DIVIDE` returns blank instead of an error when there are no orders.
```DAX
AOV =
DIVIDE([Total Revenue], [Total Orders])
```
Used in: KPI card.
 
---
 
## 2. Products page
 
### Total Quantity
Units sold.
```DAX
Total Quantity =
SUM('rpt vw_valid_sales'[quantity])
```
Used in: Top 10 products by quantity bar.
 
### Product Revenue Rank
Ranks every product by revenue, highest first. `ALL` ignores the chart's own filters so the rank is fixed.
```DAX
Product Revenue Rank =
RANKX(
    ALL('dim product'[description]),
    [Total Revenue],
    ,
    DESC
)
```
Used in: helper for the Pareto measures.
 
### Cumulative Revenue
Revenue of all products ranked at or above the current product.
```DAX
Cumulative Revenue =
VAR CurrentRank = [Product Revenue Rank]
RETURN
CALCULATE(
    [Total Revenue],
    FILTER(
        ALL('dim product'[description]),
        [Product Revenue Rank] <= CurrentRank
    )
)
```
Used in: not plotted on any visual. `Cumulative Revenue %` does not reference it (see [Notes](#7-notes-and-overlaps)).
 
### Cumulative Revenue %
Running share of total revenue, products sorted by revenue descending. Drives the line on the Pareto chart. It uses `ALLSELECTED` so the running total stays tied to the products plotted on the chart. With `ALL` the line stayed flat.
```DAX
Cumulative Revenue % =
VAR CurrentRank = [Product Revenue Rank]
VAR TotalAllProducts = CALCULATE([Total Revenue], ALL('dim product'))
VAR RunningTotal =
    CALCULATE(
        [Total Revenue],
        FILTER(
            ALLSELECTED('dim product'[description]),
            [Product Revenue Rank] <= CurrentRank
        )
    )
RETURN
DIVIDE(RunningTotal, TotalAllProducts)
```
Used in: Pareto chart (line, secondary axis). The column series is `Total Revenue`.
 
---
 
## 3. Repeat Customer Behavior page
 
### Repeat Rate %
Share of identified customers with more than one order.
```DAX
Repeat Rate % =
DIVIDE(
    CALCULATE(
        DISTINCTCOUNT('rpt vw_customer_summary'[customer_id]),
        'rpt vw_customer_summary'[is_repeat_customer] = 1
    ),
    CALCULATE(
        DISTINCTCOUNT('rpt vw_customer_summary'[customer_id]),
        'rpt vw_customer_summary'[customer_id] <> -1
    )
)
```
Used in: KPI card (72%).
 
### Median Days to Second Order
Median gap between first and second order. Customers with one order have a blank value and are left out, so they do not pull the median toward zero.
```DAX
Median Days to Second Order =
MEDIANX(
    FILTER(
        'rpt vw_customer_summary',
        NOT ISBLANK('rpt vw_customer_summary'[days_to_second_order])
    ),
    'rpt vw_customer_summary'[days_to_second_order]
)
```
Used in: KPI card (57 days).
 
### Repeat Revenue Share %
Share of customer revenue that comes from repeat customers.
```DAX
Repeat Revenue Share % =
DIVIDE(
    CALCULATE(
        SUM('rpt vw_customer_summary'[total_revenue]),
        'rpt vw_customer_summary'[is_repeat_customer] = 1
    ),
    SUM('rpt vw_customer_summary'[total_revenue])
)
```
Used in: KPI card (97%).
 
### Repeat Rate % by Country
Repeat rate for each country. `CROSSFILTER` makes the filter travel from `dim customer` to the sales table inside this measure only, so the global relationship stays single-direction and other pages are unaffected.
```DAX
Repeat Rate % by Country =
VAR RepeatCustomers =
    CALCULATE(
        DISTINCTCOUNT('rpt vw_customer_summary'[customer_id]),
        'rpt vw_customer_summary'[is_repeat_customer] = 1,
        CROSSFILTER('rpt vw_valid_sales'[customer_key], 'dim customer'[customer_surrogate_key], BOTH)
    )
VAR TotalCustomers =
    CALCULATE(
        DISTINCTCOUNT('rpt vw_customer_summary'[customer_id]),
        'rpt vw_customer_summary'[customer_id] <> -1,
        CROSSFILTER('rpt vw_valid_sales'[customer_key], 'dim customer'[customer_surrogate_key], BOTH)
    )
RETURN
DIVIDE(RepeatCustomers, TotalCustomers)
```
Used in: Repeat rate percentage per country bar.
 
### Country Customer Count
Distinct identified customers, used to limit the country chart to countries with 20 or more customers so tiny markets do not distort the ranking.
```DAX
Country Customer Count =
CALCULATE(
    DISTINCTCOUNT('rpt vw_valid_sales'[customer_key]),
    'rpt vw_valid_sales'[customer_key] <> -1
)
```
Used in: visual-level filter on the country bar. The formula is identical to `Total Customers` (see [Notes](#7-notes-and-overlaps)).
 
### % of Customers
Share of identified customers in each Customer Type (Repeat or One-Time). `ALL` on `Customer Type` keeps the denominator at the full customer base, so this only works with `Customer Type` on the axis or legend.
```DAX
% of Customers =
DIVIDE(
    CALCULATE(
        DISTINCTCOUNT('rpt vw_customer_summary'[customer_id]),
        'rpt vw_customer_summary'[customer_id] <> -1
    ),
    CALCULATE(
        DISTINCTCOUNT('rpt vw_customer_summary'[customer_id]),
        'rpt vw_customer_summary'[customer_id] <> -1,
        ALL('rpt vw_customer_summary'[Customer Type])
    )
)
```
Used in: Repeat vs One-Time clustered bar.
 
### % of Revenue
Share of customer revenue in each Customer Type. Same `ALL` pattern as `% of Customers`.
```DAX
% of Revenue =
DIVIDE(
    CALCULATE(SUM('rpt vw_customer_summary'[total_revenue])),
    CALCULATE(
        SUM('rpt vw_customer_summary'[total_revenue]),
        ALL('rpt vw_customer_summary'[Customer Type])
    )
)
```
Used in: Repeat vs One-Time clustered bar.
 
---
 
## 4. Customer Segmentation page
 
### % of Customers by Segment
Share of customers in each RFM segment. `ALL` on `Segment` keeps the denominator at all 5,852 customers.
```DAX
% of Customers by Segment =
DIVIDE(
    CALCULATE(DISTINCTCOUNT('rpt customer_segments'[customer_id])),
    CALCULATE(
        DISTINCTCOUNT('rpt customer_segments'[customer_id]),
        ALL('rpt customer_segments'[Segment])
    )
)
```
Used in: Percentage of revenue and customers by segment (clustered bar).
 
### % of Revenue by Segment
Share of customer revenue (`Monetary`) in each RFM segment.
```DAX
% of Revenue by Segment =
DIVIDE(
    CALCULATE(SUM('rpt customer_segments'[Monetary])),
    CALCULATE(
        SUM('rpt customer_segments'[Monetary]),
        ALL('rpt customer_segments'[Segment])
    )
)
```
Used in: Percentage of revenue and customers by segment (clustered bar).
 
### AOV by Type
Revenue divided by distinct invoices in the current context. Placed against customer type, it gives AOV for Wholesale and Retail.
```DAX
AOV by Type =
DIVIDE(
    SUM('rpt vw_valid_sales'[sales_amount]),
    DISTINCTCOUNT('rpt vw_valid_sales'[invoice])
)
```
Used in: CLV and AOV of customer segment (Wholesale vs Retail bar). The formula is equivalent to `AOV`.
 
### CLV by Type
Customer lifetime value proxy: revenue divided by distinct identified customers in the current context.
```DAX
CLV by Type =
DIVIDE(
    SUM('rpt vw_valid_sales'[sales_amount]),
    CALCULATE(
        DISTINCTCOUNT('rpt vw_valid_sales'[customer_key]),
        'rpt vw_valid_sales'[customer_key] <> -1
    )
)
```
Used in: CLV and AOV of customer segment (Wholesale vs Retail bar).
 
---
 
## 5. Churn Risk page
 
### Churn Rate %
Share of customers flagged as churned (`Churned = 1`, no purchase for 90+ days).
```DAX
Churn Rate % =
DIVIDE(
    CALCULATE(DISTINCTCOUNT('rpt customer_segments'[customer_id]), 'rpt customer_segments'[Churned] = 1),
    DISTINCTCOUNT('rpt customer_segments'[customer_id])
)
```
Used in: KPI card (50.7%).
 
### Revenue at Risk
Total `Monetary` value of churned customers. It is the customers' historical spend, not weighted by churn probability.
```DAX
Revenue at Risk =
CALCULATE(
    SUM('rpt customer_segments'[Monetary]),
    'rpt customer_segments'[Churned] = 1
)
```
Used in: KPI card (£3.30M).
 
The average churn probability by segment chart and the top 20 at-risk customers table use the `churn_probability` column directly (average aggregation and data bars), not a measure.
 
---
 
## 6. Calculated columns
 
All three are on `rpt vw_customer_summary`.
 
### Days to Second Order Bucket
Groups the days between a customer's first and second order.
```DAX
Days to Second Order Bucket =
SWITCH(
    TRUE(),
    ISBLANK('rpt vw_customer_summary'[days_to_second_order]), "No Second Order",
    'rpt vw_customer_summary'[days_to_second_order] <= 30, "0-30 days",
    'rpt vw_customer_summary'[days_to_second_order] <= 60, "31-60 days",
    'rpt vw_customer_summary'[days_to_second_order] <= 90, "61-90 days",
    "90+ days"
)
```
Used in: Customers' days to second order column chart. "No Second Order" is filtered out of that chart.
 
### Days to Second Order Bucket Sort
Numeric sort key so the buckets display in order (0-30, 31-60, 61-90, 90+) instead of alphabetically. Set as the **Sort by column** of `Days to Second Order Bucket`.
```DAX
Days to Second Order Bucket Sort =
SWITCH(
    TRUE(),
    ISBLANK('rpt vw_customer_summary'[days_to_second_order]), 5,
    'rpt vw_customer_summary'[days_to_second_order] <= 30, 1,
    'rpt vw_customer_summary'[days_to_second_order] <= 60, 2,
    'rpt vw_customer_summary'[days_to_second_order] <= 90, 3,
    4
)
```
 
### Customer Type
Labels each customer Repeat or One-Time.
```DAX
Customer Type =
IF('rpt vw_customer_summary'[is_repeat_customer] = 1, "Repeat", "One-Time")
```
Used in: axis of the Repeat vs One-Time chart, and the `ALL` reference in `% of Customers` and `% of Revenue`.
 
---
 
## 7. Notes and overlaps
 
- **Pareto:** `Cumulative Revenue` and `Product Revenue Rank` use `ALL`, while `Cumulative Revenue %` uses `ALLSELECTED`. `Cumulative Revenue %` computes its own running total and does not call `Cumulative Revenue`.
- **Duplicate formulas:** `Country Customer Count` matches `Total Customers`, and `AOV by Type` matches `AOV`. They are kept because the visuals already reference them.
- **Percent measures:** `% of Customers`, `% of Revenue`, `% of Customers by Segment` and `% of Revenue by Segment` are share-of-total measures. Use them with their category field on the axis or legend, or the `ALL` denominator makes the result 100%.
- **Guest checkouts:** excluded from all customer-level measures through `customer_key <> -1` or `customer_id <> -1`. Revenue measures on the fact table include guest revenue, so `Total Revenue` (£19.64M) is larger than the sum of customer revenue.
 
