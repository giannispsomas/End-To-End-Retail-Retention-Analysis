# Star Schema Build

## Overview
- Source table: `dbo.online_retail_II_clean` (cleaned working table, see Data Cleaning doc)
- Target database: `OnlineRetailII`
- Schemas: `dim` (dimension tables), `fact` (fact table)
- Tool: SQL Server (T-SQL)
- Methodology: Kimball 4-step dimensional design (business process → grain → dimensions → facts)
- Purpose: Transform the cleaned, row-level transaction table into a queryable star schema for reporting and analysis
- Source (clean table) row count: 1,026,237
- Fact table row count: 1,026,237

## Dimensional Design (Kimball 4-Step Process)

### Step 1 — Business process
Sales transactions, recorded through invoices.

### Step 2 — Grain
**One row in the fact table = one invoice line item.**
Reworded from "one product line per one invoice" — 11,144 `(invoice, product)` pairs appear on more than one line (the source has no line-item number, and deduplication only removes rows identical in every column), so an invoice can legitimately list the same product twice at different quantities or prices. Order-level counts must use `COUNT(DISTINCT invoice)`, never `COUNT(*)`.

### Step 3 — Dimensions
| Dimension | Attributes |
|---|---|
| `dim.customer` | Customer_ID, CustomerType, CustomerSegment, first_purchase_date, IsCensored |
| `dim.product` | Description, StockCode, IsNonProductCode |
| `dim.date` | FullDate, Year, Quarter, Month, MonthName, YearMonth, DayOfWeekNumber, DayOfWeek, IsWeekend, IsPartialMonth |
| `dim.country` | Country |

`Invoice` is a **degenerate dimension** — no descriptive attributes of its own, so it stays on the fact table rather than becoming a separate dimension table.

**Country moved to its own dimension.** Under the original design, Country lived only on `dim.customer`, so a guest transaction (no Customer_ID) had no way to carry a country and fell back to the Unknown member. That put roughly 22% of fact rows — nearly all UK — under "Unknown" in any country-level report. `dim.country` is now looked up independently per fact row from `_clean.Country`, so guest sales keep their real country.

**IsCensored and first purchase date moved from the fact table to `dim.customer`.** Both are properties of the customer, not of an individual transaction — computing and storing them once per customer is both more correct and cheaper than repeating them on every one of that customer's fact rows.

### Step 4 — Facts (measures)
| Measure | Additive? |
|---|---|
| `Quantity` | Additive (summable, averageable) |
| `Price` | **Non-additive** — average price must be computed as `SUM(sales_amount) / SUM(quantity)`, never `AVG(price)` |
| `SalesAmount` (`Quantity * Price`) | Additive |
| `Invoice` | Not a measure — degenerate dimension, retained for grain/traceability |

## Physical Structure

### Schemas
```sql
if not exists (select 1 from sys.schemas where name = 'fact') exec('create schema fact');
if not exists (select 1 from sys.schemas where name = 'dim') exec('create schema dim');
```

### Table design decisions
- [x] Surrogate keys for every dimension: `int identity(1,1)` for `customer`/`product`/`country`; `date_surrogate_key` uses a `yyyyMMdd` int instead, since it's naturally unique and human-readable
- [x] Natural keys retained alongside surrogate keys: `customer_id`, `stock_code`, `full_date`, `country_name`
- [x] Money columns (`price`, `sales_amount`) use `decimal(18,4)`, never `float`
- [x] Unknown members (key = `-1`) planned for `dim.customer`, `dim.product`, **and `dim.country`**; `dim.date` does not need one (dates are never missing/unmatched by construction)

### Dimension tables
```sql
create table dim.country (
    country_surrogate_key   int identity(1, 1) primary key,
    country_name            varchar(50) not null,
    constraint uniq_country_name unique (country_name)
);

create table dim.customer (
    customer_surrogate_key  int identity(1, 1) primary key,
    customer_id             int null,
    customer_type           varchar(20),
    customer_segment        varchar(20),
    first_purchase_date     date null,
    is_censored             bit null,
    constraint uniq_customer_id unique (customer_id)
);

create table dim.product (
    product_surrogate_key   int identity(1, 1) primary key,
    description             varchar(100),
    stock_code              varchar(20) not null,
    is_non_product_code     bit,
    constraint uniq_product_stock_code unique (stock_code)
);

create table dim.date (
    date_surrogate_key      int primary key,
    full_date               date not null,
    year                    smallint not null,
    quarter                 tinyint not null,
    month                   tinyint not null,
    month_name              varchar(10) not null,
    year_month              char(7) not null,
    day_of_week_number      tinyint not null,       -- 1 = Monday ... 7 = Sunday
    day_of_week             varchar(10) not null,
    is_weekend              bit not null,
    is_partial_month        bit not null
);
```

`dim.product.description` widened from `varchar(50)` to `varchar(100)` — the products restored by the corrected junk-Description rule (see Data Cleaning doc) include longer names than the original sample. `dim.customer` no longer carries `country` (moved to `dim.country`); `is_censored` and `first_purchase_date` are new, populated from the censoring lookup. `dim.date` gained `year`, `quarter`, `month`, `month_name`, `year_month`, and `day_of_week_number` for Power BI's native time intelligence — the original design listed these attributes in Step 4.5 but the first build never implemented them.

### Fact table
```sql
create table fact.sales (
    sales_surrogate_key     bigint identity(1, 1) primary key nonclustered,
    customer_key            int not null,
    product_key             int not null,
    date_key                int not null,
    country_key             int not null,
    invoice                 varchar(20) not null,
    quantity                int not null,
    price                   decimal(18, 4) not null,
    sales_amount            decimal(18, 4) not null,
    price_flag              varchar(20),
    outliers_in_qnt         varchar(20),
    transaction_type        varchar(20) not null,
    constraint fk_sales_customer foreign key (customer_key) references dim.customer(customer_surrogate_key),
    constraint fk_sales_product  foreign key (product_key)  references dim.product(product_surrogate_key),
    constraint fk_sales_date     foreign key (date_key)     references dim.date(date_surrogate_key),
    constraint fk_sales_country  foreign key (country_key)  references dim.country(country_surrogate_key)
);
```
`sales_surrogate_key` is declared `nonclustered` on purpose — leaves the clustered slot free for a clustered columnstore index (Phase 6).

`price` changed from `decimal(10,2)` to `decimal(18,4)`. Cleaning rounds Price to 3 decimals; a `decimal(10,2)` column silently re-rounds that to 2, so `price` and `sales_amount` (computed at full precision as `quantity * price`) could disagree by a fraction of a penny across a million rows. `country_key` is new; `is_censored` and `transaction_type`'s partner column `is_censored` moved off this table entirely (see dimension notes above).

### Constraints
```sql
-- Foreign keys
alter table fact.sales
    add
    constraint fk_sales_customer foreign key (customer_key) references dim.customer(customer_surrogate_key),
    constraint fk_sales_product foreign key (product_key) references dim.product(product_surrogate_key),
    constraint fk_sales_date foreign key (date_key) references dim.date(date_surrogate_key),
    constraint fk_sales_country foreign key (country_key) references dim.country(country_surrogate_key);

-- Unique constraints on natural keys (data quality + lookup speed)
alter table dim.customer add constraint uniq_customer_id unique (customer_id);
alter table dim.product add constraint uniq_product_id unique (stock_code);
alter table dim.country add constraint uniq_country_name unique (country_name);
```

## Entity-Relationship Diagram

The star shape: `sales (fact)` sits at the center, with `date (dim)`, `customer (dim)`, `product (dim)`, and **`country (dim)`** each connected via a single FK relationship — one-to-many from each dimension into the fact table.

<img width="1475" height="791" alt="star_schema_diagram" src="https://github.com/user-attachments/assets/a9211292-fda5-44ea-9b2b-ad8d348a0bb4" />


## Unknown Members

| Dimension | Surrogate key | Natural key | Descriptive attributes |
|---|---|---|---|
| `dim.customer` | -1 | `NULL` | CustomerType = `'Guest/Unregistered'`, CustomerSegment = `'N/A'` |
| `dim.product` | -1 | `'UNKNOWN'` | Description = `'Unknown Product'`, IsNonProductCode = 0 |
| `dim.country` | -1 | n/a | country_name = `'Unknown'` |

Inserted via `set identity_insert ... on/off` so each surrogate key `-1` could be forced in despite the `identity` column.

## Dimension Population

| Dimension | Rows loaded | Method |
|---|---|---|
| `dim.customer` | 5,924 (5,923 registered + unknown member) | `select distinct customer_id, customer_type, customer_segment` where `customer_id is not null`, left joined to the censoring lookup for `first_purchase_date`/`is_censored` |
| `dim.product` | 4,751 (4,750 products + unknown member) | `select distinct description, stock_code, is_non_product_code` where `stock_code is not null` |
| `dim.country` | 44 (43 countries + unknown member) | `select distinct country_name` from the clean table |
| `dim.date` | 739 | Recursive CTE generating every calendar day between `min(invoicedate)` and `max(invoicedate)` — guarantees no gaps in the reporting calendar, independent of which days actually had sales |

## Fact Table Population

```sql
insert into fact.sales (
    customer_key, product_key, date_key, country_key,
    invoice, quantity, price, sales_amount,
    price_flag, outliers_in_qnt, transaction_type
)
select
    isnull(cust.customer_surrogate_key, -1),
    isnull(pr.product_surrogate_key, -1),
    convert(int, convert(char(8), cl.InvoiceDate, 112)),
    isnull(co.country_surrogate_key, -1),
    cl.Invoice,
    cl.Quantity,
    cast(cl.Price as decimal(18, 4)),
    cl.Quantity * cast(cl.Price as decimal(18, 4)),
    cl.PriceFlag,
    cl.OutliersInQnt,
    cl.TransactionType
from dbo.online_retail_II_clean cl
left join dim.customer cust on cust.customer_id = cl.Customer_ID
left join dim.product pr    on pr.stock_code = cl.StockCode
left join dim.country co    on co.country_name = cl.Country;
```
- `left join` (not `inner join`) on every dimension, so unmatched source rows still make it into the fact table
- `isnull(..., -1)` routes any unmatched row to the Unknown member instead of dropping it or failing
- Joins are now on natural keys alone (`stock_code`, `customer_id`, `country_name`), not the compound `(stock_code, description)` / `(country, customer_id)` joins from the first build — each of those columns is already declared `unique` in its dimension, so the compound join was unnecessary
- The date key is built with `convert(char(8), ..., 112)` rather than `format(..., 'yyyyMMdd')` — materially faster over 1M+ rows
- **1,026,237 rows affected**

## Performance

```sql
create clustered columnstore index cci_fact_sales
on fact.sales;
```
Applied after the fact table was fully loaded. Chosen because reporting queries against `fact.sales` are aggregation-heavy (`SUM`/`AVG`/`COUNT` grouped by dimension attributes) rather than row-level lookups — columnstore compresses better and reads only the columns a query touches, and enables batch-mode execution for aggregates.

## Validation

### Row count check
| Table | Row count |
|---|---|
| `dbo.online_retail_II_clean` (source) | 1,026,237 |
| `fact.sales` | 1,026,237 |

Match confirmed — no rows lost or duplicated during load.

### Orphan checks (all must return 0)
| Dimension | Orphan count | Verdict |
|---|---|---|
| `dim.customer` | 0 | PASS |
| `dim.product` | 0 | PASS |
| `dim.date` | 0 | PASS |
| `dim.country` | 0 | PASS |

### Unknown member counts
| Check | Count | Verdict |
|---|---|---|
| `fact.sales` rows with `customer_key = -1` | 228,452 | PASS — matches `online_retail_II_clean`'s null-`Customer_ID` count exactly |
| `fact.sales` rows with `product_key = -1` | 0 | PASS — the `stock_code` join to `dim.product` is fully reliable |
| `fact.sales` rows with `country_key = -1` | 0 | PASS — every row's Country matched a `dim.country` entry |

### Valid-sales reconciliation
`fact.sales` keeps every transaction type (Sale, Cancellation, Stock Adjustment); `dbo.online_retail_II_fact` is the Sale-only subset built by the cleaning script. The two must agree when `fact.sales` is filtered the same way:

| Check | `dbo.online_retail_II_fact` | `fact.sales` filtered to Sale + product + Price > 0 |
|---|---|---|
| Row count | 1,003,352 | 1,003,352 |
| Revenue | £19,643,192.86 | £19,643,192.86 |

### Grain check
11,144 `(invoice, product_key)` pairs appear on more than one line — confirms the grain is "one invoice line item," not "one product per invoice." Revenue totals are unaffected either way; only `COUNT(*)` as a stand-in for order count would be.

### Partial month check
```sql
select min(full_date), max(full_date), count(*) from dim.date where is_partial_month = 1;
```
Returns exactly 9 rows, 2011-12-01 to 2011-12-09 — matches the dataset's actual last 9 days.

### Spot check
Full join of `fact.sales` to all four dimensions (`dim.date`, `dim.product`, `dim.customer`, `dim.country`) run to visually confirm values line up correctly across the star.

### Business query test
```sql
select
    dd.year Yr,
    pr.description ProductName,
    sum(fs.sales_amount) TotalSales
from fact.sales fs
inner join dim.date dd
    on fs.date_key = dd.date_surrogate_key
inner join dim.product pr
    on fs.product_key = pr.product_surrogate_key
group by
    dd.year,
    pr.description;
```
Confirms the schema supports a typical "total sales by year and product" reporting query end to end.

## Data Dictionary (key columns)

| Table | Column | Type | Description |
|---|---|---|---|
| `dim.customer` | `customer_surrogate_key` | int | Internal PK; `-1` = unknown/unmatched customer |
| `dim.customer` | `customer_id` | int, nullable | Natural key from source; `NULL` for the unknown member |
| `dim.customer` | `first_purchase_date` | date, nullable | Earliest Sale date; `NULL` for guests and customers with no Sale row |
| `dim.customer` | `is_censored` | bit, nullable | `NULL` for guests and customers with no Sale row |
| `dim.product` | `product_surrogate_key` | int | Internal PK; `-1` = unknown/unmatched product |
| `dim.product` | `stock_code` | varchar(20) | Natural key from source |
| `dim.country` | `country_surrogate_key` | int | Internal PK; `-1` = unknown/unmatched country |
| `dim.country` | `country_name` | varchar(50) | Natural key from source |
| `dim.date` | `date_surrogate_key` | int | `yyyyMMdd` integer, also serves as the natural/business key |
| `fact.sales` | `sales_surrogate_key` | bigint | Internal PK; `nonclustered` to leave room for the columnstore index |
| `fact.sales` | `invoice` | varchar(20) | Degenerate dimension — invoice number kept on the fact row, no separate dimension table |
| `fact.sales` | `sales_amount` | decimal(18,4) | `quantity * price`, calculated at load time (not stored in source) |
| `fact.sales` | `customer_key` / `product_key` / `date_key` / `country_key` | int | FKs to each dimension; `-1` where source data was missing or unmatched |

## Source-to-Target Mapping (fact table)

| Source column (`online_retail_II_clean`) | Target column (`fact.sales`) | Transformation |
|---|---|---|
| `Invoice` | `invoice` | Direct copy |
| `InvoiceDate` | `date_key` | `convert(char(8), ..., 112)` → int, looked up against `dim.date` |
| `Customer_ID` | `customer_key` | Looked up via `dim.customer` on `customer_id`; `-1` if unmatched |
| `StockCode` | `product_key` | Looked up via `dim.product` on `stock_code`; `-1` if unmatched |
| `Country` | `country_key` | Looked up via `dim.country` on `country_name`; `-1` if unmatched |
| `Quantity` | `quantity` | Direct copy |
| `Price` | `price` | Cast to `decimal(18,4)` |
| `Quantity`, `Price` | `sales_amount` | `Quantity * Price`, calculated at full precision |
| `PriceFlag` | `price_flag` | Direct copy |
| `OutliersInQnt` | `outliers_in_qnt` | Direct copy |
| `TransactionType` | `transaction_type` | Direct copy |
| `IsCensored`, first Sale date | `dim.customer.is_censored`, `dim.customer.first_purchase_date` | Computed once per customer via the censoring lookup, not copied onto every fact row |

## Maintenance

- **Load strategy: full refresh.** The source is a static historical extract, not a live feed, so the schema is rebuilt and reloaded from scratch each run rather than incrementally.

## Lessons / Notes for Future Reference

- **Mistake — `dim.customer.customer_id` too restrictive**: originally created `not null`, but the unknown member requires `customer_id = NULL`. Fixed with `alter table dim.customer alter column customer_id int null;` before inserting the unknown row.
- **Mistake — `dim.product.description` too short**: originally `varchar(20)`, too small for real descriptions (`Msg 2628`, truncation on load). Fixed with `alter table dim.product alter column description varchar(100);` before populating.
- **Mistake — fact insert column/select order mismatch**: an early version of the `fact.sales` insert listed `select` columns in a different order than the `insert into (...)` column list. SQL Server matches purely by position, not name, so several columns silently landed in the wrong place — only surfaced when a text value (`PriceFlag = 'Normal'`) hit an `int` column and threw a conversion error. Fixed by reordering the `select` list to match the `insert` list exactly.
- **Mistake — `sales_amount` omitted entirely**: the fact table's `sales_amount` is `not null` with no default, but an early insert didn't include it at all, so SQL Server tried (and failed) to insert `NULL`. Fixed by adding `cl.Quantity * cl.Price` to both the column list and the select.
- **Mistake — country could only live on `dim.customer`**: guest transactions have no `Customer_ID`, so they had no way to carry a country, and fell back to the Unknown member's country — silently dropping ~22% of rows, mostly UK, from any country-level report. Splitting country into its own `dim.country`, looked up independently per fact row, fixed this without changing the grain.
- **Mistake — `price` column too imprecise**: `decimal(10,2)` silently re-rounded the cleaning script's 3-decimal prices, so `price` and `sales_amount` could disagree at the sub-penny level across a million rows. Widened to `decimal(18,4)`.
- **Table design intentionally anticipates the columnstore index**: declaring the fact table's PK as `primary key nonclustered` up front avoids having to drop and recreate it later, since a table can only have one clustered index and the columnstore index needs that slot.
- **Unknown members must be validated, not just assumed**: comparing `fact.sales` rows with `customer_key = -1` against the actual null-`Customer_ID` count in the clean table (rather than just checking the orphan count is 0) confirmed the unknown-member logic was catching *exactly* the missing-data cases and nothing else — a stronger check than the orphan test alone. The same check was extended to `country_key = -1` for this rebuild.
