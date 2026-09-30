# Business Questions
 
This project answers two sets of questions. The first set (Q1-Q9) is answered in SQL Server. The second set is answered in Python and Power BI. Every finding here matches the project brief and the dashboard.
 
**Currency:** the dataset is in GBP (£).
**Guest checkouts:** orders with no customer ID (13.1% of revenue, £2.58M) are excluded from customer-level metrics.
 
## Contents
 
1. [SQL questions (Q1-Q9)](#1-sql-questions-q1-q9)
2. [Questions answered in Python and Power BI](#2-questions-answered-in-python-and-power-bi)
3. [Where each question shows up on the dashboard](#3-where-each-question-shows-up-on-the-dashboard)
---
 
## 1. SQL questions (Q1-Q9)
 
All queries are in [`sql/05_business_questions.sql`](sql/05_business_questions.sql). They run against two reporting views built in the star schema step: `rpt.vw_valid_sales` (valid sales lines) and `rpt.vw_customer_summary` (one row per customer).
 
### Q1. What are the top 10 products by total revenue?
- **Method:** `TOP 10` with `SUM(sales_amount)` grouped by product description.
- **Finding:** the top 10 products make up 8.0% of revenue, so there is no single-product dependency. Regency Cakestand 3 Tier leads with £331K (1.7% of revenue).
- **Dashboard:** Products page, Total Revenue per Product.
### Q2. What are the top 10 products by total quantity?
- **Method:** `TOP 10` with `SUM(quantity)` grouped by product description.
- **Finding:** the quantity ranking differs from the revenue ranking. World War 2 Gliders leads by units sold, while Regency Cakestand 3 Tier leads by revenue.
- **Dashboard:** Products page, Total Quantity per Product.
### Q3. How many repeat customers are there per country?
- **Method:** join `vw_valid_sales` to `vw_customer_summary`, filter `is_repeat_customer = 1`, and count distinct customers per country.
- **Finding:** the UK holds 5,334 of the 5,852 identified customers, so it also holds most repeat customers by count. For a fair comparison across countries, the dashboard shows the repeat *rate* rather than the count.
- **Dashboard:** Repeat Customer Behavior page, Repeat Rate Percentage per Country (countries with 20+ customers).
### Q4. What is the average time between a repeat customer's first and second order?
- **Method:** `AVG(days_to_second_order)` for repeat customers.
- **Finding:** the dashboard reports the **median**, 57 days, instead of the average, because the median is less affected by customers who take a very long time to reorder.
- **Dashboard:** Repeat Customer Behavior page, Median Days to Second Order.
### Q5. How is the time to a second order distributed: fast, medium or slow?
- **Method:** `CASE` buckets on `days_to_second_order`: Fast (30 days or fewer), Medium (31-90), Slow (over 90).
- **Finding:** 31% of repeat customers return within 30 days, 32% take 31-90 days, and 37% take longer than 90 days. Cumulatively, 63% return within 90 days.
- **Dashboard:** Repeat Customer Behavior page, Customers' Days to Second Order. The dashboard uses four buckets (0-30, 31-60, 61-90, 90+) to show more detail.
### Q6. How much revenue comes from repeat vs one-time customers, and what share of the total does each represent?
- **Method:** group `vw_customer_summary` by repeat or one-time and use a window function (`SUM() OVER ()`) for the percentage of the grand total.
- **Finding:** 4,234 repeat customers (72.4%) generate £16.51M (96.7% of customer revenue). 1,618 one-time buyers (27.6%) generate £0.56M. A repeat customer is worth about £3,900 in lifetime revenue against £344 for a one-time buyer, roughly 11 times more.
- **Dashboard:** Repeat Customer Behavior page, Repeat Rate %, Repeat Revenue Share %, and the customers vs revenue bar.
### Q7. What are the AOV and CLV proxy for each customer segment?
- **Method:** AOV is total revenue divided by total orders. The CLV proxy is total revenue divided by the number of customers.
- **Finding:** value is concentrated in a small group of wholesale accounts. The 4 Wholesale/B2B accounts average about £420,765 each, and Wholesale CLV is several times higher than Retail.
- **Dashboard:** Customer Segmentation page, CLV and AOV of Customer Segment.
### Q8. What is gross Sale revenue, net valid revenue, and the value of the non-Sale transaction types?
- **Method:** three CTEs (gross `Sale` rows from `fact.sales`, net revenue from `vw_valid_sales`, and all non-`Sale` rows), combined with `CROSS JOIN` into one result row.
- **Purpose:** reconciles the raw sales table to the £19.64M net revenue reported on the dashboard, so the cleaning steps and the exclusion of non-sale rows (returns, adjustments and similar) can be audited.
- **Dashboard:** Overview page, Total Revenue.
### Q9. How does revenue develop for each acquisition cohort?
- **Method:** group customers by month of first order and use `DATEDIFF(month, ...)` for the months since that first purchase. Q9 returns revenue by cohort and month. Q9b pivots the same structure to count active customers, months 0-12.
- **Finding:** average retention across 25 monthly cohorts is 21.0% in month 1 and 21.9% in month 2, then falls to 17.9% by month 6 and about 15% in months 9-10. The month-12 rebound (18.3%) is seasonal: October and November returns average 24% and 28% of a cohort, against 13% in January and February.
- **Dashboard:** Cohort and Retention page, retention heatmap and line chart.
---
 
## 2. Questions answered in Python and Power BI
 
These questions need statistical or machine-learning methods, so they live in the notebooks and the dashboard rather than in SQL.
 
### Where does revenue depend on a single market or season?
- **Method:** revenue by country and by month in Power BI.
- **Finding:** the UK contributes £16.80M (85.5%) from 5,334 customers. The other 42 countries add £2.84M, and 38 of them are below 1% each. September to November delivers 29% of January to November revenue in both 2010 and 2011. Growth is flat at +3.0% (January to November 2011 vs 2010).
### How concentrated is revenue in the product catalog?
- **Method:** Pareto analysis (rank products by revenue and plot the cumulative share).
- **Finding:** 284 of 4,688 products (6%) generate 50% of revenue, and 1,028 (22%) generate 80%. The bottom 2,344 products generate 4.6% (£0.91M).
### Which customer groups matter most?
- **Method:** RFM scoring (recency, frequency, monetary) and K-Means clustering. Notebook: [`python/RFM_K_Means_Clustering_Analysis/rfmcustseg.ipynb`](python/RFM_K_Means_Clustering_Analysis/rfmcustseg.ipynb). The RFM table is built in [`sql/04_rfm_table.sql`](sql/04_rfm_table.sql).
- **Finding:** four segments emerge. 42 customers hold 27% of identified revenue (£4.61M): 38 Potential Champions (£2.92M) and 4 Wholesale/B2B accounts (£1.68M). Core/Average is 3,830 customers and 65% of revenue, and the top 10% of customers generate 63.9%. The Lost segment is 1,980 customers (34%) and 8.4% of revenue, averaging 461 days since their last order, and 368 of them spent over £1,000 each (£0.86M).
### How do customers retain over time?
- **Method:** cohort retention analysis. Notebook: [`python/Cohort_Retention_Analysis/coh_ret_analysis.ipynb`](python/Cohort_Retention_Analysis/coh_ret_analysis.ipynb). SQL equivalent: Q9 and Q9b above.
- **Finding:** see Q9. Retention peaks near 22% in month 2, then erodes steadily, which points to weak habit formation after the first repeat purchase.
### Which customers have churned or are likely to?
- **Method:** a customer is churned if they have not purchased for 90+ days. A logistic regression estimates each customer's churn probability. Notebook: [`python/Churn_Regression_Analysis/churn_regr.ipynb`](python/Churn_Regression_Analysis/churn_regr.ipynb).
- **Finding:** 2,967 customers (51%) are churned, holding £3.30M (17% of total revenue): Core/Average £1.76M (53%) and Lost £1.44M (43%). 589 customers who lapsed 91-180 days ago (£1.01M) are the most recoverable, and 1,304 still-active customers already score a 50%+ churn probability (£1.06M).
---
 
## 3. Where each question shows up on the dashboard
 
| Dashboard page | Questions answered |
|---|---|
| Business Overview | Revenue concentration by country and season |
| Products | Q1, Q2, long-tail Pareto |
| Repeat Customer Behavior | Q3, Q4, Q5, Q6 |
| Customer Segmentation | Q7, RFM segments |
| Cohort and Retention | Q9 |
| Churn Risk | Churn rate, revenue at risk, churn probability |
 
Q8 (revenue reconciliation) supports the Total Revenue figure on the Overview page and has no chart of its own.
 
