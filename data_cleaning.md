# Data Cleaning

## Overview
- Source table: `dbo.online_retail_II` (raw, untouched throughout)
- Working table: `dbo.online_retail_II_clean` (all cleaning applied here)
- Final output: `dbo.online_retail_II_fact` (filtered, analysis-ready fact table)
- Tool: SQL Server (T-SQL)
- Purpose: Resolve every issue identified in Data Profiling, producing a trustworthy fact table for analysis
- Raw row count: 1,044,848
- Final fact table row count: 1,003,352

## Column-by-Column Cleaning

### Invoice
- [x] Remove full-row exact duplicates. **11,812 rows removed** (11,001 distinct duplicate groups, 22,813 total rows involved).
- [x] Cancellation invoices ('C' prefix) handled via TransactionType classification, not deletion.
- [x] 6 rows with 'A' prefix inspected — retained, treated as Sale/Normal within TransactionType logic.

### Description
- [x] Remove rows with no Description. **4,275 rows removed.**
- [x] Trim leading/trailing whitespace. **204,569 rows changed** (value change only, no rows removed).
- [x] Normalize all remaining Description values to UPPERCASE. **4,999 rows changed** (value change only).
- [x] Remove very short descriptions (≤3 chars: wet, FBA, MIA, ?, ??, ???). **106 rows removed.**
- [x] Remove placeholder/junk Description values. **2,414 rows removed** — corrected rule, split by casing:
  - **Uppercase descriptions** (where real products live): deleted only on an exact match to a confirmed junk value (DOTCOM POSTAGE, SAMPLES, AMAZON FEE, CHECK, AMAZON, MISSING, DAMAGED, FOUND, POSSIBLE DAMAGES OR LOST?, WET/MOULDY, UPDATE) — **1,572 rows** across 10 distinct values.
  - **Non-uppercase descriptions** (staff notes, e.g. "Adjustment by john on 26/01/2010"): kept the original substring patterns (damage, missing, found, adjust, smash, broken, crush, thrown away, wet, rusty, mould, lost, dotcom, amazon, ebay, test, sample, check, update) — **842 rows** across 139 distinct values, all individually reviewed and confirmed junk.
  - The original pattern-only rule (applied to all casing) removed 5,270 rows, including real products such as SET OF 4 PANTRY JELLY MOULDS, BROWN CHECK CAT DOORSTOP, the BAKING MOULD range, and the CRUSOE CHECK lampshades. Splitting by casing restored those products; see Lessons below.
- [x] Build the canonical Description-per-StockCode lookup (most frequent Description per StockCode, ties broken alphabetically) and apply it. **715 StockCodes fixed** (multi-description count before: 715, after: 0).

### StockCode
- [x] Trim leading/trailing whitespace. **1 row changed** (value change only).
- [x] Query distinct non-standard StockCodes, manually review, compile confirmed non-product code list (POST, DOT, M, C2, C3, D, B, S, CRUK, BANK CHARGES, AMAZONFEE, ADJUST, ADJUST2, TEST001, TEST002, gift_0001_10 through gift_0001_90). DCGS% and SP1002 codes reviewed and confirmed legitimate products — excluded from the non-product list.
- [x] Flag rows matching the confirmed non-product list (`IsNonProductCode`). **4,035 rows flagged as non-product**, 1,022,202 flagged as legitimate product.

### Country
- [x] Build the Customer_ID → most-frequent-Country lookup (ties broken alphabetically) and apply it. **12 multi-country customers resolved** to a single Country each.

### InvoiceDate
- [x] Build the Invoice → earliest-InvoiceDate lookup and apply it, resolving 83 invoices that had more than one distinct date.
- [x] **Re-ran full-row duplicate detection after this fix** — found 4 new exact duplicate rows, created because two previously-distinct rows (differing only by InvoiceDate) became identical once both were overwritten to the same resolved date. **4 rows removed.**

### Price
- [x] Round Price to 3 decimals, the finest precision found in the data. **820,333 rows changed** (value change only) — moved to run immediately after the Country fix and before the InvoiceDate fix, so the duplicate re-check above compares final, rounded prices rather than raw float values that could differ in trailing digits.
- [x] Flag zero/negative Price rows (`PriceFlag = 'Zero/Adjustment'`). **943 rows flagged** (lower than the original profiling count of 6,024 — most zero-price rows were tied to junk/null Descriptions already removed earlier).

### Customer_ID
- [x] Flag missing Customer IDs as Guest/Unregistered (`CustomerType`). Not dropped — retained for product-level analysis. **228,452 rows flagged Guest**, 797,785 flagged Registered.

### Quantity
- [x] Flag extreme outlier quantities (`OutliersInQnt = 'Wholesale/Bulk'`) using the P99 threshold (`ABS(Quantity) > 100`). **10,685 rows flagged**, 1,015,552 flagged Normal transaction.

### TransactionType
- [x] Defined and applied the classification rule, in priority order:
  1. `Invoice LIKE 'C%'` → **Cancellation**
  2. `Quantity <= 0 AND Price = 0` → **Stock Adjustment**
  3. `Quantity <= 0` → **Return**
  4. else → **Sale**
- Validated the four categories sum to the exact table row count before committing the column.
- Result: **18,934 Cancellation, 124 Stock Adjustment, 0 Return, 1,007,179 Sale.** The Return rule matches no rows in this dataset — every non-cancelled row with `Quantity <= 0` also has `Price = 0` and is caught by the Stock Adjustment rule first. The rule is kept as a safety net for future data.

### CustomerSegment
- [x] Calculated average Quantity per customer (Sale transactions only, registered customers only), cast to `float` before averaging so the value isn't truncated to a whole number.
- [x] Determined threshold via P95 of average-quantity-per-customer (**P95 ≈ 45.33**), used as the Wholesale/Retail cutoff.
- [x] Built the lookup and applied it (`CustomerSegment`). Result: **294 Wholesale (26,255 rows), 5,576 Retail (771,410 rows), 53 N/A (228,572 rows)** — Guest/no-Sale-history customers relabeled from NULL for clarity.

### IsCensored (right-censoring flag)
- [x] Calculated each registered customer's first purchase date (Sale transactions only).
- [x] Cutoff = 90 days before dataset end (Dec 9, 2011) = Sep 10, 2011.
- [x] Built the lookup and applied it (`IsCensored`). Result: **598 censored (27,516 rows), 5,272 not censored (770,149 rows), 53 NULL/N/A** (guests and customers with no Sale row — insufficient window to observe repeat-purchase behavior).

### IsPartialMonth
- [x] Flagged the final calendar month as partial when the last InvoiceDate falls before that month's last day (dataset ends Dec 9, 2011 — only 9 days of December). **25,180 rows flagged** Partial month, 1,001,057 Regular month.

## Fact Table Construction

- [x] Applied the fact table inclusion rule:
  ```
  TransactionType = 'Sale' 
  AND IsNonProductCode = 0 
  AND Description IS NOT NULL 
  AND Price > 0
  ```
- **22,885 rows excluded**, final fact table row count: **1,003,352**.
- Built once, after the final duplicate pass, so the fact table reflects the fully deduplicated clean table.

## Row Count Log

| Step | Description | Rows Before | Rows Removed | Rows After | Notes |
|---|---|---|---|---|---|
| 0 | Raw dataset | 1,044,848 | — | 1,044,848 | Starting point |
| 1 | Remove full-row exact duplicates | 1,044,848 | 11,812 | 1,033,036 | 11,001 duplicate groups |
| 2 | Remove rows with no Description | 1,033,036 | 4,275 | 1,028,761 | |
| 3 | Remove very short descriptions (≤3 chars) | 1,028,761 | 106 | 1,028,655 | |
| 4 | Remove junk/placeholder Description values | 1,028,655 | 2,414 | 1,026,241 | Corrected rule — split by casing |
| 5 | Trim whitespace on Description | 1,026,241 | 0 (204,569 rows changed) | 1,026,241 | Value change only |
| 6 | Trim whitespace on StockCode | 1,026,241 | 0 (1 row changed) | 1,026,241 | Value change only |
| 7 | Normalize Description to UPPERCASE | 1,026,241 | 0 (4,999 rows changed) | 1,026,241 | Value change only |
| 8 | Apply canonical Description-per-StockCode lookup | 1,026,241 | 0 | 1,026,241 | 715 StockCodes fixed |
| 9 | Apply Customer_ID → Country lookup | 1,026,241 | 0 | 1,026,241 | 12 customers fixed |
| 10 | Round Price to 3 decimals | 1,026,241 | 0 (820,333 rows changed) | 1,026,241 | Value change only — moved ahead of the InvoiceDate fix |
| 11 | Resolve multi-date Invoices | 1,026,241 | 0 | 1,026,241 | 83 invoices fixed |
| 12 | Re-run full-row duplicate removal (post-fix) | 1,026,241 | 4 | 1,026,237 | New duplicates surfaced by the Price/InvoiceDate fixes |
| 13 | Flag non-product StockCodes | 1,026,237 | 0 | 1,026,237 | 4,035 flagged |
| 14 | Flag missing Customer IDs as Guest | 1,026,237 | 0 | 1,026,237 | 228,452 flagged Guest |
| 15 | Flag zero/negative Price rows | 1,026,237 | 0 | 1,026,237 | 943 flagged |
| 16 | Flag extreme outlier quantities | 1,026,237 | 0 | 1,026,237 | 10,685 flagged |
| 17 | Flag partial final month | 1,026,237 | 0 | 1,026,237 | 25,180 flagged |
| 18 | Classify TransactionType | 1,026,237 | 0 | 1,026,237 | 0 Return rows found |
| 19 | Flag Wholesale/Retail segment | 1,026,237 | 0 | 1,026,237 | 294 / 5,576 / 53 customers |
| 20 | Flag right-censored customers | 1,026,237 | 0 | 1,026,237 | 598 / 5,272 / 53 customers |
| 21 | Apply fact table inclusion rule | 1,026,237 | 22,885 | 1,003,352 | Final filtered row set |
| **END** | **Final fact table row count** | | | **1,003,352** | |

## Fact Table Validation

| Check | Result | Verdict |
|---|---|---|
| Nulls (all columns except Customer_ID) | 0 | PASS |
| Customer_ID nulls in fact table | 226,760 | Expected — Guest rows retained |
| Min Price | 0.001 | PASS (above 0) |
| Max Price | 1,157.15 | — |
| Min Quantity | 1 | PASS — no negatives or zeros, confirms Sale filter worked |
| Max Quantity | 80,995 | — |
| Min InvoiceDate | 2009-12-01 07:45:00 | — |
| Max InvoiceDate | 2011-12-09 12:50:00 | — |
| Full-row duplicates in fact table | 0 | PASS |

## Clean Table vs Fact Table Comparison

| Metric | Clean Table | Fact Table | Difference |
|---|---|---|---|
| Total rows | 1,026,237 | 1,003,352 | 22,885 |
| Distinct StockCodes | 4,750 | 4,724 | 26 |
| Distinct Customers | 5,923 | 5,852 | 71 |
| Distinct Countries | 43 | 43 | 0 |
| Null Descriptions | 0 | 0 | 0 |
| Zero/negative Price rows | 943 | 0 | 943 |
| Null Customer_ID rows | 228,452 | 226,760 | 1,692 |

## Key Ratios

| Metric | Value |
|---|---|
| Guest (null Customer_ID) share, clean table | 22.3% |
| Guest (null Customer_ID) share, fact table | 22.6% |
| Row retention, raw → fact table | 96.0% |
| Row retention, clean → fact table | 97.8% |

## Revenue Validation

Manually recomputed `SUM(Quantity * Price)` for sampled invoices from the fact table and confirmed the total matched line-item-level manual calculation. Example — Invoice 536365, 7 line items:

| StockCode | Quantity | Price | Line total |
|---|---|---|---|
| 85123A | 6 | 2.55 | 15.30 |
| 71053 | 6 | 3.39 | 20.34 |
| 84406B | 8 | 2.75 | 22.00 |
| 84029G | 6 | 3.39 | 20.34 |
| 84029E | 6 | 3.39 | 20.34 |
| 22752 | 2 | 7.65 | 15.30 |
| 21730 | 6 | 4.25 | 25.50 |

Hand total: **£139.12** — matches `SUM(Quantity * Price)` exactly, confirming the filtering logic neither dropped nor duplicated legitimate line items.

## Lessons / Notes for Future Reference

- **Order matters, but isn't strictly linear**: resolving the InvoiceDate multi-date issue and the Price rounding (both value fixes) surfaced new full-row duplicates that hadn't existed at the time of the original deduplication step. Any step that overwrites a column used in the duplicate-detection logic should be followed by a re-check for duplicates, run once, after the last such step.
- **A substring rule can't tell junk text from a real product that happens to share a word.** The original junk-Description rule matched on patterns like `%mould%` and `%check%` across all casing, and deleted real products (SET OF 4 PANTRY JELLY MOULDS, BROWN CHECK CAT DOORSTOP, the BAKING MOULD range, the CRUSOE CHECK lampshades) along with genuine junk. Splitting the rule by casing — exact match only for uppercase text, where real products live; pattern match for non-uppercase staff notes, which were individually reviewed — fixed this without losing any of the confirmed junk.
- **`Price` is stored as `float`**, so two logically equal prices can differ in their last digits and slip past a duplicate check. Rounding it to 3 decimals earlier in the script, before the final duplicate pass, ensures that pass compares final, stable values.
- **Casting `Quantity` before averaging matters.** `avg(Quantity)` on a `bigint` column truncates every customer's average to a whole number before any percentile is taken. Casting to `float` first (`avg(cast(Quantity as float))`) keeps the decimal precision the P95 cutoff needs.
- **Flag, don't delete, when the row still represents a real business event** (guest transactions, non-product fees, cancellations) — these were preserved in `online_retail_II_clean` and only excluded from the final `online_retail_II_fact` via explicit, documented filter conditions.
- **Delete only when the row itself is meaningless noise** (junk Description values, exact duplicates) — these have no informational value even for auxiliary analysis.
- **Every lookup table (Description, Country, InvoiceDate) followed the same three-step pattern**: rank candidate values by the chosen rule (most frequent, with an explicit tie-breaker; or earliest), keep the top-ranked row per entity, save as a small answer-key table, then `UPDATE ... JOIN` it back onto the main table.
