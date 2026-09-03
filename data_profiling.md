# Data Profiling

## Overview
- Dataset source: https://archive.ics.uci.edu/dataset/502/online+retail+ii
- Dataset size: 43.5 MB
- Tool: SQL Server (T-SQL)
- Purpose: Identify data quality issues before cleaning

## Schema Overview

| Column      | Data Type |
|---|---|
| Invoice     | nvarchar  |  
| StockCode   | nvarchar  |  
| Description | nvarchar  |  
| Quantity    | bigint    |  
| InvoiceDate | datetime2 |  
| Price       | float     |  
| Customer_ID | int       |  
| Country     | nvarchar  |  

## Column-by-Column Findings

### Invoice
- Total number of rows: 1044848
- Nulls: 0 
- Blank rows: 0
- Leading/trailing whitespaces: 0
- Duplicates: 40058 
- Cancellation prefix (The 'C' prefix): 19165
- Other prefixes (The 'A' prefix): 6
- Data length:

| invoice_data_length | number_of_rows |
|---|---|
| 6 | 1,025,677 |
| 7 | 19,171 |
#### FINAL NOTES
The main issues of this column lie in the duplicates, cancellation invoices, and invoices with the prefix 'A'.


### StockCode
- Total rows: 1044848
- Blank rows: 0
- Nulls: 0
- Duplicates: 4744 rows
- Leading/trailing whitespace: 1 row ('47503J')
- Casing inconsistency (non-uppercase): 0
- Unexpected special characters: 11 rows
- Internal whitespace: 0
- Non-product placeholder codes (not matching 4-5 digit pattern): 61 rows
- Distinct StockCode count: 5131
- Value length distribution: 

| stockcode_length | num_of_rows |
|---|---|
| 1 | 1,684 |
| 2 | 278 |
| 3 | 1,425 |
| 4 | 2,122 |
| 5 | 912,611 |
| 6 | 124,966 |
| 7 | 1,369 |
| 8 | 126 |
| 9 | 67 |
| 12 | 200 |

#### FINAL NOTES
The main issues in this column are structural rather than formatting-related: 61 non-product 
placeholder codes (e.g. postage, fees, adjustments) and 11 rows with unexpected special 
characters need to be identified and flagged before building the fact table. Casing and 
whitespace are clean, and duplicates (4,744 rows) are expected given StockCode repeats across 
multiple invoices.








### Description
- Nulls: count, %
- Blanks: 
- Rows with leading/trailing whitespace: count
- Very short descriptions (≤3 chars): distinct values found
- Duplicates: count, total number of duplicate rows
- Casing breakdown: ALL UPPERCASE / ALL LOWERCASE / MIXED CASE — count each
- StockCode → multiple Descriptions: count of StockCodes affected
- Description → multiple StockCodes: count (lowercase-variant descriptions), count (uppercase-variant descriptions)
- Placeholder/junk values found (damage, missing, test, sample, ?, amazon, ebay, etc.): list/count





### Price
- Nulls: count
- Negative/zero values: count, %
- Min / Max: 
- Avg: 
- Median / P95 / P99: 
- Price consistency per StockCode: number of StockCodes with more than one distinct price, stdev range observed

### InvoiceDate
- Nulls: 
- Date range (min/max): 
- Future dates: count
- Time component anomalies (e.g. rows clustering at 00:00:00): 
- Invoices with more than one distinct date: count
- Duplicate InvoiceDate values: notable frequency, if any

### Quantity
- Nulls: 
- Zero values: count
- Negative values: count, %
- Min / Max / Avg: 
- Median / P95 / P99: 
- Duplicate Quantity values: notable frequency, if any
- Cancellation vs negative Quantity alignment: % match
- Extreme outliers (beyond P99): count, examples
- Quantity ≤ 0 vs Price sign breakdown: counts per bucket (negative/zero/positive price)

### Customer_ID
- Nulls: count, %
- Null clustering by Country / cancellation status: summary of pattern (or "no clear clustering")
- Null Customer_ID on non-cancellation invoices: count
- Null Customer_ID on cancelled invoices: count
- Invoices mapping to more than one Customer_ID: count
- Min / Max Customer_ID: 
- Multi-country customers: count
- Null Customer_ID vs Price sign: counts per bucket (zero/negative/positive)

### Country
- Nulls: 
- Blanks: 
- Distinct values: count
- Naming inconsistencies: 
- Leading/trailing whitespace: 
- Casing inconsistency: 
- Placeholder values ("Unspecified", "European Community"): count each

## Cross-Column Findings
- Cancellation invoices vs negative Quantity correlation: % alignment
- Null Customer_ID vs Price sign distribution
- Quantity ≤ 0 vs Price sign distribution (returns integrity check)
- StockCode ↔ Description mismatches (both directions)
- Multi-country Customer_IDs
- Full-row duplicates: count

## Key Takeaways
- Bullet list of the 4-6 decisions this profiling drives (feeds directly into cleaning plan)
