# Data Profiling

## Overview
- Dataset source: https://archive.ics.uci.edu/dataset/502/online+retail+ii
- Dataset size: 43.5 MB
- Tool: SQL Server (T-SQL)
- Purpose: Identify data quality issues before cleaning
- Total raw row count: 1,044,848

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
- Nulls: 0
- Blank rows: 0
- Leading/trailing whitespace: 0
- Duplicates: 40,058
- Cancellation prefix (the 'C' prefix): 19,165
- Other prefixes (the 'A' prefix): 6
- Data length:

| invoice_data_length | number_of_rows |
|---|---|
| 6 | 1,025,677 |
| 7 | 19,171 |

**FINAL NOTES**

Issues: 40,058 duplicates, 19,165 cancellations (needs TransactionType flag), 6 rows with unexplained 'A' prefix (inspect individually).

### StockCode
- Blank rows: 0
- Nulls: 0
- Duplicates: 4,744 rows
- Leading/trailing whitespace: 1 row ('47503J')
- Casing inconsistency (non-uppercase): 0
- Unexpected special characters: 11 distinct StockCodes
- Internal whitespace: 0
- Non-product placeholder codes (not matching 4-5 digit pattern): 61 distinct StockCodes
- Distinct StockCode count: 5,131
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

**FINAL NOTES**

Issues: 61 non-product placeholder codes, 11 codes with special characters, 1 row with whitespace. Manual review confirmed a mix of genuine non-product codes (POST, DOT, M, C2, C3, D, B, S, CRUK, BANK CHARGES, AMAZONFEE, ADJUST, ADJUST2, TEST001, TEST002, gift_0001_XX series) and legitimate products using a different code format (DCGS%, SP1002) that don't match the standard digit-pattern rule. Everything else clean.

### Description
- Nulls: 4,275
- Blanks: 0
- Rows with leading/trailing whitespace: 206,844
- Distinct values with leading/trailing whitespace: 953
- Very short descriptions (≤3 chars):

| Description | descr_length |
|---|---|
| wet | 3 |
| ?? | 2 |
| ? | 1 |
| FBA | 3 |
| MIA | 3 |
| ??? | 3 |

- Duplicates: 5,259
- Casing breakdown:

| casing_type | num_rows |
|---|---|
| ALL UPPERCASE | 1,034,707 |
| ALL LOWERCASE | 725 |
| MIXED CASE | 9,416 |

- StockCode -> multiple Descriptions: 1,190 StockCodes
- Description -> multiple StockCodes: roughly 54 to 57 distinct descriptions affected (split between lowercase- and uppercase-variant descriptions; exact split unconfirmed, minor and superseded by the cleaning fix)
- Placeholder/junk values found (damage, missing, test, sample, ?, amazon, ebay, etc.): 174

**FINAL NOTES**

Issues: 4,275 nulls, 5,259 duplicates, 174 placeholder values, 206,844 rows with whitespace. Not a reliable grouping key — 1,190 StockCodes map to multiple Descriptions. Build a canonical Description-per-StockCode lookup instead.

### Price
- Nulls: 5
- Zero/negative values: 6,024 (confirmed entirely zero-price; no true negative prices exist — Min = 0)
- Min: 0
- Max: 38,970
- Avg: 4.74
- Median: 2.099
- P95: 9.94
- P99: 18
- Price consistency per StockCode: 4,276 StockCodes have more than one distinct price recorded (expected — normal price variation over time, not a data quality issue on its own)

**FINAL NOTES**

Issues: 5 nulls, 6,024 zero-price rows. Likely correlates with cancellations or non-sale transactions (samples, write-offs).

### InvoiceDate
- Nulls: 0
- Date range (min/max): 2009-12-01 07:45:00 to 2011-12-09 12:50:00
- Future dates: 0
- Time component anomalies (e.g. rows clustering at 00:00:00): No major anomalies found. A steadily descending number of rows cluster normally at random time intervals.
- Invoices with more than one distinct date: 83 invoices with exactly 2 dates
- Duplicate InvoiceDate values: No major anomalies found here either. One invoice which is the exception, Invoice no. 573585, with 1,114 line items all sharing the same timestamp — confirmed as one large multi-line invoice, not a data error.

**FINAL NOTES**

Issues: 83 invoices with more than one distinct date, breaking the one-invoice-one-timestamp assumption. Needs a resolution rule (earliest date chosen) before using as a join key or in date-based aggregation. Note: resolving this during cleaning surfaced 4 additional full-row duplicates that hadn't been detectable at profiling time — see Data Cleaning doc.

### Quantity
- Nulls: 0
- Zero values: 0
- Negative values: 22,557
- Min: -80,995
- Max: 80,995
- Avg: 9
- Median: 3
- P95: 30
- P99: 100
- Duplicate Quantity values: Frequency is normal, no major outliers were found
- Cancellation vs negative Quantity alignment: strong overall correlation, but not perfect.
- Cancelled invoices with negative/zero quantity (expected): 19,164
- Normal invoices with positive quantity (expected): 1,022,290
- Normal invoices with negative/zero quantity (inconsistent): 3,393 — needs investigation, these may be returns not labeled with the 'C' prefix
- Cancelled invoices with positive quantity (inconsistent): 1 row — isolated case, worth inspecting individually
- Extreme outliers (beyond P99): Overall normal frequency and distribution — large values turn out to be legitimate matched sale/cancellation pairs (e.g. Invoice 581483: +80995 / Invoice C581484: -80995 on the same StockCode), repeated consistently across many invoice pairs, indicating genuine bulk wholesale orders rather than data entry errors.
- Quantity ≤ 0 vs Price sign breakdown:
- Positive price: 19,164 rows — expected pattern (normal returns/cancellations)
- Zero price: 3,393 rows — matches the earlier "Normal invoice + negative quantity" finding; likely stock adjustments/write-offs, not customer returns
- Negative price: 0 rows — no double-counted adjustments found, convention holds cleanly

**FINAL NOTES**

Issues: 3,394 rows break the 'C'-prefix-only cancellation assumption (3,393 normal-invoice negative quantity + 1 cancelled-invoice positive quantity). The 3,393 pair with zero price — likely stock adjustments, not returns. Supports a dedicated TransactionType classification.

### Customer_ID
- Nulls: 235,287
- Percentage of nulls: 22.51%
- Null Customer_ID clustering by Country/cancellation status: heavily concentrated in the UK — 231,706 "Normal" + 614 "Cancelled" null-Customer_ID rows are UK, dwarfing every other country (next highest: EIRE at 1,598). This points to a systematic cause specific to the UK market (e.g. guest checkout not requiring an account) rather than random missingness, and supports flagging nulls as "Guest/Unregistered" rather than treating them as broken data.
- Null Customer_ID breakdown by transaction type:
- Unknown (non-cancelled) transactions: 234,568
- Cancelled transactions: 719
- Total matches the overall null count above
- Invoices mapping to more than one Customer_ID: 0
- Min Customer_ID: 12346
- Max Customer_ID: 18287
- Multi-country customers: 12 Customer_IDs map to 2 distinct countries
- Null Customer_ID vs Price sign: 5,954 rows with zero price, 229,333 rows with positive price

**FINAL NOTES**

Issues: 22.51% nulls, concentrated in guest checkout — flag as Guest/Unregistered, don't drop. 719 null rows tied to cancellations and the zero/positive price split both feed into TransactionType. ID range is a plausible real range; 12 multi-country customers resolved via most-frequent-Country lookup.

### Country
- Nulls: 0
- Blanks: 0
- Distinct values: 43, including 'Unspecified', 'EIRE', 'European Community'
- Naming inconsistencies: 0
- Leading/trailing whitespace: 0
- Casing inconsistency: 0
- Placeholder values: 756 rows "Unspecified", 61 rows "European Community"

**FINAL NOTES**

Issues: bucket 756 "Unspecified" and 61 "European Community" rows as Other/Unknown rather than exclude — they're still real transactions.

## Cross-Column Findings

**Cancellation invoices vs negative Quantity**: strong but imperfect correlation.
- Cancelled + negative/zero quantity (expected): 19,164
- Normal invoice + positive quantity (expected): 1,022,290
- Normal invoice + negative/zero quantity (inconsistent): 3,393 — likely stock adjustments, not cancellations
- Cancelled + positive quantity (inconsistent): 1 row — isolated case

**Quantity ≤ 0 vs Price sign** (returns integrity check):
- Positive price: 19,164 rows — expected (normal returns)
- Zero price: 3,393 rows — same set as the inconsistent rows above, points to write-offs/adjustments
- Negative price: 0 rows — no double-counted adjustments found

**Null Customer_ID vs Price sign**: 
- 5,954 rows with zero price, 229,333 rows with positive price

**Null Customer_ID clustering by Country/cancellation status**: 
- heavily concentrated in the UK — 231,706 "Normal" + 614 "Cancelled" null-Customer_ID rows are UK, dwarfing every other country (next highest: EIRE at 1,598). Points to a systematic UK-market cause (e.g. guest checkout) rather than random missingness.

**StockCode / Description mismatches**:
- StockCodes mapping to multiple Descriptions: 1,190
- Descriptions mapping to multiple StockCodes: roughly 54 to 57 distinct descriptions affected (exact split unconfirmed; resolved entirely by the canonical lookup during cleaning)

**Multi-country Customer_IDs**: 
- 12 customers linked to more than one Country — resolved via most-frequent-Country lookup before building Dim_Customer.

**Full-row duplicates**: 
- 11,001 distinct duplicate groups (22,813 total rows involved), 11,812 excess rows removed to leave one row per group. 
Note: an additional 4 duplicate rows surfaced later during cleaning, after the InvoiceDate resolution step collapsed two previously-distinct timestamps into one — see Data Cleaning doc.

## Key Takeaways

- Build a TransactionType column (Sale / Cancellation / Stock Adjustment) — the 'C' prefix alone misses 3,394 inconsistent rows.
- Flag null Customer_IDs (22.5%) as Guest/Unregistered — don't drop, revenue is real.
- Filter non-product StockCodes and junk Descriptions explicitly by name, not just pattern rules.
- Use StockCode as the canonical product key — Description isn't reliable (1,190 mismatches).
- Exclude zero-price rows from revenue KPIs.
- Remove full-row duplicates before anything else — and re-check for duplicates after any step that overwrites a differentiating column (e.g. InvoiceDate resolution).
- Resolve multi-country customers and multi-date invoices via most-frequent/earliest-value lookups before building dimension tables.
