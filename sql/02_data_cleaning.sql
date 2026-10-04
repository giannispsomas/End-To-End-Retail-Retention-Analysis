/*
================================================================================
END-TO-END RETAIL RETENTION ANALYSIS - DATA CLEANING
================================================================================
Purpose   : Turn the raw table dbo.online_retail_II into an analysis-ready
            dataset. The raw table is never modified: all work happens on a copy.

Structure : PART 1  Setup                          step 0
            PART 2  Remove noise, fix values       steps 1-12
            PART 3  Flag and classify              steps 13-20
            PART 4  Build the fact subset          step 21
            PART 5  Validation                     checks V1-V9

Tables created
    dbo.online_retail_II_clean          full cleaned + flagged dataset
                                        (the source of the star schema)
    dbo.online_retail_II_fact           valid-sales subset, used to cross-check
                                        the star schema
    dbo.stockcode_description_lookup    StockCode   -> canonical Description
    dbo.customer_country_lookup         Customer_ID -> resolved Country
    dbo.invoice_date_lookup             Invoice     -> earliest InvoiceDate
    dbo.customer_segmentation_lookup    Customer_ID -> Wholesale / Retail
    dbo.customer_censoring_lookup       Customer_ID -> first purchase, IsCensored

Columns added to dbo.online_retail_II_clean (in step order)
    IsNonProductCode, CustomerType, PriceFlag, OutliersInQnt, IsPartialMonth,
    TransactionType, CustomerSegment, IsCensored

Design rules
    1. Delete a row only when it is meaningless noise (no description, junk
       text, exact duplicate). Flag it when it still records a real business
       event (guest sales, cancellations, postage, fees).
    2. Every step that overwrites a column used to detect duplicates
       (Description, StockCode, Country, Price, InvoiceDate) comes BEFORE the second
       duplicate pass (step 12). Flags and classifications come after it, so
       they are computed on final values.
    3. Every lookup follows one pattern: rank the candidate values, keep the
       top one per entity, save it as a small answer-key table, apply it with
       UPDATE ... JOIN, then verify that no conflicts remain.
    4. Every step ends with a check: a labelled row count, or a count that
       must be 0.

How to run
    Run the whole script once, top to bottom, with nothing selected (F5).
    The reset block drops and rebuilds everything the script creates, so it
    can be re-run at any time. The lines that contain only the word GO split
    the script into batches: a column added by ALTER TABLE has to exist before
    the statements that use it are compiled. Do not remove them.
    If any red error text appears on the Messages tab, stop and read it before
    running anything else.
================================================================================
*/

use OnlineRetailII;
go


/*
================================================================================
PART 1 - SETUP
================================================================================
*/

-- RESET: drop everything this script creates. The raw table is never dropped.
drop table if exists dbo.online_retail_II_fact;
drop table if exists dbo.online_retail_II_clean;
drop table if exists dbo.stockcode_description_lookup;
drop table if exists dbo.customer_country_lookup;
drop table if exists dbo.invoice_date_lookup;
drop table if exists dbo.customer_segmentation_lookup;
drop table if exists dbo.customer_censoring_lookup;

-- Rows deleted by the latest DELETE. Reused by the removal steps (1-4 and 12)
-- to print a row-count log.
declare @removed int;

--------------------------------------------------------------------------------
-- STEP 00 | Copy the raw table                                        (SETUP)
--------------------------------------------------------------------------------
-- WHY     : the raw table stays the source of truth. Any step can be redone
--           from it.
-- OUTPUT  : dbo.online_retail_II_clean
-- EXPECT  : 1,044,848 rows.

select *
into dbo.online_retail_II_clean
from dbo.online_retail_II;

select 'STEP 00 - raw dataset copied' as step, count(*) as rows_after
from dbo.online_retail_II_clean;


/*
================================================================================
PART 2 - REMOVE NOISE AND FIX VALUES
================================================================================
Steps 1-4 delete rows. Steps 5-11 overwrite values. Step 12 removes the
duplicates that the overwrites can create.
================================================================================
*/

--------------------------------------------------------------------------------
-- STEP 01 | Remove exact full-row duplicates, pass 1                (DELETE)
--------------------------------------------------------------------------------
-- PROBLEM : profiling found 11,001 groups of identical rows (22,813 rows).
-- RULE    : rows identical across all 8 columns are one transaction recorded
--           more than once. Keep one copy of each group.
-- EXPECT  : 11,812 rows removed, 1,033,036 rows left.

-- Before: duplicate groups in the raw table
with cte_exact_duplicates as (
    select Country, Customer_ID, Description, Invoice,
        InvoiceDate, Price, Quantity, StockCode,
        count(*) duplicate_count
    from dbo.online_retail_II
    group by Country, Customer_ID, Description, Invoice,
        InvoiceDate, Price, Quantity, StockCode
    having count(*) > 1
)
select count(*) as duplicate_groups,
    sum(duplicate_count) as rows_in_duplicate_groups,
    sum(duplicate_count - 1) as rows_to_remove
from cte_exact_duplicates;

with cte_deduplication as (
    select *,
        row_number() over (
            partition by Country, Customer_ID, Description, Invoice,
                InvoiceDate, Price, Quantity, StockCode
            order by (select null)
        ) row_num
    from dbo.online_retail_II_clean
)
delete from cte_deduplication
where row_num > 1;
set @removed = @@rowcount;

select 'STEP 01 - exact duplicates removed (pass 1)' as step,
    @removed as rows_removed, count(*) as rows_after
from dbo.online_retail_II_clean;


--------------------------------------------------------------------------------
-- STEP 02 | Remove rows with no Description                          (DELETE)
--------------------------------------------------------------------------------
-- PROBLEM : profiling found 4,275 rows with a NULL Description.
-- RULE    : without a product name the row cannot be used for product-level
--           analysis. Remove it.
-- EXPECT  : 4,275 rows removed, 1,028,761 rows left.

select count(*) as rows_with_null_description
from dbo.online_retail_II_clean
where Description is null;

delete from dbo.online_retail_II_clean
where Description is null;
set @removed = @@rowcount;

select 'STEP 02 - rows with no Description removed' as step,
    @removed as rows_removed, count(*) as rows_after
from dbo.online_retail_II_clean;


--------------------------------------------------------------------------------
-- STEP 03 | Remove very short descriptions (3 characters or fewer)   (DELETE)
--------------------------------------------------------------------------------
-- PROBLEM : real product names are never this short. The only values found
--           are wet, FBA, MIA, ?, ?? and ???.
-- RULE    : remove those six values.
-- EXPECT  : 106 rows removed, 1,028,655 rows left.

select distinct Description, len(Description) as description_length
from dbo.online_retail_II_clean
where len(Description) <= 3;

delete from dbo.online_retail_II_clean
where Description in ('wet', 'FBA', 'MIA', '?', '??', '???');
set @removed = @@rowcount;

select 'STEP 03 - very short descriptions removed' as step,
    @removed as rows_removed, count(*) as rows_after
from dbo.online_retail_II_clean;


--------------------------------------------------------------------------------
-- STEP 04 | Remove junk / placeholder descriptions                   (DELETE)
--------------------------------------------------------------------------------
-- PROBLEM : the Description column also holds stock-take notes, marketplace
--           tags, damage notes, test entries and gift vouchers.
--           A substring pattern cannot tell those from real products: the
--           patterns %mould% and %check% also match SET OF 4 PANTRY JELLY
--           MOULDS, BROWN CHECK CAT DOORSTOP and the BAKING MOULD range.
-- RULE    : the case of the text separates the two groups.
--           - ALL UPPERCASE descriptions (where real products live): delete
--             only an exact match to a confirmed junk value.
--           - Non-uppercase descriptions (notes typed by staff, for example
--             "Adjustment by john on 26/01/2010"): delete by pattern. All 139
--             distinct matches were reviewed and none is a product.
--           This step runs before trimming and uppercasing (steps 5-7), so the
--           original casing is still available.
-- NOTE    : the CTE is written twice, once to preview and once to delete.
--           The two copies must stay identical.
-- EXPECT  : at most 2,879 more rows survive than under the old pattern-only
--           rule (2,864 real products plus 15 ambiguous DOTCOMGIFTSHOP rows).

-- Preview: what the rule will delete
with cte_junk as (
    select
        Description,
        case
            when Description collate Latin1_General_CS_AS = upper(Description) collate Latin1_General_CS_AS
                 and ltrim(rtrim(Description)) in (
                     'DOTCOM POSTAGE', 'SAMPLES', 'AMAZON FEE', 'CHECK', 'AMAZON',
                     'MISSING', 'DAMAGED', 'FOUND', 'POSSIBLE DAMAGES OR LOST?',
                     'WET/MOULDY', 'UPDATE')
                then 'uppercase - exact match'
            when Description collate Latin1_General_CS_AS <> upper(Description) collate Latin1_General_CS_AS
                 and (Description like '%damage%'
                   or Description like '%missing%'
                   or Description like '%found%'
                   or Description like '%adjust%'
                   or Description like '%smash%'
                   or Description like '%broken%'
                   or Description like '%crush%'
                   or Description like '%thrown away%'
                   or Description like '%wet%'
                   or Description like '%rusty%'
                   or Description like '%mould%'
                   or Description like '%lost%'
                   or Description like '%dotcom%'
                   or Description like '%amazon%'
                   or Description like '%ebay%'
                   or Description like '%test%'
                   or Description like '%sample%'
                   or Description like '%check%'
                   or Description = 'update')
                then 'non-uppercase - pattern'
        end as junk_rule
    from dbo.online_retail_II_clean
)
select junk_rule,
    count(distinct Description) as distinct_descriptions,
    count(*) as row_count
from cte_junk
where junk_rule is not null
group by junk_rule;

-- Delete (same rule)
with cte_junk as (
    select
        Description,
        case
            when Description collate Latin1_General_CS_AS = upper(Description) collate Latin1_General_CS_AS
                 and ltrim(rtrim(Description)) in (
                     'DOTCOM POSTAGE', 'SAMPLES', 'AMAZON FEE', 'CHECK', 'AMAZON',
                     'MISSING', 'DAMAGED', 'FOUND', 'POSSIBLE DAMAGES OR LOST?',
                     'WET/MOULDY', 'UPDATE')
                then 'uppercase - exact match'
            when Description collate Latin1_General_CS_AS <> upper(Description) collate Latin1_General_CS_AS
                 and (Description like '%damage%'
                   or Description like '%missing%'
                   or Description like '%found%'
                   or Description like '%adjust%'
                   or Description like '%smash%'
                   or Description like '%broken%'
                   or Description like '%crush%'
                   or Description like '%thrown away%'
                   or Description like '%wet%'
                   or Description like '%rusty%'
                   or Description like '%mould%'
                   or Description like '%lost%'
                   or Description like '%dotcom%'
                   or Description like '%amazon%'
                   or Description like '%ebay%'
                   or Description like '%test%'
                   or Description like '%sample%'
                   or Description like '%check%'
                   or Description = 'update')
                then 'non-uppercase - pattern'
        end as junk_rule
    from dbo.online_retail_II_clean
)
delete from cte_junk
where junk_rule is not null;
set @removed = @@rowcount;

select 'STEP 04 - junk descriptions removed' as step,
    @removed as rows_removed, count(*) as rows_after
from dbo.online_retail_II_clean;


--------------------------------------------------------------------------------
-- STEP 05 | Trim whitespace on Description                           (UPDATE)
--------------------------------------------------------------------------------
-- PROBLEM : the same product name appears with and without leading or
--           trailing spaces, which splits its numbers across "different"
--           products.
-- RULE    : trim both ends. No rows are removed.
-- CHECK   : the datalength comparison is used because "=" ignores trailing
--           spaces in SQL Server.

select count(*) as description_rows_to_trim
from dbo.online_retail_II_clean
where datalength(Description) <> datalength(rtrim(ltrim(Description)));

update dbo.online_retail_II_clean
set Description = rtrim(ltrim(Description));

select 'STEP 05 - Description trimmed' as step,
    count(*) as rows_still_with_whitespace
from dbo.online_retail_II_clean
where datalength(Description) <> datalength(rtrim(ltrim(Description)));   -- expect 0


--------------------------------------------------------------------------------
-- STEP 06 | Trim whitespace on StockCode                             (UPDATE)
--------------------------------------------------------------------------------
-- PROBLEM : profiling found one StockCode with a trailing space ('47503J ').
-- RULE    : trim both ends. No rows are removed.

select count(*) as stockcode_rows_to_trim
from dbo.online_retail_II_clean
where datalength(StockCode) <> datalength(rtrim(ltrim(StockCode)));

update dbo.online_retail_II_clean
set StockCode = rtrim(ltrim(StockCode));

select 'STEP 06 - StockCode trimmed' as step,
    count(*) as rows_still_with_whitespace
from dbo.online_retail_II_clean
where datalength(StockCode) <> datalength(rtrim(ltrim(StockCode)));   -- expect 0


--------------------------------------------------------------------------------
-- STEP 07 | Normalize Description to UPPERCASE                       (UPDATE)
--------------------------------------------------------------------------------
-- PROBLEM : real product descriptions are uppercase, but some rows hold
--           lowercase or mixed-case spellings of the same product.
-- RULE    : uppercase every Description. No rows are removed.

-- Before: casing breakdown
select
    case
        when Description collate Latin1_General_CS_AS = upper(Description) collate Latin1_General_CS_AS then 'ALL UPPERCASE'
        when Description collate Latin1_General_CS_AS = lower(Description) collate Latin1_General_CS_AS then 'ALL LOWERCASE'
        else 'MIXED CASE'
    end as casing_type,
    count(*) as num_rows
from dbo.online_retail_II_clean
group by
    case
        when Description collate Latin1_General_CS_AS = upper(Description) collate Latin1_General_CS_AS then 'ALL UPPERCASE'
        when Description collate Latin1_General_CS_AS = lower(Description) collate Latin1_General_CS_AS then 'ALL LOWERCASE'
        else 'MIXED CASE'
    end;

update dbo.online_retail_II_clean
set Description = upper(Description);

select 'STEP 07 - Description uppercased' as step,
    count(*) as rows_not_uppercase
from dbo.online_retail_II_clean
where Description collate Latin1_General_CS_AS <> upper(Description) collate Latin1_General_CS_AS;   -- expect 0


--------------------------------------------------------------------------------
-- STEP 08 | One canonical Description per StockCode                  (UPDATE)
--------------------------------------------------------------------------------
-- PROBLEM : one product (StockCode) can carry several spellings of its
--           Description (typos, leftovers of casing and spacing). All of the
--           rows are valid sales; only the text is inconsistent, and grouping
--           by Description would split one product across several entries.
-- RULE    : per StockCode, pick the most frequent Description (ties broken
--           alphabetically, so a re-run gives the same answer) and overwrite
--           every row of that StockCode with it.
-- OUTPUT  : dbo.stockcode_description_lookup
-- NOTE    : no rows are deleted here, but this step CAN turn two rows that
--           differed only in the spelling of Description into identical rows.
--           Those are removed in step 12.

select count(*) as stockcodes_with_multiple_descriptions_before
from (
    select StockCode
    from dbo.online_retail_II_clean
    group by StockCode
    having count(distinct Description) > 1
) x;

with cte_ranked as (
    select StockCode,
        Description,
        row_number() over (partition by StockCode order by count(*) desc, Description) row_num
    from dbo.online_retail_II_clean
    where Description is not null
    group by StockCode, Description
)
select StockCode, Description canonical_description
into dbo.stockcode_description_lookup
from cte_ranked
where row_num = 1;

update r
set r.Description = l.canonical_description
from dbo.online_retail_II_clean r
join dbo.stockcode_description_lookup l on r.StockCode = l.StockCode;

select count(*) as stockcodes_with_multiple_descriptions_after   -- expect 0
from (
    select StockCode
    from dbo.online_retail_II_clean
    group by StockCode
    having count(distinct Description) > 1
) x;


--------------------------------------------------------------------------------
-- STEP 09 | One Country per customer                                 (UPDATE)
--------------------------------------------------------------------------------
-- PROBLEM : some customers are logged under more than one Country (for
--           example customer 12346: United Kingdom on 50 rows, France on 2).
--           Profiling found 12 such customers.
-- RULE    : per registered customer, pick the most frequent Country (ties
--           broken alphabetically) and overwrite every row of that customer.
--           Guest rows (NULL Customer_ID) are left alone.
-- OUTPUT  : dbo.customer_country_lookup

select count(*) as customers_with_multiple_countries_before
from (
    select Customer_ID
    from dbo.online_retail_II_clean
    where Customer_ID is not null
    group by Customer_ID
    having count(distinct Country) > 1
) x;

with cte_customers_ranked_countries as (
    select Customer_ID, Country,
        count(*) country_count_per_customer,
        row_number() over (partition by Customer_ID order by count(*) desc, Country) row_num
    from dbo.online_retail_II_clean
    where Customer_ID is not null
    group by Customer_ID, Country
)
select Customer_ID, Country
into dbo.customer_country_lookup
from cte_customers_ranked_countries
where row_num = 1;

update clean_table
set clean_table.Country = country_l.Country
from dbo.online_retail_II_clean as clean_table
join dbo.customer_country_lookup as country_l
    on clean_table.Customer_ID = country_l.Customer_ID;

select count(*) as customers_with_multiple_countries_after   -- expect 0
from (
    select Customer_ID
    from dbo.online_retail_II_clean
    where Customer_ID is not null
    group by Customer_ID
    having count(distinct Country) > 1
) x;


--------------------------------------------------------------------------------
-- STEP 10 | Round Price to 3 decimals                                (UPDATE)
--------------------------------------------------------------------------------
-- PROBLEM : Price is stored as float, so two equal prices can differ in the
--           last digits and slip past the duplicate check in step 12.
-- RULE    : round to 3 decimals, the finest precision found in the data.

select data_type, numeric_precision, numeric_scale
from information_schema.columns
where table_name = 'online_retail_II_clean' and column_name = 'Price';

select count(*) as rows_where_price_changes
from dbo.online_retail_II_clean
where Price <> round(Price, 3);

update dbo.online_retail_II_clean
set Price = round(Price, 3);


--------------------------------------------------------------------------------
-- STEP 11 | One InvoiceDate per Invoice                              (UPDATE)
--------------------------------------------------------------------------------
-- PROBLEM : 83 invoices carry two different timestamps across their line
--           items (for example invoice 536365). One invoice is one event and
--           must have one date.
-- RULE    : per Invoice, keep the EARLIEST date and overwrite every row of
--           that invoice.
-- OUTPUT  : dbo.invoice_date_lookup

select count(*) as invoices_with_multiple_dates_before
from (
    select Invoice
    from dbo.online_retail_II_clean
    group by Invoice
    having count(distinct InvoiceDate) > 1
) x;

with cte_earliest_dates as (
    select Invoice,
        InvoiceDate,
        row_number() over (partition by Invoice order by InvoiceDate asc) row_num
    from dbo.online_retail_II_clean
    group by Invoice, InvoiceDate
)
select ed.Invoice,
    ed.InvoiceDate
into dbo.invoice_date_lookup
from cte_earliest_dates ed
where ed.row_num = 1;

update clean_table
set clean_table.InvoiceDate = inv_date.InvoiceDate
from dbo.online_retail_II_clean as clean_table
join dbo.invoice_date_lookup as inv_date
    on clean_table.Invoice = inv_date.Invoice;

select count(*) as invoices_with_multiple_dates_after   -- expect 0
from (
    select Invoice
    from dbo.online_retail_II_clean
    group by Invoice
    having count(distinct InvoiceDate) > 1
) x;


--------------------------------------------------------------------------------
-- STEP 12 | Remove exact full-row duplicates, pass 2                (DELETE)
--------------------------------------------------------------------------------
-- WHY     : steps 5-11 overwrote columns that define a duplicate (Description,
--           StockCode, Country, Price, InvoiceDate). Two rows that differed
--           only in those columns can now be identical. Any step that
--           overwrites a duplicate-defining column has to be followed by this
--           check, which is why this pass sits after the last overwrite.
-- RULE    : same as step 1.

with cte_dedup as (
    select *,
        row_number() over (
            partition by Invoice, StockCode, Description, Quantity,
                InvoiceDate, Price, Customer_ID, Country
            order by (select null)
        ) rn
    from dbo.online_retail_II_clean
)
delete from cte_dedup
where rn > 1;
set @removed = @@rowcount;

select 'STEP 12 - exact duplicates removed (pass 2)' as step,
    @removed as rows_removed, count(*) as rows_after
from dbo.online_retail_II_clean;


/*
================================================================================
PART 3 - FLAG AND CLASSIFY
================================================================================
No rows are removed below. Each step adds one column to
dbo.online_retail_II_clean. A row that still records a real business event is
flagged here and excluded later by an explicit, documented filter (step 21 and
the star schema), never deleted.
================================================================================
*/

--------------------------------------------------------------------------------
-- STEP 13 | Flag non-product StockCodes                     (ADD IsNonProductCode)
--------------------------------------------------------------------------------
-- PROBLEM : 61 StockCodes do not match the 4-5 digit product pattern. Some are
--           postage, fees, adjustments, test entries and gift vouchers; others
--           (DCGS%, SP1002) were reviewed by hand and are real products.
-- RULE    : flag the confirmed non-product codes listed below. The rows stay:
--           they are real operational events.
-- OUTPUT  : IsNonProductCode (1 = non-product, 0 = product)

alter table dbo.online_retail_II_clean add IsNonProductCode bit null;
go

declare @non_product_codes table (StockCode nvarchar(20));
insert into @non_product_codes values
    ('POST'), ('DOT'), ('M'), ('C2'), ('C3'), ('D'), ('B'), ('S'),
    ('CRUK'), ('BANK CHARGES'), ('AMAZONFEE'), ('ADJUST'), ('ADJUST2'),
    ('TEST001'), ('TEST002'),
    ('gift_0001_10'), ('gift_0001_20'), ('gift_0001_30'), ('gift_0001_40'),
    ('gift_0001_50'), ('gift_0001_60'), ('gift_0001_70'), ('gift_0001_80'),
    ('gift_0001_90');

update dbo.online_retail_II_clean
set IsNonProductCode = 1
where StockCode in (select StockCode from @non_product_codes);

update dbo.online_retail_II_clean
set IsNonProductCode = 0
where IsNonProductCode is null;

select IsNonProductCode, count(*) as row_count
from dbo.online_retail_II_clean
group by IsNonProductCode;


--------------------------------------------------------------------------------
-- STEP 14 | Flag guest customers                            (ADD CustomerType)
--------------------------------------------------------------------------------
-- PROBLEM : about 22.5% of rows have no Customer_ID, almost all in the UK.
--           That pattern matches guest checkout, not random missing data.
-- RULE    : label those rows Guest/Unregistered. They stay for product-level
--           analysis and are excluded from customer-level analysis later.
-- OUTPUT  : CustomerType (Registered / Guest/Unregistered)

alter table dbo.online_retail_II_clean add CustomerType nvarchar(20) null;
go

update dbo.online_retail_II_clean
set CustomerType = case
    when Customer_ID is null then 'Guest/Unregistered'
    else 'Registered'
end;

select CustomerType, count(*) as row_count
from dbo.online_retail_II_clean
group by CustomerType;


--------------------------------------------------------------------------------
-- STEP 15 | Flag zero / negative Price                        (ADD PriceFlag)
--------------------------------------------------------------------------------
-- PROBLEM : rows with a price of zero are adjustments and write-offs, not
--           sales.
-- RULE    : flag Price <= 0 so revenue KPIs can exclude it. The rows stay
--           because they show write-off volume.
-- OUTPUT  : PriceFlag (Normal / Zero/Adjustment)

alter table dbo.online_retail_II_clean add PriceFlag nvarchar(20) null;
go

update dbo.online_retail_II_clean
set PriceFlag = case
    when Price <= 0 then 'Zero/Adjustment'
    else 'Normal'
end;

select PriceFlag, count(*) as row_count
from dbo.online_retail_II_clean
group by PriceFlag;


--------------------------------------------------------------------------------
-- STEP 16 | Flag bulk quantities                         (ADD OutliersInQnt)
--------------------------------------------------------------------------------
-- PROBLEM : a few lines carry very large quantities (up to 80,995 units).
--           Profiling showed they are genuine bulk orders, usually matched by
--           a later cancellation, not data-entry errors.
-- RULE    : flag abs(Quantity) > 100 (the 99th percentile from profiling).
--           Nothing is removed; KPIs are reported with and without them.
-- OUTPUT  : OutliersInQnt (Wholesale/Bulk / Normal transaction)

alter table dbo.online_retail_II_clean add OutliersInQnt nvarchar(20) null;
go

update dbo.online_retail_II_clean
set OutliersInQnt = case
    when abs(Quantity) > 100 then 'Wholesale/Bulk'
    else 'Normal transaction'
end;

select OutliersInQnt, count(*) as row_count
from dbo.online_retail_II_clean
group by OutliersInQnt;


--------------------------------------------------------------------------------
-- STEP 17 | Flag the partial final month                  (ADD IsPartialMonth)
--------------------------------------------------------------------------------
-- PROBLEM : the data ends on 2011-12-09, so December 2011 holds 9 days
--           instead of a full month and breaks month-over-month comparisons.
-- RULE    : the month that contains the last InvoiceDate is partial when the
--           last InvoiceDate falls before that month's last day. This is the
--           same rule dim.date uses in the star schema.
-- OUTPUT  : IsPartialMonth (Partial month / Regular month)

alter table dbo.online_retail_II_clean add IsPartialMonth nvarchar(20) null;
go

declare @last_invoice_date datetime2 = (select max(InvoiceDate) from dbo.online_retail_II_clean);

update dbo.online_retail_II_clean
set IsPartialMonth = case
    when year(InvoiceDate) = year(@last_invoice_date)
     and month(InvoiceDate) = month(@last_invoice_date)
     and cast(@last_invoice_date as date) < eomonth(@last_invoice_date)
    then 'Partial month'
    else 'Regular month'
end;

select IsPartialMonth, count(*) as row_count
from dbo.online_retail_II_clean
group by IsPartialMonth;


--------------------------------------------------------------------------------
-- STEP 18 | Classify TransactionType                    (ADD TransactionType)
--------------------------------------------------------------------------------
-- PROBLEM : the 'C' invoice prefix alone does not separate real sales from
--           cancellations and stock write-offs.
-- RULE    : first match wins.
--             1. Invoice starts with 'C'         -> Cancellation
--             2. Quantity <= 0 and Price = 0     -> Stock Adjustment
--             3. Quantity <= 0                   -> Return
--             4. otherwise                       -> Sale
-- NOTE    : in this dataset rule 3 matches no rows (every non-'C' row with
--           Quantity <= 0 has Price = 0). It stays as a safety net.
-- OUTPUT  : TransactionType. Revenue queries filter on TransactionType = 'Sale'.

alter table dbo.online_retail_II_clean add TransactionType nvarchar(20) null;
go

update dbo.online_retail_II_clean
set TransactionType = case
    when Invoice like 'C%' then 'Cancellation'
    when Quantity <= 0 and Price = 0 then 'Stock Adjustment'
    when Quantity <= 0 then 'Return'
    else 'Sale'
end;

-- The categories must add up to the table's row count, with no NULLs
select TransactionType, count(*) as row_count
from dbo.online_retail_II_clean
group by TransactionType;

select
    (select count(*) from dbo.online_retail_II_clean where TransactionType is null) as rows_without_type,   -- expect 0
    (select count(*) from dbo.online_retail_II_clean) as table_rows;


--------------------------------------------------------------------------------
-- STEP 19 | Wholesale / Retail segmentation             (ADD CustomerSegment)
--------------------------------------------------------------------------------
-- PROBLEM : many customers are wholesalers. Averaging them together with
--           individual buyers skews AOV and CLV toward the wholesale accounts.
-- RULE    : per registered customer, take the average Quantity of their Sale
--           rows. A customer at or above the 95th percentile of those averages
--           is Wholesale; every other customer with sales is Retail. Guests
--           and customers with no Sale row get 'N/A'.
-- OUTPUT  : dbo.customer_segmentation_lookup, CustomerSegment
-- NOTE    : Quantity is cast to float so the average keeps its decimals.
--           Last verified run: cutoff 45.33, 294 Wholesale, 5,576 Retail,
--           53 N/A customers.

alter table dbo.online_retail_II_clean add CustomerSegment nvarchar(20) null;
go

with cte_avg_qnt_of_custs as (
    select Customer_ID,
        avg(cast(Quantity as float)) avg_qnt_per_cust
    from dbo.online_retail_II_clean
    where TransactionType = 'Sale' and Customer_ID is not null
    group by Customer_ID
),
cte_p95_val as (
    select distinct
        percentile_cont(0.95) within group (order by avg_qnt_per_cust) over () as p95_val
    from cte_avg_qnt_of_custs
)
select
    c.Customer_ID,
    c.avg_qnt_per_cust,
    case
        when c.avg_qnt_per_cust >= p.p95_val then 'Wholesale'
        else 'Retail'
    end as CustomerSegment
into dbo.customer_segmentation_lookup
from cte_avg_qnt_of_custs c
cross join cte_p95_val p;

update clean_table
set clean_table.CustomerSegment = seg.CustomerSegment
from dbo.online_retail_II_clean as clean_table
join dbo.customer_segmentation_lookup as seg
    on clean_table.Customer_ID = seg.Customer_ID;

-- Guests and customers without a Sale row have no segment: relabel NULL as 'N/A'
update dbo.online_retail_II_clean
set CustomerSegment = 'N/A'
where CustomerSegment is null;

select CustomerSegment,
    count(*) as row_count,
    count(distinct Customer_ID) as customers
from dbo.online_retail_II_clean
group by CustomerSegment;


--------------------------------------------------------------------------------
-- STEP 20 | Right-censoring flag                            (ADD IsCensored)
--------------------------------------------------------------------------------
-- PROBLEM : a customer whose first purchase was close to the end of the data
--           has not had a fair window to buy again. Comparing their repeat
--           rate with long-standing customers would be unfair.
-- RULE    : per registered customer, take the first Sale date. A customer whose
--           first purchase falls in the last 90 days of the data (after
--           2011-09-10) is censored. The cutoff is calculated from the data.
-- OUTPUT  : dbo.customer_censoring_lookup, IsCensored (1 / 0; NULL for guests
--           and customers with no Sale row)

alter table dbo.online_retail_II_clean add IsCensored bit null;
go

with cte_first_purchase as (
    select Customer_ID, min(InvoiceDate) as first_purchase_date
    from dbo.online_retail_II_clean
    where TransactionType = 'Sale' and Customer_ID is not null
    group by Customer_ID
),
cte_cutoff_date as (
    select dateadd(day, -90, max(InvoiceDate)) as cutoff_date
    from dbo.online_retail_II_clean
)
select
    fp.Customer_ID,
    fp.first_purchase_date,
    case
        when fp.first_purchase_date > c.cutoff_date then 1
        else 0
    end as IsCensored
into dbo.customer_censoring_lookup
from cte_first_purchase fp
cross join cte_cutoff_date c;

update clean_table
set clean_table.IsCensored = censor_l.IsCensored
from dbo.online_retail_II_clean as clean_table
join dbo.customer_censoring_lookup as censor_l
    on clean_table.Customer_ID = censor_l.Customer_ID;

select IsCensored,
    count(*) as row_count,
    count(distinct Customer_ID) as customers
from dbo.online_retail_II_clean
group by IsCensored;


/*
================================================================================
PART 4 - BUILD THE FACT SUBSET
================================================================================
*/

--------------------------------------------------------------------------------
-- STEP 21 | Build dbo.online_retail_II_fact                     (CREATE TABLE)
--------------------------------------------------------------------------------
-- PURPOSE : the valid-sales subset of the clean table. The star schema keeps
--           all transaction types in fact.sales; this table is what a valid
--           sale means, and the star schema build checks its own valid-sales
--           rows against it (validation V4 of the star schema script).
-- RULE    : TransactionType = 'Sale'
--           AND IsNonProductCode = 0
--           AND Description IS NOT NULL
--           AND Price > 0
-- OUTPUT  : dbo.online_retail_II_fact

select *
into dbo.online_retail_II_fact
from dbo.online_retail_II_clean
where TransactionType = 'Sale'
    and IsNonProductCode = 0
    and Description is not null
    and Price > 0;

select 'STEP 21 - fact subset built' as step,
    (select count(*) from dbo.online_retail_II_clean) as clean_rows,
    (select count(*) from dbo.online_retail_II_fact) as fact_rows,
    (select count(*) from dbo.online_retail_II_clean)
        - (select count(*) from dbo.online_retail_II_fact) as rows_excluded;


/*
================================================================================
PART 5 - VALIDATION
================================================================================
Read the result sets in order. Every line marked "expect" must hold.
================================================================================
*/

-- V1 | Every flag column is filled in.
-- expect: all 0 (IsCensored is allowed to be NULL, so it is not listed)
select
    sum(case when IsNonProductCode is null then 1 else 0 end) as null_IsNonProductCode,
    sum(case when CustomerType is null then 1 else 0 end) as null_CustomerType,
    sum(case when PriceFlag is null then 1 else 0 end) as null_PriceFlag,
    sum(case when OutliersInQnt is null then 1 else 0 end) as null_OutliersInQnt,
    sum(case when IsPartialMonth is null then 1 else 0 end) as null_IsPartialMonth,
    sum(case when TransactionType is null then 1 else 0 end) as null_TransactionType,
    sum(case when CustomerSegment is null then 1 else 0 end) as null_CustomerSegment
from dbo.online_retail_II_clean;

-- V2 | Nulls in the fact subset.
-- expect: all 0 except Customer_ID (guest rows are kept on purpose)
select
    sum(case when Invoice is null then 1 else 0 end) as Invoice_nulls,
    sum(case when StockCode is null then 1 else 0 end) as StockCode_nulls,
    sum(case when Description is null then 1 else 0 end) as Description_nulls,
    sum(case when Quantity is null then 1 else 0 end) as Quantity_nulls,
    sum(case when InvoiceDate is null then 1 else 0 end) as InvoiceDate_nulls,
    sum(case when Price is null then 1 else 0 end) as Price_nulls,
    sum(case when Customer_ID is null then 1 else 0 end) as Customer_ID_nulls,
    sum(case when Country is null then 1 else 0 end) as Country_nulls
from dbo.online_retail_II_fact;

-- V3 | Min / max sanity check on the fact subset.
-- expect: minPrice > 0, minQnt >= 1, dates 2009-12-01 to 2011-12-09
select
    min(Price) minPrice, max(Price) maxPrice,
    min(Quantity) minQnt, max(Quantity) maxQnt,
    min(InvoiceDate) minInvDate, max(InvoiceDate) maxInvDate
from dbo.online_retail_II_fact;

-- V4 | Distinct counts, clean table against fact subset.
-- expect: the fact subset counts are equal to or smaller than the clean counts
with cte_fact_table_numbers as (
    select count(distinct StockCode) as distinct_stockcodes,
        count(distinct Customer_ID) as distinct_customers,
        count(distinct Country) as distinct_countries
    from dbo.online_retail_II_fact
),
cte_clean_table_numbers as (
    select count(distinct StockCode) as distinct_stockcodes,
        count(distinct Customer_ID) as distinct_customers,
        count(distinct Country) as distinct_countries
    from dbo.online_retail_II_clean
)
select
    c.distinct_stockcodes as clean_stockcodes,
    f.distinct_stockcodes as fact_stockcodes,
    c.distinct_stockcodes - f.distinct_stockcodes as STOCKCODES_DIFFERENCE,

    c.distinct_customers as clean_customers,
    f.distinct_customers as fact_customers,
    c.distinct_customers - f.distinct_customers as CUSTOMERS_DIFFERENCE,

    c.distinct_countries as clean_countries,
    f.distinct_countries as fact_countries,
    c.distinct_countries - f.distinct_countries as COUNTRIES_DIFFERENCE
from cte_fact_table_numbers f
cross join cte_clean_table_numbers c;

-- V5 | Full-row duplicates in the fact subset.
-- expect: 0 rows
select Invoice, StockCode, Description, Quantity, InvoiceDate, Price, Customer_ID, Country, count(*) duplicate_count
from dbo.online_retail_II_fact
group by Invoice, StockCode, Description, Quantity, InvoiceDate, Price, Customer_ID, Country
having count(*) > 1;

-- V6 | Guest rows are still present in the fact subset.
-- expect: the inclusion rule never filters on Customer_ID, so only guest rows
--         that are not valid sales are missing (null_difference is small)
with cte_fact_null_count as (
    select count(*) fact_null_count
    from dbo.online_retail_II_fact f
    where f.Customer_ID is null
), cte_clean_null_count as (
    select count(*) clean_null_count
    from dbo.online_retail_II_clean c
    where c.Customer_ID is null
)
select clean_null_count,
    fact_null_count,
    (clean_null_count - fact_null_count) null_difference
from cte_fact_null_count
cross join cte_clean_null_count;

-- V7 | Recompute revenue by hand for sampled invoices.
-- Pick invoices, pull the line items of one invoice, then compare the total
-- below with a manual calculation of those line items in a spreadsheet.
select distinct top 10 Invoice
from dbo.online_retail_II_fact
order by Invoice;

select *
from dbo.online_retail_II_fact
where Invoice = '536365';

select Invoice, sum(Quantity * Price) as invoice_total
from dbo.online_retail_II_fact
where Invoice = '536365'
group by Invoice;

-- V8 | Clean table against fact subset, side by side.
with cte_clean_metrics as (
    select
        count(*) as total_rows,
        sum(case when Description is null then 1 else 0 end) as null_descriptions,
        sum(case when Price <= 0 then 1 else 0 end) as zero_negative_price,
        sum(case when Customer_ID is null then 1 else 0 end) as null_customer_id,
        count(distinct StockCode) as distinct_stockcodes,
        count(distinct Customer_ID) as distinct_customers,
        count(distinct Country) as distinct_countries
    from dbo.online_retail_II_clean
),
cte_fact_metrics as (
    select
        count(*) as total_rows,
        sum(case when Description is null then 1 else 0 end) as null_descriptions,
        sum(case when Price <= 0 then 1 else 0 end) as zero_negative_price,
        sum(case when Customer_ID is null then 1 else 0 end) as null_customer_id,
        count(distinct StockCode) as distinct_stockcodes,
        count(distinct Customer_ID) as distinct_customers,
        count(distinct Country) as distinct_countries
    from dbo.online_retail_II_fact
)
select
    c.total_rows as clean_total_rows, f.total_rows as fact_total_rows,
    c.null_descriptions as clean_null_descriptions, f.null_descriptions as fact_null_descriptions,
    c.zero_negative_price as clean_zero_negative_price, f.zero_negative_price as fact_zero_negative_price,
    c.null_customer_id as clean_null_customer_id, f.null_customer_id as fact_null_customer_id,
    c.distinct_stockcodes as clean_distinct_stockcodes, f.distinct_stockcodes as fact_distinct_stockcodes,
    c.distinct_customers as clean_distinct_customers, f.distinct_customers as fact_distinct_customers,
    c.distinct_countries as clean_distinct_countries, f.distinct_countries as fact_distinct_countries
from cte_clean_metrics c
cross join cte_fact_metrics f;

-- V9 | Regression check for the junk rule (step 4).
-- These real products were once deleted by mistake.
-- expect: both counts above 0. The last list may show only rows with real
--         numeric StockCodes (products whose name mentions the gift shop).
select count(*) as pantry_jelly_moulds
from dbo.online_retail_II_fact
where Description like '%PANTRY JELLY MOULDS%';

select count(*) as brown_check_cat_doorstop
from dbo.online_retail_II_fact
where Description = 'BROWN CHECK CAT DOORSTOP';

select StockCode, Description, count(*) as rows_in_fact
from dbo.online_retail_II_fact
where Description like '%DOTCOM%'
group by StockCode, Description;


/*
================================================================================
REFERENCE RUN (last verified before this restructure)
================================================================================
The counts below came from the previous version of this script, which applied
the same logic in a different step order. This version should reproduce them
exactly; if any number differs, find out why before building the star schema.

    dbo.online_retail_II_clean   1,026,237 rows
    dbo.online_retail_II_fact    1,003,352 rows
    Guest rows                   228,452
    TransactionType              Sale 1,007,179 / Cancellation 18,934 /
                                 Stock Adjustment 124 / Return 0
    Customers by segment         Wholesale 294 / Retail 5,576 / N/A 53
    Wholesale cutoff             average quantity 45.33

The per-step row counts of steps 1-3 (11,812 / 4,275 / 106 removed) do not
depend on the junk rule and should match the earlier log. Steps 4 and 12 have
new counts under the corrected rules: paste them into the row-count log.
================================================================================
*/
