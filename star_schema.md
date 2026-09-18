# Star Schema Build

## Overview
- Source table: `dbo.online_retail_II_clean` (cleaned working table, see Data Cleaning doc)
- Target database: `OnlineRetailII`
- Schemas: `dim` (dimension tables), `fact` (fact table)
- Tool: SQL Server (T-SQL)
- Methodology: Kimball 4-step dimensional design (business process → grain → dimensions → facts)
- Purpose: Transform the cleaned, row-level transaction table into a queryable star schema for reporting and analysis
- Source (clean table) row count: 1,023,381
- Fact table row count: 1,023,381

## Dimensional Design (Kimball 4-Step Process)

### Step 1 — Business process
Sales transactions, recorded through invoices.

### Step 2 — Grain
**One row in the fact table = one product line per one invoice.**
Never mixed with a coarser grain (e.g. one row per invoice) or a finer one (e.g. one row per unit).

### Step 3 — Dimensions
| Dimension | Attributes |
|---|---|
| `dim.customer` | Customer_ID, Country, CustomerType, CustomerSegment |
| `dim.product` | Description, StockCode, IsNonProductCode |
| `dim.date` | FullDate, Day, Month, MonthName, Quarter, Year, DayOfWeek, IsWeekend, IsPartialMonth |

`Invoice` is a **degenerate dimension** — no descriptive attributes of its own, so it stays on the fact table rather than becoming a separate dimension table.

### Step 4 — Facts (measures)
| Measure | Additive? |
|---|---|
| `Quantity` | Additive (summable, averageable) |
| `Price` | Additive |
| `SalesAmount` (`Quantity * Price`) | Additive |
| `Invoice` | Not a measure — degenerate dimension, retained for grain/traceability |

## Physical Structure

### Schemas
```sql
if not exists (select 1 from sys.schemas where name = 'fact') exec('create schema fact');
if not exists (select 1 from sys.schemas where name = 'dim') exec('create schema dim');
```

### Table design decisions
- [x] Surrogate keys for every dimension: `int identity(1,1)` for `customer`/`product`; `date_surrogate_key` uses a `yyyyMMdd` int instead, since it's naturally unique and human-readable
- [x] Natural keys retained alongside surrogate keys: `customer_id`, `stock_code`, `full_date`
- [x] Money columns (`price`, `sales_amount`) use `decimal`, never `float`
- [x] Unknown members (key = `-1`) planned for `dim.customer` and `dim.product`; `dim.date` does not need one (dates are never missing/unmatched by construction)

### Dimension tables
```sql
create table dim.customer (
	customer_surrogate_key		int identity(1, 1) primary key,
	customer_id					int null,
	country						varchar(20),
	customer_type				varchar(20),
	customer_segment			varchar(20)
);

create table dim.product (
	product_surrogate_key		int identity(1, 1) primary key,
	description					varchar(50),
	stock_code					varchar(20) not null,
	is_non_product_code			bit
);

create table dim.date (
	date_surrogate_key			int primary key,
	full_date					date not null,
	day_of_week					varchar(10),
	is_weekend					bit,
	is_partial_month			bit not null
);
```

### Fact table
```sql
create table fact.sales (
	sales_surrogate_key			bigint identity(1,1) primary key nonclustered,
	customer_key				int not null,
	product_key					int not null,
	date_key					int not null,
	invoice						varchar(20) not null,
	quantity					int not null,
	price						decimal (10,2),
	sales_amount				decimal(18,4) not null,
	price_flag					varchar(20),
	outliers_in_qnt				varchar(20),
	is_censored					bit,
	transaction_type			varchar(20)
);
```
`sales_surrogate_key` is declared `nonclustered` on purpose — leaves the clustered slot free for a clustered columnstore index (Phase 6).

### Constraints
```sql
-- Foreign keys
alter table fact.sales
	add
	constraint fk_sales_customer foreign key (customer_key) references dim.customer(customer_surrogate_key),
	constraint fk_sales_product foreign key (product_key) references dim.product(product_surrogate_key),
	constraint fk_sales_date foreign key (date_key) references dim.date(date_surrogate_key);

-- Unique constraints on natural keys (data quality + lookup speed)
alter table dim.customer add constraint uniq_customer_id unique (customer_id);
alter table dim.product add constraint uniq_product_id unique (stock_code);
```

## Entity-Relationship Diagram

The star shape: `sales (fact)` sits at the center, with `date (dim)`, `customer (dim)`, and `product (dim)` each connected via a single FK relationship — one-to-many from each dimension into the fact table.

<img width="1405" height="812" alt="Star Schema Diagram (End-To-End Online Retail Analysis)" src="https://github.com/user-attachments/assets/188e97d4-e9e4-4109-9f7e-fc7e92d030d6" />

## Unknown Members

| Dimension | Surrogate key | Natural key | Descriptive attributes |
|---|---|---|---|
| `dim.customer` | -1 | `NULL` | Country/Type/Segment = `'unknown'` |
| `dim.product` | -1 | `'unknown'` | Description = `'unknown'`, IsNonProductCode = 0 |

Inserted via `set identity_insert ... on/off` so the surrogate key `-1` could be forced in despite the `identity` column.

## Dimension Population

| Dimension | Rows loaded | Method |
|---|---|---|
| `dim.customer` | 5,299 | `select distinct customer_id, country, customer_type, customer_segment` where `customer_id is not null` |
| `dim.product` | 4,733 | `select distinct description, stock_code, is_non_product_code` where `stock_code is not null` |
| `dim.date` | 739 | Recursive CTE generating every calendar day between `min(invoicedate)` and `max(invoicedate)` — guarantees no gaps in the reporting calendar, independent of which days actually had sales |

## Fact Table Population

```sql
insert into fact.sales (
	invoice, date_key, customer_key, product_key,
	quantity, price, sales_amount, price_flag,
	outliers_in_qnt, transaction_type, is_censored
)
select
	cl.Invoice,
	cast(format(cl.invoicedate, 'yyyyMMdd') as int),
	isnull(cust.customer_surrogate_key, -1),
	isnull(pr.product_surrogate_key, -1),
	cl.Quantity,
	cl.Price,
	cl.Quantity * cl.Price,
	cl.PriceFlag,
	cl.OutliersInQnt,
	cl.TransactionType,
	isnull(cl.IsCensored, 0)
from dbo.online_retail_II_clean cl
left join dim.product pr
	on (pr.stock_code = cl.StockCode) and (pr.description = cl.Description)
left join dim.customer cust
	on (cust.country = cl.Country) and (cust.customer_id = cl.Customer_ID);
```
- `left join` (not `inner join`) on both dimensions, so unmatched source rows still make it into the fact table
- `isnull(..., -1)` routes any unmatched row to the Unknown member instead of dropping it or failing
- **1,023,381 rows affected**

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
| `dbo.online_retail_II_clean` (source) | 1,023,381 |
| `fact.sales` | 1,023,381 |

Match confirmed — no rows lost or duplicated during load.

### Orphan checks (all must return 0)
| Dimension | Orphan count | Verdict |
|---|---|---|
| `dim.customer` | 0 | PASS |
| `dim.product` | 0 | PASS |
| `dim.date` | 0 | PASS |

### Unknown member counts
| Check | Count | Verdict |
|---|---|---|
| `fact.sales` rows with `customer_key = -1` | ~250,000 | PASS — matches `online_retail_II_clean` null-`Customer_ID` count exactly; confirms every unknown-customer row traces back to a genuinely missing source ID, with no join leakage |
| `fact.sales` rows with `product_key = -1` | 0 | PASS — confirms the `(stock_code, description)` join to `dim.product` is fully reliable |

### Spot check
Full join of `fact.sales` to all three dimensions (`dim.date`, `dim.product`, `dim.customer`) run to visually confirm values line up correctly across the star.

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
| `dim.product` | `product_surrogate_key` | int | Internal PK; `-1` = unknown/unmatched product |
| `dim.product` | `stock_code` | varchar(20) | Natural key from source |
| `dim.date` | `date_surrogate_key` | int | `yyyyMMdd` integer, also serves as the natural/business key |
| `fact.sales` | `sales_surrogate_key` | bigint | Internal PK; `nonclustered` to leave room for the columnstore index |
| `fact.sales` | `invoice` | varchar(20) | Degenerate dimension — invoice number kept on the fact row, no separate dimension table |
| `fact.sales` | `sales_amount` | decimal(18,4) | `quantity * price`, calculated at load time (not stored in source) |
| `fact.sales` | `customer_key` / `product_key` / `date_key` | int | FKs to each dimension; `-1` where source data was missing or unmatched |

## Source-to-Target Mapping (fact table)

| Source column (`online_retail_II_clean`) | Target column (`fact.sales`) | Transformation |
|---|---|---|
| `Invoice` | `invoice` | Direct copy |
| `InvoiceDate` | `date_key` | `format(..., 'yyyyMMdd')` → int, looked up against `dim.date` |
| `Customer_ID`, `Country` | `customer_key` | Looked up via `dim.customer` on `(country, customer_id)`; `-1` if unmatched |
| `StockCode`, `Description` | `product_key` | Looked up via `dim.product` on `(stock_code, description)`; `-1` if unmatched |
| `Quantity` | `quantity` | Direct copy |
| `Price` | `price` | Direct copy |
| `Quantity`, `Price` | `sales_amount` | `Quantity * Price`, calculated |
| `PriceFlag` | `price_flag` | Direct copy |
| `OutliersInQnt` | `outliers_in_qnt` | Direct copy |
| `TransactionType` | `transaction_type` | Direct copy |
| `IsCensored` | `is_censored` | `isnull(..., 0)` |

## Maintenance

- **Load strategy: full refresh.** The source is a static historical extract, not a live feed, so the schema is rebuilt and reloaded from scratch each run rather than incrementally.

## Lessons / Notes for Future Reference

- **Mistake — `dim.customer.customer_id` too restrictive**: originally created `not null`, but the unknown member requires `customer_id = NULL`. Fixed with `alter table dim.customer alter column customer_id int null;` before inserting the unknown row.
- **Mistake — `dim.product.description` too short**: originally `varchar(20)`, too small for real descriptions (`Msg 2628`, truncation on load). Fixed with `alter table dim.product alter column description varchar(50);` before populating.
- **Mistake — fact insert column/select order mismatch**: an early version of the `fact.sales` insert listed `select` columns in a different order than the `insert into (...)` column list. SQL Server matches purely by position, not name, so several columns silently landed in the wrong place — only surfaced when a text value (`PriceFlag = 'Normal'`) hit an `int` column and threw a conversion error. Fixed by reordering the `select` list to match the `insert` list exactly.
- **Mistake — `sales_amount` omitted entirely**: the fact table's `sales_amount` is `not null` with no default, but an early insert didn't include it at all, so SQL Server tried (and failed) to insert `NULL`. Fixed by adding `cl.Quantity * cl.Price` to both the column list and the select.
- **Table design intentionally anticipates the columnstore index**: declaring the fact table's PK as `primary key nonclustered` up front avoids having to drop and recreate it later, since a table can only have one clustered index and the columnstore index needs that slot.
- **Unknown members must be validated, not just assumed**: comparing `fact.sales` rows with `customer_key = -1` against the actual null-`Customer_ID` count in the clean table (rather than just checking the orphan count is 0) confirmed the unknown-member logic was catching *exactly* the missing-data cases and nothing else — a stronger check than the orphan test alone.
