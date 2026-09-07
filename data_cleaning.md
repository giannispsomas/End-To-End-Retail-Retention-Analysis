# Data Cleaning

## Overview
- Source table: `dbo.online_retail_II` (raw, untouched throughout)
- Working table: `dbo.online_retail_II_clean` (all cleaning applied here)
- Final output: `dbo.online_retail_II_fact` (filtered, analysis-ready fact table)
- Tool: SQL Server (T-SQL)
- Purpose: Resolve every issue identified in Data Profiling, producing a trustworthy fact table for analysis
- Raw row count: 1,044,848
- Final fact table row count: 1,000,522

## Column-by-Column Cleaning

### Invoice
- [x] Remove full-row exact duplicates. **11,812 rows removed** (11,001 distinct duplicate groups, 22,813 total rows involved).
- [x] Cancellation invoices ('C' prefix) handled via TransactionType classification, not deletion.
- [x] 6 rows with 'A' prefix inspected — retained, treated as Sale/Normal within TransactionType logic.

### Description
- [x] Remove rows with no Description. **4,275 rows removed.**
- [x] Trim leading/trailing whitespace. **204,102 rows changed** (value change only, no rows removed).
- [x] Normalize all remaining Description values to UPPERCASE. **4,999 rows changed** (value change only).
- [x] Remove very short descriptions (≤3 chars: wet, FBA, MIA, ?, ??, ???). **106 rows removed.**
- [x] Remove placeholder/junk Description values (damage, missing, found, adjust, smash, broken, crush, thrown away, wet, rusty, mould, lost, dotcom, amazon, ebay, test, sample, check, update). **5,270 rows removed.**
- [x] Build the canonical Description-per-StockCode lookup (most frequent Description per StockCode) and apply it. **710 StockCodes fixed** (multi-description count before: 710, after: 0).

### StockCode
- [x] Trim leading/trailing whitespace. **1 row changed** (value change only).
- [x] Query distinct non-standard StockCodes, manually review, compile confirmed non-product code list (POST, DOT, M, C2, C3, D, B, S, CRUK, BANK CHARGES, AMAZONFEE, ADJUST, ADJUST2, TEST001, TEST002, gift_0001_10 through gift_0001_90). DCGS% and SP1002 codes reviewed and confirmed legitimate products — excluded from the non-product list.
- [x] Flag rows matching the confirmed non-product list (`IsNonProductCode`). **4,035 rows flagged as non-product**, 1,019,350 flagged as legitimate product.

### Country
- [x] Build the Customer_ID → most-frequent-Country lookup and apply it. **12 multi-country customers resolved** to a single Country each.

### InvoiceDate
- [x] Build the Invoice → earliest-InvoiceDate lookup and apply it, resolving 83 invoices that had more than one distinct date.
- [x] **Re-ran full-row duplicate detection after this fix** — found 4 new exact duplicate rows, created because two previously-distinct rows (differing only by InvoiceDate) became identical once both were overwritten to the same resolved date. **4 rows removed.**

### Customer_ID
- [x] Flag missing Customer IDs as Guest/Unregistered (`CustomerType`). Not dropped — retained for product-level analysis. **227,787 rows flagged Guest**, remainder flagged Registered.

### Price
- [x] Flag zero/negative Price rows (`PriceFlag = 'Zero/Adjustment'`). **941 rows flagged** (lower than the original profiling count of 6,024 — most zero-price rows were tied to junk/null Descriptions already removed earlier).

### Quantity
- [x] Flag extreme outlier quantities (`QuantityFlag = 'Wholesale/Bulk'`) using the P99 threshold (`ABS(Quantity) > 100`).

### TransactionType
- [x] Defined and applied the classification rule, in priority order:
  1. `Invoice LIKE 'C%'` → **Cancellation**
  2. `Quantity <= 0 AND Price = 0` → **Stock Adjustment**
  3. `Quantity <= 0` → **Return**
  4. else → **Sale**
- Validated the four categories sum to the exact table row count before committing the column.
- Result: 18,910 Cancellation, 941 Stock Adjustment, 3,393 Return, remainder Sale.

### CustomerSegment
- [x] Calculated average Quantity per customer (Sale transactions only).
- [x] Determined threshold via P95 of average-quantity-per-customer (**P95 = 45**), used as the Wholesale/Retail cutoff.
- [x] Built the lookup and applied it (`CustomerSegment`). Result: 26,197 Wholesale, 769,281 Retail, 227,907 N/A (Guest/no Sale history — relabeled from NULL for clarity).

### IsCensored (right-censoring flag)
- [x] Calculated each customer's first purchase date (Sale transactions only).
- [x] Cutoff = 90 days before dataset end (Dec 9, 2011) = Sep 10, 2011.
- [x] Built the lookup and applied it (`IsCensored`). Customers whose first purchase falls after the cutoff are flagged as censored (insufficient window to observe repeat-purchase behavior).

### IsPartialMonth
- [x] Flagged December 2011 rows as a partial month (dataset ends Dec 9, 2011 — only 9 days of data). **25,107 rows flagged** Partial month, 998,278 Regular month.

## Fact Table Construction

- [x] Applied the fact table inclusion rule:
  ```
  TransactionType = 'Sale' 
  AND IsNonProductCode = 0 
  AND Description IS NOT NULL 
  AND Price > 0
  ```
- **22,859 rows excluded**, final fact table row count: **1,000,522**.
- Table rebuilt once after the InvoiceDate-triggered duplicate fix, to ensure the fact table reflects the fully deduplicated clean table.

## Row Count Log

| Step | Description | Rows Before | Rows Removed | Rows After | Notes |
|---|---|---|---|---|---|
| 0 | Raw dataset | 1,044,848 | — | 1,044,848 | Starting point |
| 1 | Remove full-row exact duplicates | 1,044,848 | 11,812 | 1,033,036 | |
| 2 | Remove rows with no Description | 1,033,036 | 4,275 | 1,028,761 | |
| 3 | Remove very short descriptions (≤3 chars) | 1,028,761 | 106 | 1,028,655 | |
| 4 | Remove placeholder/junk Description values | 1,028,655 | 5,270 | 1,023,385 | |
| 5 | Trim whitespace on Description | 1,023,385 | 0 (204,102 rows changed) | 1,023,385 | Value change only |
| 6 | Trim whitespace on StockCode | 1,023,385 | 0 (1 row changed) | 1,023,385 | Value change only |
| 7 | Normalize Description to UPPERCASE | 1,023,385 | 0 (4,999 rows changed) | 1,023,385 | Value change only |
| 8 | Apply canonical Description-per-StockCode lookup | 1,023,385 | 0 | 1,023,385 | 710 StockCodes fixed |
| 9 | Apply Customer_ID → Country lookup | 1,023,385 | 0 | 1,023,385 | 12 customers fixed |
| 10 | Flag non-product StockCodes | 1,023,385 | 0 | 1,023,385 | 4,035 flagged |
| 11 | Resolve multi-date Invoices | 1,023,385 | 0 | 1,023,385 | 83 invoices fixed |
| 12 | Re-run full-row duplicate removal (post-InvoiceDate fix) | 1,023,385 | 4 | 1,023,381 | New duplicates surfaced by InvoiceDate fix |
| 13 | Flag missing Customer IDs as Guest | 1,023,381 | 0 | 1,023,381 | 227,787 flagged Guest |
| 14 | Classify TransactionType | 1,023,381 | 0 | 1,023,381 | |
| 15 | Flag zero/negative Price rows | 1,023,381 | 0 | 1,023,381 | 941 flagged |
| 16 | Flag extreme outlier quantities | 1,023,381 | 0 | 1,023,381 | |
| 17 | Flag Wholesale/Retail segment | 1,023,381 | 0 | 1,023,381 | |
| 18 | Flag right-censored customers | 1,023,381 | 0 | 1,023,381 | |
| 19 | Flag December 2011 as partial month | 1,023,381 | 0 | 1,023,381 | 25,107 flagged |
| 20 | Apply fact table inclusion rule | 1,023,381 | 22,859 | 1,000,522 | Final filtered row set |
| **END** | **Final fact table row count** | | | **1,000,522** | |

## Fact Table Validation

| Check | Result | Verdict |
|---|---|---|
| Nulls (all columns except Customer_ID) | 0 | PASS |
| Customer_ID nulls in fact table | 226,097 | Expected — Guest rows retained |
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
| Total rows | 1,023,381 | 1,000,522 | 22,859 |
| Distinct StockCodes | 4,733 | 4,707 | 26 |
| Distinct Customers | 5,922 | 5,851 | 71 |
| Distinct Countries | 43 | 43 | 0 |
| Null Descriptions | 0 | 0 | 0 |
| Zero/negative Price rows | 941 | 0 | 941 |
| Null Customer_ID rows | 227,787 | 226,097 | 1,690 |

## Key Ratios

| Metric | Value |
|---|---|
| Guest (null Customer_ID) share, clean table | 22.3% |
| Guest (null Customer_ID) share, fact table | 22.6% |
| Row retention, raw → fact table | 95.75% |
| Row retention, clean → fact table | 97.77% |

## Revenue Validation

Manually recomputed `SUM(Quantity * Price)` for a sample of invoices from the fact table and confirmed the total matched line-item-level manual calculation, verifying the filtering logic neither dropped nor duplicated legitimate line items.

## Lessons / Notes for Future Reference

- **Order matters, but isn't strictly linear**: resolving the InvoiceDate multi-date issue (a value fix) surfaced new full-row duplicates that hadn't existed at the time of the original deduplication step. Any step that overwrites a column used in the duplicate-detection logic should be followed by a re-check for duplicates.
- **Flag, don't delete, when the row still represents a real business event** (guest transactions, non-product fees, cancellations) — these were preserved in `online_retail_II_clean` and only excluded from the final `online_retail_II_fact` via explicit, documented filter conditions.
- **Delete only when the row itself is meaningless noise** (junk Description values, exact duplicates) — these have no informational value even for auxiliary analysis.
- **Every lookup table (Description, Country, InvoiceDate) followed the same three-step pattern**: rank candidate values by the chosen rule (most frequent, or earliest), keep the top-ranked row per entity, save as a small answer-key table, then `UPDATE ... JOIN` it back onto the main table.
