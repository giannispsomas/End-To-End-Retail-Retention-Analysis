# Dashboard Guide
 
The Power BI report has six pages. Each page answers one business question and opens with a one-line takeaway. The file is [`powerbi/`](powerbi/) in this repo. Measure formulas are in [`dax_measures.md`](dax_measures.md).
 
## Contents
 
1. [Data model](#data-model)
2. [Page 1: Business Overview](#page-1-business-overview)
3. [Page 2: Products](#page-2-products)
4. [Page 3: Repeat Customer Behavior](#page-3-repeat-customer-behavior)
5. [Page 4: Customer Segmentation](#page-4-customer-segmentation)
6. [Page 5: Cohort and Retention](#page-5-cohort-and-retention)
7. [Page 6: Churn Risk](#page-6-churn-risk)
8. [How to use the report](#how-to-use-the-report)
---
 
## Data model
 
The report connects to the `OnlineRetailII` database on SQL Server Express in **Import** mode, using Windows authentication.
 
| Table | Role |
|---|---|
| `rpt.vw_valid_sales` | Fact table: valid sales lines with all dimension keys |
| `rpt.vw_customer_summary` | One row per customer: order count, revenue, days to second order, repeat flag |
| `rpt.customer_segments` | RFM segment, churn flag and churn probability per customer (5,852 rows, produced in Python) |
| `rpt.cohort_retention` | Retention percentage by cohort month and month number (325 rows, 25 cohorts) |
| `dim customer`, `dim product`, `dim date` | Star schema dimensions |
| `_Measures` | Empty table that holds all DAX measures |
 
**Relationships**
 
| From | To | Type |
|---|---|---|
| `vw_valid_sales[customer_key]` | `dim customer[customer_surrogate_key]` | Many-to-one, single |
| `vw_valid_sales[product_key]` | `dim product[product_key]` | Many-to-one, single |
| `vw_valid_sales[full_date]` | `dim date[full_date]` | Many-to-one, single |
| `vw_customer_summary[customer_key]` | `dim customer[customer_surrogate_key]` | Many-to-one, single |
| `customer_segments[customer_id]` | `dim customer[customer_id]` | One-to-one, both |
 
The guest customer (`customer_key = -1`) has its `customer_id` set to -1 in Power Query so the one-to-one relationship with `customer_segments` resolves.
 
---
 
## Page 1: Business Overview
 
![Business Overview](images/page1_business_overview.png)
 
**Takeaway:** revenue is heavily UK-concentrated (85.5%) with a recurring Q4 seasonal spike. December 2011 is an incomplete month.
 
| Visual | What it shows | Measure |
|---|---|---|
| KPI cards (4) | £19.64M revenue, 5,852 customers, 39,516 orders, £497.09 average order value | `Total Revenue`, `Total Customers`, `Total Orders`, `AOV` |
| Line chart | Monthly revenue with a dashed average line (£785,728) | `Total Revenue` |
| Bar chart | Top 10 countries by revenue | `Total Revenue` |
| Year slicer | Filters the page to 2009, 2010 or 2011 | n/a |
 
**How to read it:** the two peaks on the line are the September to November seasons. The drop at the far right is the partial month, not a real decline.
 
---
 
## Page 2: Products
 
![Products](images/page2_products.png)
 
**Takeaway:** revenue is spread across a long tail of products. About 22% of products generate 80% of revenue.
 
| Visual | What it shows | Measure |
|---|---|---|
| Pareto chart | Columns show each product's revenue, sorted high to low. The line shows the cumulative share of total revenue (right axis) | `Total Revenue`, `Cumulative Revenue %` |
| Bar chart | Top 10 products by revenue | `Total Revenue` |
| Bar chart | Top 10 products by units sold | `Total Quantity` |
 
**How to read it:** the Pareto chart lists every product, so scroll the chart to move along the tail. Individual bars are not meant to be read. Look at how quickly the line climbs. The line reaches 100% at the last product.
 
---
 
## Page 3: Repeat Customer Behavior
 
![Repeat Customer Behavior](images/page3_repeat_customer_behavior.png)
 
**Takeaway:** repeat customers are 72% of the base but generate 97% of revenue, while one-time buyers (28% of customers) contribute just 3%.
 
| Visual | What it shows | Measure |
|---|---|---|
| KPI cards (3) | 72% repeat rate, 57-day median to second order, 97% repeat revenue share | `Repeat Rate %`, `Median Days to Second Order`, `Repeat Revenue Share %` |
| Column chart | Customers by days to their second order (0-30, 31-60, 61-90, 90+) | Distinct count of `customer_id` by `Days to Second Order Bucket` |
| Bar chart | Repeat rate by country, for countries with 20 or more customers | `Repeat Rate % by Country` |
| Clustered bar | Share of customers vs share of revenue for repeat and one-time buyers | `% of Customers`, `% of Revenue` |
 
**How to read it:** the last chart shows the gap between the two bars. Repeat customers have a small lead in customer share but a large lead in revenue share.
 
---
 
## Page 4: Customer Segmentation
 
![Customer Segmentation](images/page4_customer_segmentation.png)
 
**Takeaway:** Wholesale/B2B outliers and Potential Champions are small in number but drive disproportionate revenue, while Churned/Lost customers make up a large share of the base.
 
| Visual | What it shows | Measure |
|---|---|---|
| Table | Average recency, frequency and monetary value per segment, with data bars | Averages of `Recency`, `Frequency`, `Monetary` |
| Clustered bar | Share of revenue vs share of customers by segment | `% of Revenue by Segment`, `% of Customers by Segment` |
| Clustered bar | Customer lifetime value and average order value for Wholesale vs Retail | `CLV by Type`, `AOV by Type` |
| Year slicer | Filters the year | n/a |
 
**Segments** (from K-Means clustering on RFM values): Churned / Lost Customers, Core / Average Customers, Potential Champions, Wholesale / B2B Outliers. See [`business_questions.md`](business_questions.md) for the sizes.
 
---
 
## Page 5: Cohort and Retention
 
![Cohort and Retention](images/page5_cohort_and_retention.png)
 
**Takeaway:** retention peaks around month 2 (about 22%), then declines steadily, dropping to roughly 18% by month 6.
 
| Visual | What it shows | Source |
|---|---|---|
| Line chart | Average retention percentage for months 1 to 6 | `rpt.cohort_retention[retention_pct]` |
| Matrix heatmap | Retention percentage by cohort month (rows) and months since first purchase (columns), with a color scale | `rpt.cohort_retention` |
 
**How to read it:** each row is the customers acquired in one month. Darker cells mean higher retention. The empty pink triangle at the bottom right is where a cohort has not existed long enough to measure. The line chart stops at month 6 so the incomplete recent cohorts do not distort the average. Month 0 is left out because it is always 100%.
 
---
 
## Page 6: Churn Risk
 
![Churn Risk](images/page6_churn_risk.png)
 
**Takeaway:** 51% of customers are churned, which represents £3.30M in revenue at risk, concentrated in the Churned/Lost and Core/Average segments.
 
| Visual | What it shows | Measure |
|---|---|---|
| KPI cards (2) | £3.30M revenue at risk and a 50.7% churn rate | `Revenue at Risk`, `Churn Rate %` |
| Column chart | Average churn probability for each segment | Average of `churn_probability` |
| Table | The 20 highest-spending churned customers with their churn probability | `customer_id`, `Segment`, `Monetary`, `churn_probability` |
 
**How to read it:** the table is filtered to churned customers (`Churned = 1`) and sorted by monetary value. It is a ready-made outreach list, with the largest accounts first.
 
---
 
## How to use the report
 
1. Open the `.pbix` file in Power BI Desktop. Import mode holds a copy of the data, so the report opens without a database connection.
2. To refresh from SQL Server, restore the database using the scripts in [`sql/`](sql/), then point the data source at your own server (Home → Transform data → Data source settings).
3. The Year slicers filter the pages that have one. Pages without a slicer show the full period.
 
