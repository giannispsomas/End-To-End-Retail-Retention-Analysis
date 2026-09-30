# Data Cleaning

## Overview

- **Source table:** `dbo.online_retail_II` (raw, untouched throughout)
- **Working table:** `dbo.online_retail_II_clean` (all cleaning applied here)
- **Final output:** `dbo.online_retail_II_fact` (filtered, analysis-ready)
- **Tool:** SQL Server (T-SQL)
- **Purpose:** resolve every issue found in [data_profiling.md](data_profiling.md) and produce a trustworthy fact table
- **Raw row count:** 1,044,848 (after the 22,523 overlapping rows between the two source sheets were removed at load, see [data_profiling.md](data_profiling.md#source-file-and-load))
- **Clean table row count:** 1,026,237
- **Final fact table row count:** 1,003,352

**Principle used throughout.** Flag a row when it still represents a real business event (guest transactions, non-product fees, cancellations). Delete a row only when it is meaningless noise (junk descriptions, exact duplicates). Flagged rows stay in the clean table and are excluded from the fact table only through explicit, documented conditions.

**Counts differ from profiling.** Profiling counts are on the raw table. Cleaning counts are taken at the step where they ran, after earlier removals. For example, profiling found 206,844 Description rows with whitespace and cleaning trimmed 204,569, because duplicates and junk rows had already been removed.

---

## Column-by-Column Cleaning

### Invoice

- Removed full-row exact duplicates: **11,812 rows** (11,001 duplicate groups, 22,813 rows involved).
- Cancellation invoices ('C' prefix) are classified through `TransactionType`, not deleted.
- The 6 rows with an 'A' prefix were inspected and kept, treated as Sale within the `TransactionType` logic.

### Description

- Removed rows with no Description: **4,275 rows**.
- Trimmed leading and trailing whitespace: **204,569 rows changed** (value change only).
- Converted all remaining values to uppercase: **4,999 rows changed** (value change only).
- Removed very short descriptions (3 characters or fewer: wet, FBA, MIA, ?, ??, ???): **106 rows**.
- Removed placeholder and junk values: **2,414 rows**. The rule is split by casing:
  - **Uppercase descriptions** (where real products live) are deleted only on an exact match to a confirmed junk value: DOTCOM POSTAGE, SAMPLES, AMAZON FEE, CHECK, AMAZON, MISSING, DAMAGED, FOUND, POSSIBLE DAMAGES OR LOST?, WET/MOULDY, UPDATE. This removed **1,572 rows** across 10 distinct values.
  - **Non-uppercase descriptions** (staff notes such as "Adjustment by john on 26/01/2010") are matched on substring patterns: damage, missing, found, adjust, smash, broken, crush, thrown away, wet, rusty, mould, lost, dotcom, amazon, ebay, test, sample, check, update. This removed **842 rows** across 139 distinct values, all individually reviewed and confirmed as junk.
  - The original rule applied the patterns to all casing. It removed 5,270 rows, including real products such as SET OF 4 PANTRY JELLY MOULDS, BROWN CHECK CAT DOORSTOP, the BAKING MOULD range and the CRUSOE CHECK lampshades. Splitting by casing restored them (see [Lessons](#lessons)).
- Built the canonical Description per StockCode (most frequent Description, ties broken alphabetically) and applied it: **715 StockCodes fixed**. StockCodes with more than one Description went from 715 to 0.

### StockCode

- Trimmed whitespace: **1 row changed**.
- Compiled the confirmed non-product code list after manual review: POST, DOT, M, C2, C3, D, B, S, CRUK, BANK CHARGES, AMAZONFEE, ADJUST, ADJUST2, TEST001, TEST002, and gift_0001_10 through gift_0001_90. DCGS% and SP1002 were reviewed and confirmed as legitimate products, so they are not on the list.
- Flagged matching rows with `IsNonProductCode`: **4,035 rows flagged as non-product**, 1,022,202 as legitimate products.

### Country

- Built the Customer_ID to most-frequent-Country lookup (ties broken alphabetically) and applied it: **12 multi-country customers** resolved to one country each.
- 'Unspecified' (756 rows in the raw table) and 'European Community' (61) are real transactions and were not changed.

### InvoiceDate

- Built the Invoice to earliest-InvoiceDate lookup and applied it, resolving **83 invoices** that had two distinct dates.
- Re-ran full-row duplicate detection afterwards and found **4 new exact duplicates**. Two rows that differed only by InvoiceDate became identical once both took the same resolved date. These 4 rows were removed.

### Price

- Rounded Price to 3 decimals, the finest precision found in the data: **820,333 rows changed** (value change only). This step runs right after the Country fix and before the InvoiceDate fix, so the final duplicate check compares rounded prices instead of raw floats that could differ in trailing digits.
- Flagged zero or negative Price with `PriceFlag = 'Zero/Adjustment'`: **943 rows**. This is far below the 6,024 zero-price rows in profiling, because most of them belonged to junk or null-Description rows that earlier steps had already removed.
- The 5 null prices found in profiling have no dedicated step. Any that remain in the clean table fail the `Price > 0` condition of the fact table rule and are excluded there, and the fact table null check returned 0.

### Customer_ID

- Flagged missing Customer_ID as Guest/Unregistered in `CustomerType` and did not drop the rows, because the revenue is real and the rows are needed for product-level analysis: **228,452 rows Guest**, 797,785 Registered.

### Quantity

- Flagged extreme quantities with `OutliersInQnt = 'Wholesale/Bulk'` where `ABS(Quantity) > 100` (the P99 threshold): **10,685 rows**, 1,015,552 Normal.

### TransactionType

Rule, applied in this priority order:

1. `Invoice LIKE 'C%'` gives **Cancellation**.
2. `Quantity <= 0 AND Price = 0` gives **Stock Adjustment**.
3. `Quantity <= 0` gives **Return**.
4. Anything else gives **Sale**.

| TransactionType | Rows |
|---|---|
| Sale | 1,007,179 |
| Cancellation | 18,934 |
| Stock Adjustment | 124 |
| Return | 0 |

The four categories were validated to sum to the exact table row count before the column was committed. The Return rule matches no rows here, because every non-cancelled row with `Quantity <= 0` also has `Price = 0` and is caught by the Stock Adjustment rule first. The rule stays as a safety net for future data.

### CustomerSegment

- Calculated each registered customer's average Quantity (Sale transactions only), cast to `float` before averaging so the value is not truncated to a whole number.
- Set the Wholesale/Retail cutoff at the P95 of that average: **about 45.33**.
- Result: **294 Wholesale** (26,255 rows), **5,576 Retail** (771,410 rows) and **53 N/A** (228,572 rows, guests and customers with no Sale history, relabeled from NULL).

### IsCensored

- Took each registered customer's first purchase date (Sale transactions only).
- Set the cutoff at 90 days before the dataset end (9 December 2011), which is 10 September 2011.
- Result: **598 censored** customers (27,516 rows) and **5,272 not censored** (770,149 rows). 53 are NULL or N/A: guests and customers with no Sale row, who have no window to observe repeat purchases.

### IsPartialMonth

- Flagged the final calendar month as partial when the last InvoiceDate falls before that month's last day. The dataset ends 9 December 2011, so December 2011 has only 9 days: **25,180 rows** flagged Partial, 1,001,057 Regular.

---

## Fact Table Construction

The fact table inclusion rule:

```sql
TransactionType = 'Sale'
AND IsNonProductCode = 0
AND Description IS NOT NULL
AND Price > 0
```

This excluded **22,885 rows** and leaves **1,003,352**. It was built once, after the final duplicate pass, so the fact table reflects the fully deduplicated clean table.

## Row Count Log

| Step | Description | Rows before | Rows removed | Rows after | Notes |
|---|---|---|---|---|---|
| 0 | Raw dataset | 1,044,848 | none | 1,044,848 | Starting point |
| 1 | Remove full-row exact duplicates | 1,044,848 | 11,812 | 1,033,036 | 11,001 duplicate groups |
| 2 | Remove rows with no Description | 1,033,036 | 4,275 | 1,028,761 | |
| 3 | Remove very short descriptions | 1,028,761 | 106 | 1,028,655 | 3 characters or fewer |
| 4 | Remove junk Description values | 1,028,655 | 2,414 | 1,026,241 | Rule split by casing |
| 5 | Trim whitespace on Description | 1,026,241 | 0 | 1,026,241 | 204,569 rows changed |
| 6 | Trim whitespace on StockCode | 1,026,241 | 0 | 1,026,241 | 1 row changed |
| 7 | Uppercase Description | 1,026,241 | 0 | 1,026,241 | 4,999 rows changed |
| 8 | Canonical Description per StockCode | 1,026,241 | 0 | 1,026,241 | 715 StockCodes fixed |
| 9 | Customer_ID to Country lookup | 1,026,241 | 0 | 1,026,241 | 12 customers fixed |
| 10 | Round Price to 3 decimals | 1,026,241 | 0 | 1,026,241 | 820,333 rows changed, run before step 11 |
| 11 | Resolve multi-date invoices | 1,026,241 | 0 | 1,026,241 | 83 invoices fixed |
| 12 | Re-run duplicate removal | 1,026,241 | 4 | 1,026,237 | Duplicates created by steps 10 and 11 |
| 13 | Flag non-product StockCodes | 1,026,237 | 0 | 1,026,237 | 4,035 flagged |
| 14 | Flag missing Customer_ID as Guest | 1,026,237 | 0 | 1,026,237 | 228,452 flagged |
| 15 | Flag zero or negative Price | 1,026,237 | 0 | 1,026,237 | 943 flagged |
| 16 | Flag extreme quantities | 1,026,237 | 0 | 1,026,237 | 10,685 flagged |
| 17 | Flag partial final month | 1,026,237 | 0 | 1,026,237 | 25,180 flagged |
| 18 | Classify TransactionType | 1,026,237 | 0 | 1,026,237 | 0 Return rows |
| 19 | Flag Wholesale or Retail segment | 1,026,237 | 0 | 1,026,237 | 294 / 5,576 / 53 customers |
| 20 | Flag right-censored customers | 1,026,237 | 0 | 1,026,237 | 598 / 5,272 / 53 customers |
| 21 | Apply fact table inclusion rule | 1,026,237 | 22,885 | 1,003,352 | Final row set |
| **End** | **Final fact table** | | | **1,003,352** | |

## Fact Table Validation

| Check | Result | Verdict |
|---|---|---|
| Nulls (all columns except Customer_ID) | 0 | Pass |
| Customer_ID nulls in fact table | 226,760 | Expected, guest rows are kept |
| Min Price | 0.001 | Pass (above 0) |
| Max Price | 1,157.15 | n/a |
| Min Quantity | 1 | Pass (no negatives or zeros, so the Sale filter worked) |
| Max Quantity | 80,995 | n/a |
| Min InvoiceDate | 2009-12-01 07:45:00 | n/a |
| Max InvoiceDate | 2011-12-09 12:50:00 | n/a |
| Full-row duplicates in fact table | 0 | Pass |

## Clean Table vs Fact Table

| Metric | Clean table | Fact table | Difference |
|---|---|---|---|
| Total rows | 1,026,237 | 1,003,352 | 22,885 |
| Distinct StockCodes | 4,750 | 4,724 | 26 |
| Distinct customers | 5,923 | 5,852 | 71 |
| Distinct countries | 43 | 43 | 0 |
| Null Descriptions | 0 | 0 | 0 |
| Zero or negative Price rows | 943 | 0 | 943 |
| Null Customer_ID rows | 228,452 | 226,760 | 1,692 |

| Ratio | Value |
|---|---|
| Guest share of rows, clean table | 22.3% |
| Guest share of rows, fact table | 22.6% |
| Row retention, raw to fact | 96.0% |
| Row retention, clean to fact | 97.8% |

## Revenue Validation

`SUM(Quantity * Price)` was recomputed by hand for sampled invoices and matched the fact table. Example, Invoice 536365 with 7 line items:

| StockCode | Quantity | Price | Line total |
|---|---|---|---|
| 85123A | 6 | 2.55 | 15.30 |
| 71053 | 6 | 3.39 | 20.34 |
| 84406B | 8 | 2.75 | 22.00 |
| 84029G | 6 | 3.39 | 20.34 |
| 84029E | 6 | 3.39 | 20.34 |
| 22752 | 2 | 7.65 | 15.30 |
| 21730 | 6 | 4.25 | 25.50 |

The hand total is **£139.12** and matches `SUM(Quantity * Price)` exactly, so the filtering neither dropped nor duplicated legitimate line items. The star schema build reconciles the whole valid set again in [star_schema.md](star_schema.md).

---

## Lessons

- **Order matters, but it is not strictly linear.** The InvoiceDate fix and the Price rounding are value fixes, and they surfaced full-row duplicates that did not exist at the time of the first deduplication. After any step that overwrites a column used to detect duplicates, re-check for duplicates once, after the last such step.
- **A substring rule cannot tell junk text from a real product that shares a word.** Patterns like `%mould%` and `%check%` deleted real products together with junk. Splitting the rule by casing fixed this: exact match for uppercase text, where real products live, and pattern match for non-uppercase staff notes, which were individually reviewed.
- **`Price` is stored as `float`,** so two logically equal prices can differ in their last digits and slip past a duplicate check. Rounding to 3 decimals before the final duplicate pass makes the comparison stable.
- **Cast `Quantity` before averaging.** `avg(Quantity)` on a `bigint` column truncates each customer's average to a whole number before any percentile is taken. `avg(cast(Quantity as float))` keeps the precision the P95 cutoff needs.
- **Flag, do not delete, when the row is still a real business event** (guest transactions, non-product fees, cancellations). Delete only when the row is meaningless noise (junk descriptions, exact duplicates).
- **Every lookup followed the same pattern** (Description, Country, InvoiceDate): rank the candidate values by the chosen rule (most frequent with an explicit tie-breaker, or earliest), keep the top row per entity, save it as a small lookup table, then `UPDATE ... JOIN` it back onto the main table.
