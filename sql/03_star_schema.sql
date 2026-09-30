-- ============================================================
-- Online Retail II Star Schema Build
-- ============================================================

-- ============================================================
-- COMPLETE STEP-BY-STEP GUIDE: Designing & Building a Star Schema in SQL Server
-- Combined from Kimball methodology + practical SQL Server / Power BI best practices
-- Use this as a checklist. Turn each step into actual code only after you understand it.
-- ============================================================

-- ============================================================
-- PHASE 0: PREPARATION
-- ============================================================
-- 0.1  Understand the business process you are modeling
-- 0.2  Gather business requirements (what questions will users ask?)
-- 0.3  Examine the source data (columns, data types, quality, volume)
-- 0.4  Confirm you have a cleaned source table ready (e.g. dbo.online_retail_ii_clean)
-- 0.5  Decide the target database and create it if it does not exist
-- 0.6  Open SQL Server Management Studio (SSMS) and connect to the server


-- ANSWER --
-- The business process is recording transaction orders through invoices


-- ============================================================
-- PHASE 1: DIMENSIONAL DESIGN (Kimball 4-Step Process) – DO THIS ON PAPER FIRST
-- ============================================================

-- Step 1: Select the business process
--        Example: “Sales transactions” or “Invoice line items”
-- ANSWER --
-- Sales transaction 


-- Step 2: Declare the grain (MOST IMPORTANT STEP)
--        Write one clear sentence: “One row in the fact table = one product line on one invoice”
--        Never mix different grains in the same fact table
-- ANSWER --
-- One row in the fact table = one product line per one invoice


-- Step 3: Identify the dimensions
--        Ask: Who? What? Where? When? Why? How?
--        Typical dimensions: Customer, Product, Date, (sometimes Store, Promotion, etc.)
--        List every descriptive attribute that belongs to each dimension
-- ANSWER --
-- Dim_Customer = Customer_ID, Country, CustomerType, CustomerSegment
-- Dim_Product = Description, StockCode, IsNonProductCode
-- Dim_Date = InvoiceDate, IsPartialMonth
-- Fact table ==> Fact_Sales = Customer_Key, Product_Key, Date_Key, Invoice, Quantity, Price, PriceFlag, OutliersInQnt, 
-- IsCensored, TransactionType
-- Invoice is a degenerate dimension, while quanity and price are measures, and the rest are events the transaction, NOT THE PRODUCT
-- One row describes one product line/distinct product per one transaction. Meaning, that transaction is performed by the invoicing, and the 
-- product is the what.


-- Step 4: Identify the facts (measures)
--        Ask: What can be summed, counted, or averaged?
--        Examples: Quantity, Unit Price, Sales Amount, Discount, etc.
--        Decide which measures are additive, semi-additive, or non-additive
-- ANSWER --
-- Invoice, because it records an event/transaction
-- Quantity, because it can be summed, avg, etc.
-- Price, because it can be summed, avg, etc.
-- Quantity and price are additive, while Invoice is a degenerate dimension, thus it remains in the fact tabl


-- Extra design decisions (still on paper):

-- 4.1  Choose surrogate keys for every dimension (int IDENTITY)
-- ANSWER --
-- Dim_Customer  → CustomerKey    int IDENTITY(1,1)   (surrogate)
-- Dim_Product   → ProductKey     int IDENTITY(1,1)   (surrogate)
-- Dim_Date      → DateKey        int                 (yyyyMMdd style, acts as surrogate)


-- 4.2  Decide natural / business keys (StockCode, CustomerID, etc.)
-- ANSWER --
-- Dim_Customer  → Customer_ID     (natural key)
-- Dim_Product   → StockCode       (natural key)
-- Dim_Date      → FullDate        (natural key)


-- 4.3  Plan “Unknown” members (key = -1) for missing values
-- ANSWER --
-- Dim_Customer  → CustomerKey = -1, Customer_ID = NULL, Country = 'Unknown', etc.
-- Dim_Product   → ProductKey  = -1, StockCode = 'Unknown', Description = 'Unknown Product'
-- (Dim_Date usually does not need an Unknown member)
-- Use unknowns whenever there is a chance of missing or unmatched data


-- 4.4  Decide degenerate dimensions (e.g. Invoice number stays on the fact table)
-- ANSWER --
-- Invoice ==> stays on the fact table (degenerate dimension), because there are no descriptive attributes about it that need to split into a different table


-- 4.5  Design the Date dimension attributes
-- ANSWER --
-- DateKey, FullDate, Day, Month, MonthName, Quarter, Year,
-- DayOfWeek, IsWeekend, IsPartialMonth


-- 4.6  Decide data types (especially decimal for money, never float)
-- ANSWER --
-- Quantity        → int or bigint
-- Price           → decimal(18,4)          -- never float
-- SalesAmount     → decimal(18,4)          -- optional calculated measure
-- All Keys        → int
-- Invoice         → nvarchar(20) or varchar(20)
-- Flags           → nvarchar(20) or bit (depending on the column)


-- 4.7  Sketch the star on paper or in a diagram tool:
--      Dim_Customer ──┐
--      Dim_Product  ──┼── Fact_Sales
--      Dim_Date     ──┘


-- ============================================================
-- PHASE 2: CREATE THE PHYSICAL STRUCTURE IN SQL SERVER
-- ============================================================

use OnlineRetailII;
go
 
-- Schemas
if not exists (select 1 from sys.schemas where name = 'fact') exec('create schema fact');
if not exists (select 1 from sys.schemas where name = 'dim') exec('create schema dim');
go
 
-- Drop (fact first, because of the foreign keys)
drop table if exists fact.sales;
drop table if exists dim.customer;
drop table if exists dim.product;
drop table if exists dim.date;
drop table if exists dim.country;
go

-- Checking the tables in the db
select 
	TABLE_SCHEMA, 
	TABLE_NAME
from INFORMATION_SCHEMA.TABLES
where TABLE_TYPE = 'BASE TABLE'
order by 
	TABLE_SCHEMA, 
	TABLE_NAME;


-- 2.2  Create Dimension tables (empty)
--      - Surrogate key as PRIMARY KEY (int IDENTITY(1,1))
--      - Natural key column(s)
--      - All descriptive attributes
--      - Optional: audit columns (InsertDate, UpdateDate)

-- Creating the dim.country dimension table
create table dim.country (
    country_surrogate_key   int identity(1, 1) primary key,
    country_name            varchar(50) not null,
    constraint uniq_country_name unique (country_name)
);

-- Check if the table is created successfully
select COLUMN_NAME
from INFORMATION_SCHEMA.COLUMNS
where TABLE_SCHEMA = 'dim'
	and TABLE_NAME = 'country';


-- Creating the dim.customer dimension table
create table dim.customer (
    customer_surrogate_key  int identity(1, 1) primary key,
    customer_id             int null,
    customer_type           varchar(20),
    customer_segment        varchar(20),
    first_purchase_date     date null,
    is_censored             bit null,
    constraint uniq_customer_id unique (customer_id)
);

-- Check if the table is created successfully
select COLUMN_NAME
from INFORMATION_SCHEMA.COLUMNS
where TABLE_SCHEMA = 'dim'
	and TABLE_NAME = 'customer';


-- Creating the dim.product dimension table
create table dim.product (
    product_surrogate_key   int identity(1, 1) primary key,
    description             varchar(100),
    stock_code              varchar(20) not null,
    is_non_product_code     bit,
    constraint uniq_product_stock_code unique (stock_code)
);

-- Check if the table is created successfully
select COLUMN_NAME
from INFORMATION_SCHEMA.COLUMNS
where TABLE_SCHEMA = 'dim'
	and TABLE_NAME = 'product';


-- Creating the dim.date dimension table
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

-- Check if the table is created successfully
select COLUMN_NAME
from INFORMATION_SCHEMA.COLUMNS
where TABLE_SCHEMA = 'dim'
	and TABLE_NAME = 'date';


-- 2.3  Create the Fact table (empty)
--      - Surrogate key (bigint IDENTITY)
--      - Foreign keys to every dimension (int, NOT NULL)
--      - Degenerate dimension columns (Invoice, etc.)
--      - All measure columns with correct data types
--      - Optional: audit columns
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
go

-- Check if the table is created successfully
select COLUMN_NAME
from INFORMATION_SCHEMA.COLUMNS
where TABLE_SCHEMA = 'fact'
	and TABLE_NAME = 'sales';


-- ============================================================
-- PHASE 3: ADD UNKNOWN MEMBERS
-- ============================================================

set identity_insert dim.country on;
insert into dim.country (country_surrogate_key, country_name)
values (-1, 'Unknown');
set identity_insert dim.country off;
 
-- Every row that maps to -1 is a guest (null Customer_ID)
set identity_insert dim.customer on;
insert into dim.customer (customer_surrogate_key, customer_id, customer_type, customer_segment, first_purchase_date, is_censored)
values (-1, null, 'Guest/Unregistered', 'N/A', null, null);
set identity_insert dim.customer off;
 
set identity_insert dim.product on;
insert into dim.product (product_surrogate_key, description, stock_code, is_non_product_code)
values (-1, 'Unknown Product', 'UNKNOWN', 0);
set identity_insert dim.product off;

-- ============================================================
-- PHASE 4: POPULATE THE DIMENSIONS
-- ============================================================

-- dim.country
insert into dim.country (country_name)
select distinct Country
from dbo.online_retail_II_clean
where Country is not null;
 
-- dim.customer (registered customers; censoring comes from the lookup)
insert into dim.customer (customer_id, customer_type, customer_segment, first_purchase_date, is_censored)
select
    c.Customer_ID,
    c.CustomerType,
    c.CustomerSegment,
    cast(l.first_purchase_date as date),
    l.IsCensored
from (
    select distinct Customer_ID, CustomerType, CustomerSegment
    from dbo.online_retail_II_clean
    where Customer_ID is not null
) c
left join dbo.customer_censoring_lookup l
    on l.Customer_ID = c.Customer_ID;
 
-- dim.product
insert into dim.product (description, stock_code, is_non_product_code)
select distinct Description, StockCode, IsNonProductCode
from dbo.online_retail_II_clean
where StockCode is not null;
 
-- dim.date (one row per calendar day between the first and last invoice date)
declare @startdate date, @enddate date;
select @startdate = cast(min(InvoiceDate) as date),
       @enddate   = cast(max(InvoiceDate) as date)
from dbo.online_retail_II_clean;
 
with date_sequence as (
    select @startdate as full_date
    union all
    select dateadd(day, 1, full_date)
    from date_sequence
    where full_date < @enddate
)
insert into dim.date (
    date_surrogate_key, full_date, year, quarter, month, month_name, year_month,
    day_of_week_number, day_of_week, is_weekend, is_partial_month
)
select
    convert(int, convert(char(8), full_date, 112)),
    full_date,
    year(full_date),
    datepart(quarter, full_date),
    month(full_date),
    datename(month, full_date),
    convert(char(7), full_date, 120),
    (datediff(day, '19000101', full_date) % 7) + 1,
    datename(weekday, full_date),
    case when (datediff(day, '19000101', full_date) % 7) + 1 in (6, 7) then 1 else 0 end,
    -- the month that contains the last invoice date is partial if it ends later
    case when year(full_date) = year(@enddate)
          and month(full_date) = month(@enddate)
          and @enddate < eomonth(@enddate) then 1 else 0 end
from date_sequence
option (maxrecursion 0);
go

-- ============================================================
-- PHASE 5: POPULATE THE FACT TABLE
-- ============================================================

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
go
 
-- Columnstore index (after the load)
create clustered columnstore index cci_fact_sales
on fact.sales;
go

-- ============================================================
-- PHASE 7: VALIDATION (NEVER SKIP)
-- ============================================================

-- V1. Row counts (must be identical)
select
    (select count(*) from dbo.online_retail_II_clean) as clean_rows,
    (select count(*) from fact.sales) as fact_rows;
 
-- V2. Orphans (all four must be 0)
select
    (select count(*) from fact.sales f left join dim.customer d on d.customer_surrogate_key = f.customer_key where d.customer_surrogate_key is null) as customer_orphans,
    (select count(*) from fact.sales f left join dim.product d  on d.product_surrogate_key  = f.product_key  where d.product_surrogate_key  is null) as product_orphans,
    (select count(*) from fact.sales f left join dim.date d     on d.date_surrogate_key     = f.date_key     where d.date_surrogate_key     is null) as date_orphans,
    (select count(*) from fact.sales f left join dim.country d  on d.country_surrogate_key  = f.country_key  where d.country_surrogate_key  is null) as country_orphans;
 
-- V3. Unknown members
-- expect: unknown_customer_rows = null_customer_rows_in_clean; the other two = 0
select
    (select count(*) from fact.sales where customer_key = -1) as unknown_customer_rows,
    (select count(*) from dbo.online_retail_II_clean where Customer_ID is null) as null_customer_rows_in_clean,
    (select count(*) from fact.sales where product_key = -1) as unknown_product_rows,
    (select count(*) from fact.sales where country_key = -1) as unknown_country_rows;
 
-- V4. Valid-sales reconciliation against dbo.online_retail_II_fact
-- expect: subset_rows = star_valid_sale_rows, subset_revenue = star_valid_sale_revenue
select
    (select count(*) from dbo.online_retail_II_fact) as subset_rows,
    (select count(*)
       from fact.sales s
       join dim.product p on p.product_surrogate_key = s.product_key
      where s.transaction_type = 'Sale' and p.is_non_product_code = 0 and s.price > 0) as star_valid_sale_rows,
    (select round(sum(Quantity * Price), 2) from dbo.online_retail_II_fact) as subset_revenue,
    (select round(sum(s.sales_amount), 2)
       from fact.sales s
       join dim.product p on p.product_surrogate_key = s.product_key
      where s.transaction_type = 'Sale' and p.is_non_product_code = 0 and s.price > 0) as star_valid_sale_revenue;
 
-- V5. Rows and revenue by transaction type
select transaction_type, count(*) as row_count, sum(sales_amount) as revenue
from fact.sales
group by transaction_type;
 
-- V6. Grain check: invoice/product pairs that appear on more than one line
-- (informational; revenue is unaffected, but count orders with COUNT(DISTINCT invoice))
select count(*) as repeated_invoice_product_pairs
from (
    select invoice, product_key
    from fact.sales
    group by invoice, product_key
    having count(*) > 1
) x;
 
-- V7. Partial month (expect exactly 9 rows: 2011-12-01 to 2011-12-09)
select min(full_date) as first_partial_day, max(full_date) as last_partial_day, count(*) as partial_days
from dim.date
where is_partial_month = 1;
 
-- V8. Price precision and flag consistency (expect 0)
select count(*) as price_flag_mismatches
from fact.sales
where (price <= 0 and price_flag = 'Normal')
   or (price > 0  and price_flag <> 'Normal');
 
-- V9. Customers by segment and censoring (NULL censoring = no Sale row, or guest)
select customer_segment, is_censored, count(*) as customers
from dim.customer
group by customer_segment, is_censored
order by customer_segment, is_censored;

-- ============================================================
-- PHASE 8: DOCUMENTATION & MAINTENANCE
-- ============================================================

-- 8.1  Document the grain in a comment or wiki
-- 8.2  Document source-to-target mapping
-- 8.3  Save the final CREATE and load scripts
-- 8.4  Create a simple data dictionary (column descriptions)
-- 8.5  Decide how future loads will work (full refresh vs incremental)
