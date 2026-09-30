# Data Profiling

## Overview

- **Dataset source:** https://archive.ics.uci.edu/dataset/502/online+retail+ii
- **Dataset size:** 43.5 MB
- **Tool:** SQL Server (T-SQL)
- **Purpose:** identify data quality issues before cleaning
- **Raw row count:** 1,044,848

## Schema

| Column | Data type |
|---|---|
| Invoice | nvarchar |
| StockCode | nvarchar |
| Description | nvarchar |
| Quantity | bigint |
| InvoiceDate | datetime2 |
| Price | float |
| Customer_ID | int |
| Country | nvarchar |

## Summary of Issues

| Column | Main issues found | How cleaning handled it (see [data_cleaning.md](data_cleaning.md)) |
|---|---|---|
| Invoice | Full-row duplicates, 19,165 cancellation invoices, 6 rows with an 'A' prefix | Duplicates removed. Cancellations classified through `TransactionType`, not deleted. 'A' rows kept as Sales. |
| StockCode | 61 non-product codes, 11 codes with special characters, 1 row with whitespace | Whitespace trimmed. Non-product codes flagged with `IsNonProductCode`. |
| Description | 4,275 nulls, 206,844 rows with whitespace, junk and very short values, 1,190 StockCodes with several Descriptions | Nulls, short and junk values removed. Whitespace trimmed, text uppercased, one canonical Description per StockCode. |
| Price | 5 nulls, 6,024 zero-price rows | Rounded to 3 decimals. Zero-price rows flagged with `PriceFlag`. |
| InvoiceDate | 83 invoices with two distinct dates | Earliest date kept for each invoice. |
| Quantity | 22,557 negative values, 3,394 rows that break the 'C'-prefix rule | `TransactionType` classification. Outliers flagged with `OutliersInQnt`. |
| Customer_ID | 235,287 nulls (22.52%), 12 customers in two countries | Nulls flagged as Guest, not dropped. Most frequent country kept for each customer. |
| Country | 756 'Unspecified' rows, 61 'European Community' rows | Not changed. The 43 countries are kept as they are. |

---

## Column-by-Column Findings

### Invoice

- Nulls: 0
- Blank rows: 0
- Leading or trailing whitespace: 0
- Duplicates: 40,058. An invoice has one row per line item, so repeated invoice numbers are expected. Full-row duplicates are covered under [Cross-Column Findings](#cross-column-findings).
- Cancellation prefix ('C'): 19,165
- Other prefix ('A'): 6
- Value length:

| invoice_data_length | number_of_rows |
|---|---|
| 6 | 1,025,677 |
| 7 | 19,171 |

**Issues:** 19,165 cancellations need a `TransactionType` flag, and 6 rows with an unexplained 'A' prefix need individual inspection.

### StockCode

- Blank rows: 0
- Nulls: 0
- Duplicates: 4,744 rows
- Leading or trailing whitespace: 1 row ('47503J')
- Casing inconsistency (non-uppercase): 0
- Unexpected special characters: 11 distinct StockCodes
- Internal whitespace: 0
- Non-product placeholder codes (not matching the 4 to 5 digit pattern): 61 distinct StockCodes
- Distinct StockCode count: 5,131
- Value length:

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

**Issues:** 61 non-product placeholder codes, 11 codes with special characters, and 1 row with whitespace. Manual review found two groups:
- Genuine non-product codes: POST, DOT, M, C2, C3, D, B, S, CRUK, BANK CHARGES, AMAZONFEE, ADJUST, ADJUST2, TEST001, TEST002, and the gift_0001_XX series.
- Legitimate products in a different code format: DCGS% and SP1002.

Everything else is clean.

### Description

- Nulls: 4,275
- Blanks: 0
- Rows with leading or trailing whitespace: 206,844 (953 distinct values)
- Duplicates: 5,259
- Very short descriptions (3 characters or fewer):

| Description | descr_length |
|---|---|
| wet | 3 |
| ?? | 2 |
| ? | 1 |
| FBA | 3 |
| MIA | 3 |
| ??? | 3 |

- Casing breakdown:

| casing_type | num_rows |
|---|---|
| ALL UPPERCASE | 1,034,707 |
| ALL LOWERCASE | 725 |
| MIXED CASE | 9,416 |

- StockCodes with more than one Description: 1,190. Cleaning removed the null, short and junk rows and normalized whitespace and case before the canonical lookup was built, and 715 StockCodes were still affected at that point.
- Descriptions linked to more than one StockCode: about 54 to 57 distinct descriptions. The lookup fixed this entirely.
- Placeholder or junk values (damage, missing, test, sample, ?, amazon, ebay and similar): 174

**Issues:** 4,275 nulls, 5,259 duplicates, 174 placeholder values, and 206,844 rows with whitespace. Description is not a reliable grouping key, so a canonical Description per StockCode is built during cleaning.

### Price

- Nulls: 5
- Zero or negative values: 6,024 (all zero; no negative prices exist, and the minimum is 0)
- Min: 0
- Max: 38,970
- Average: 4.74
- Median: 2.099
- P95: 9.94
- P99: 18
- StockCodes with more than one distinct price: 4,276. This is expected (normal price variation over time) and is not a quality issue on its own.

**Issues:** 5 nulls and 6,024 zero-price rows. The zero prices likely relate to cancellations or non-sale transactions such as samples and write-offs.

### InvoiceDate

- Nulls: 0
- Date range: 2009-12-01 07:45:00 to 2011-12-09 12:50:00
- Future dates: 0
- Time anomalies (for example rows clustering at 00:00:00): none. Rows spread normally across time intervals.
- Invoices with more than one distinct date: 83, each with exactly 2 dates
- Duplicate InvoiceDate values: no anomalies apart from Invoice 573585, which has 1,114 line items sharing one timestamp. This is a single large multi-line invoice, not a data error.

**Issues:** 83 invoices have more than one date, which breaks the one-invoice-one-timestamp assumption. The earliest date is chosen before the column is used as a join key or in date aggregation. Resolving this during cleaning surfaced 4 more full-row duplicates that profiling could not detect (see [data_cleaning.md](data_cleaning.md)).

### Quantity

- Nulls: 0
- Zero values: 0
- Negative values: 22,557
- Min: -80,995
- Max: 80,995
- Average: 9
- Median: 3
- P95: 30
- P99: 100
- Duplicate Quantity values: normal frequency, no outliers
- Extreme outliers (beyond P99): the large values are legitimate matched sale and cancellation pairs (for example Invoice 581483 at +80,995 and Invoice C581484 at -80,995 on the same StockCode), repeated across many invoice pairs. They indicate genuine bulk wholesale orders, not data entry errors.

**Cancellation prefix vs quantity sign.** The two agree strongly but not perfectly.

| Group | Rows | Verdict |
|---|---|---|
| Cancelled invoice, negative or zero quantity | 19,164 | Expected |
| Normal invoice, positive quantity | 1,022,290 | Expected |
| Normal invoice, negative or zero quantity | 3,393 | Inconsistent |
| Cancelled invoice, positive quantity | 1 | Inconsistent (isolated case) |

**Quantity of zero or below vs price sign**

| Price | Rows | Meaning |
|---|---|---|
| Positive | 19,164 | Expected pattern (normal returns and cancellations) |
| Zero | 3,393 | Same set as the inconsistent normal invoices. Likely stock adjustments or write-offs, not customer returns. |
| Negative | 0 | No double-counted adjustments |

**Issues:** 3,394 rows break the 'C'-prefix-only cancellation assumption (3,393 normal invoices with negative quantity, plus 1 cancelled invoice with positive quantity). The 3,393 have zero price and are likely stock adjustments. This supports a dedicated `TransactionType` classification.

### Customer_ID

- Nulls: 235,287 (22.52%)
- Invoices mapping to more than one Customer_ID: 0
- Min: 12346
- Max: 18287
- Customers linked to two countries: 12
- Null Customer_ID by transaction type:

| Transaction type | Rows |
|---|---|
| Unknown (non-cancelled) | 234,568 |
| Cancelled | 719 |
| **Total** | **235,287** |

- Null Customer_ID by price sign: 5,954 rows with zero price and 229,333 rows with positive price.
- Clustering by country: the nulls are heavily concentrated in the UK, with 231,706 normal and 614 cancelled null rows. The next highest country is EIRE with 1,598. This points to a systematic UK cause, such as guest checkout not requiring an account, rather than random missingness.

**Issues:** 22.52% nulls concentrated in guest checkout, so they are flagged as Guest/Unregistered and not dropped. The ID range is plausible. The 12 multi-country customers are resolved with a most-frequent-country lookup.

### Country

- Nulls: 0
- Blanks: 0
- Distinct values: 43, including 'Unspecified', 'EIRE' and 'European Community'
- Naming inconsistencies: 0
- Leading or trailing whitespace: 0
- Casing inconsistency: 0
- Placeholder values: 756 rows 'Unspecified' and 61 rows 'European Community'

**Issues:** the 756 'Unspecified' and 61 'European Community' rows are real transactions, so they are not excluded.

---

## Cross-Column Findings

**Cancellation invoices vs quantity.** See the table in the Quantity section above. The two agree strongly, with 3,394 exceptions.

**Zero price vs quantity of zero or below.** All 3,393 non-cancelled rows with negative quantity have zero price, which points to write-offs or adjustments, not returns. No negative prices exist.

**Null Customer_ID vs price sign.** 5,954 zero-price rows and 229,333 positive-price rows. See the Customer_ID section.

**StockCode and Description mismatches**
- StockCodes with more than one Description: 1,190
- Descriptions with more than one StockCode: about 54 to 57, resolved entirely by the canonical lookup during cleaning

**Multi-country customers.** 12 customers are linked to two countries. They are resolved with a most-frequent-country lookup before `dim.customer` is built.

**Full-row duplicates**
- 11,001 distinct duplicate groups (22,813 rows involved). Removing the excess rows leaves one row per group, and 11,812 rows are removed.
- 4 further duplicates surfaced during cleaning, after the InvoiceDate resolution collapsed two different timestamps into one (see [data_cleaning.md](data_cleaning.md)).

---

## Key Takeaways

1. Remove full-row duplicates first, and re-check for duplicates after any step that overwrites a column used to tell rows apart (for example the InvoiceDate resolution).
2. Build a `TransactionType` column (Sale, Cancellation, Stock Adjustment). The 'C' prefix alone misses 3,394 rows.
3. Flag null Customer_IDs (22.52%) as Guest/Unregistered. Do not drop them, because the revenue is real.
4. Filter non-product StockCodes and junk Descriptions explicitly by name, not only by pattern.
5. Join on StockCode. Description is not reliable as a key, so build one canonical Description per StockCode.
6. Exclude zero-price rows from revenue KPIs.
7. Resolve multi-country customers and multi-date invoices with most-frequent and earliest-value lookups before building the dimension tables.
