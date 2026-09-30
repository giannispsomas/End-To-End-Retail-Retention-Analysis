# Assumptions and Limitations
 
This document lists the definitions the analysis relies on and what it cannot conclude. Read it alongside the findings in [`business_questions.md`](business_questions.md) and the dashboard in [`dashboard_guide.md`](dashboard_guide.md).
 
## Contents
 
1. [Data and scope](#1-data-and-scope)
2. [Definitions used](#2-definitions-used)
3. [Modeling assumptions](#3-modeling-assumptions)
4. [Limitations](#4-limitations)
5. [What the analysis does not claim](#5-what-the-analysis-does-not-claim)
---
 
## 1. Data and scope
 
- **Source:** the Online Retail II dataset from the UCI Machine Learning Repository, licensed CC BY 4.0. It contains transactions from a UK-based online retailer between December 2009 and December 2011.
- **Currency:** all values are in GBP (£).
- **Period:** two years of data. **December 2011 is a partial month** and is flagged in the data (`is_partial_month`) and on the dashboard.
- **Revenue basis:** revenue means valid sales from `rpt.vw_valid_sales`. Other transaction types, such as returns and adjustments, are excluded. Query Q8 reconciles gross sales, net revenue and non-sale transactions.
- **Cleaning:** the steps and row counts are in [`data_cleaning.md`](data_cleaning.md) and [`data_profiling.md`](data_profiling.md).
## 2. Definitions used
 
| Term | Definition |
|---|---|
| Identified customer | An order with a customer ID. 5,852 customers in total. |
| Guest checkout | An order with no customer ID (`customer_key = -1`). 13.1% of revenue (£2.58M). Excluded from every customer-level metric. |
| Repeat customer | A customer with two or more orders. |
| One-time customer | A customer with one order. |
| Days to second order | Days between a customer's first and second order. Blank for one-time customers. |
| Censored customer | A customer whose first order is too recent to have had a second order within the data (`is_censored`). 367 first orders fall into this group. |
| AOV | Average order value: total revenue divided by total orders. |
| CLV proxy | Total revenue divided by number of customers. It describes past spend, not predicted future value. |
| Churned | A customer with no purchase for 90 or more days. The reference date is set in the RFM script (`sql/04_rfm_table.sql`). |
| Revenue at Risk | The total historical spend (`Monetary`) of churned customers. It is not weighted by churn probability and it is not a revenue forecast. |
| Cohort | All customers whose first order falls in the same month. |
| Retention (cohort) | The share of a cohort that places an order in a given month after its first purchase. |
| RFM | Recency, Frequency and Monetary value of each customer. |
 
## 3. Modeling assumptions
 
1. **Segments come from clustering.** K-Means groups customers by RFM values, and the four segment names (Churned / Lost, Core / Average, Potential Champions, Wholesale / B2B Outliers) were assigned by interpreting each cluster's profile. The number of clusters was chosen with the elbow method and silhouette score (charts in the notebook folder).
2. **Churn is a fixed threshold.** 90 days without a purchase counts as churned, regardless of a customer's normal buying rhythm.
3. **Churn probability is a model output.** It comes from the churn notebook and describes the chance a customer has stopped buying, given their behavior. The confusion matrix and ROC curve are in `python/Churn_Regression_Analysis/`.
4. **Products are identified by description** in the Pareto analysis and product rankings, not by stock code.
5. **Median instead of average for time to second order.** The dashboard reports the median because a few very long gaps would inflate the average.
6. **Country repeat rates** are shown only for countries with 20 or more customers.
## 4. Limitations
 
**Time span**
- Two years give only two full seasonal cycles. The Q4 spike appears in both, but two data points cannot show a stable pattern.
- The +3.0% growth compares January to November of 2011 with 2010, because December 2011 is incomplete. It is a short comparison, not a trend.
**Customer coverage**
- Guest checkouts (13.1% of revenue) cannot be tied to a customer, so repeat behavior, segments and churn describe only 86.9% of revenue.
- The Wholesale/B2B segment has 4 accounts. Its averages, including the £420,765 per account, move a lot if a single account is added or removed.
**Retention**
- Recent cohorts have fewer months of history, so the bottom right of the heatmap is empty. The average retention line stops at month 6 for that reason, and averages at higher months use fewer cohorts.
- The rise at month 12 (18.3%) is seasonal: October and November returns are far higher than January and February returns. It is not a sign that customers come back after a year.
**Churn**
- A 90-day threshold can label seasonal buyers as churned during the off-season. The cohort data shows strong Q4 returns, so some churned customers may return in autumn.
- Revenue at Risk shows what churned customers spent in the past. It does not predict what they would spend if won back.
- The most recoverable groups in the brief (589 customers lapsed 91 to 180 days ago, and 1,304 active customers with a 50%+ churn probability) are ranked by recency and model score. The analysis does not test which outreach would work.
**Products**
- Ranking by description can merge or split products if one description covers several stock codes, or one stock code has several descriptions.
- The Pareto chart plots every product, so the individual bars are not readable. The message sits in the shape of the cumulative line.
**Data refresh**
- The data is a historical snapshot in Import mode. The report does not update itself.
## 5. What the analysis does not claim
 
- **The proposed fixes are hypotheses.** Campaigns, account management and product audits in the brief follow from the findings but were not tested.
- **The findings are descriptive.** They show what happened in this retailer's data over two years. They do not show why customers behave this way.
- **The results may not transfer.** They describe one UK online gift retailer and its mostly UK customer base, and other businesses could show different patterns.
 
