/*
================================================================================
ONLINE RETAIL II - DATA PROFILING
================================================================================
Purpose: Systematic column-by-column and cross-column profiling of the
         online_retail_II dataset prior to data cleaning.
================================================================================
*/
 
create database OnlineRetailII;
 
-- Preview the full dataset
select *
from dbo.online_retail_II;
 
-- Review column names and data types
select COLUMN_NAME, DATA_TYPE 
from INFORMATION_SCHEMA.COLUMNS
where TABLE_NAME = 'online_retail_II';
 
 
/*
================================================================================
COLUMN 1: Invoice
================================================================================
*/
 
-- Check for the total number of rows of this column
select count(retail.Invoice)
from dbo.online_retail_II retail;

-- Check for blank rows
select retail.Invoice
from dbo.online_retail_II retail
where retail.Invoice = '' or retail.Invoice = ' ';
 
-- Check for nulls
select retail.Invoice
from dbo.online_retail_II retail
where retail.Invoice is null;
 
-- Check for duplicates
select retail.Invoice, count(retail.Invoice) num_of_duplicate_invoices
from dbo.online_retail_II retail
group by retail.Invoice
having count(retail.Invoice) > 1;
 
-- Check for the total number of duplicates in the column
with cte_invoice_duplicates as (
	select retail.Invoice, count(retail.Invoice) num_of_duplicate_invoices
	from dbo.online_retail_II retail
	group by retail.Invoice
	having count(retail.Invoice) > 1
)
select count(cte_invoice_duplicates.num_of_duplicate_invoices) total_number_of_invoice_duplicates
from cte_invoice_duplicates;
 
-- Check for leading or trailing whitespaces
select retail.Invoice
from dbo.online_retail_II retail
where datalength(retail.Invoice) <> datalength(ltrim(rtrim(retail.Invoice)));
 
-- Check for unexpected special characters
select retail.Invoice 
from dbo.online_retail_II retail
where retail.Invoice like '%[^A-Za-z0-9]%';
 
-- Check for inconsistent value length
select len(retail.Invoice) invoice_data_length, 
	count(*) number_of_rows
from dbo.online_retail_II retail
group by len(retail.Invoice);
 
-- Check for the number of invoices that begin with 'C' (cancellations)
select count(retail.Invoice) 
from dbo.online_retail_II retail
where retail.Invoice like 'C%';
 
-- Check for other non-numeric Invoice prefixes besides 'C'
-- (extract first character of each Invoice and count rows per distinct prefix,
--  to reveal any other transaction-type prefixes besides cancellations)
select left(retail.Invoice, 1) invoice_prefix, 
    count(*) as row_count
from dbo.online_retail_II retail
group by left(retail.Invoice, 1);
 
 
/*
================================================================================
COLUMN 2: StockCode
================================================================================
*/
 
-- Check for the total number of rows of this column
select count(retail.Invoice)
from dbo.online_retail_II retail;

-- Check for blank rows
select retail.StockCode
from dbo.online_retail_II retail
where retail.StockCode = '' or retail.StockCode = ' ';
 
-- Check for nulls
select retail.StockCode
from dbo.online_retail_II retail
where retail.StockCode is null;
 
-- Check for duplicates
select retail.StockCode, count(retail.StockCode) num_of_duplicate_stockcodes
from dbo.online_retail_II retail
group by retail.StockCode
having count(*) > 1;
 
-- Check for the total number of duplicates in the column
with cte_duplicates as (
	select retail.StockCode, count(retail.StockCode) num_of_duplicate_stockcodes
	from dbo.online_retail_II retail
	group by retail.StockCode
	having count(*) > 1
)
select count(cte_duplicates.num_of_duplicate_stockcodes) total_number_of_duplicates
from cte_duplicates;
 
-- Check for leading or trailing whitespaces
select distinct retail.StockCode
from dbo.online_retail_II retail
where datalength(retail.StockCode) <> datalength(rtrim(ltrim(retail.StockCode)));
 
-- Check for inconsistent casing
select distinct retail.StockCode
from dbo.online_retail_II retail
where retail.StockCode <> upper(retail.StockCode);
 
-- Check for unexpected special characters
select distinct retail.StockCode
from dbo.online_retail_II retail
where retail.StockCode like '%[^A-Za-z0-9]%';
 
-- Check for inconsistent value length
select len(retail.StockCode) stockcode_length, 
	count(*) num_of_rows
from dbo.online_retail_II retail
group by len(retail.StockCode);
 
-- Check for internal whitespaces
select distinct retail.StockCode
from dbo.online_retail_II retail
where retail.StockCode like '% %'
  and retail.StockCode <> rtrim(ltrim(retail.StockCode));
 
-- Check for non-product placeholder codes (codes not matching the standard 4-5 digit pattern)
select distinct retail.StockCode
from dbo.online_retail_II retail
where retail.StockCode not like '[0-9][0-9][0-9][0-9][0-9]%'
  and retail.StockCode not like '[0-9][0-9][0-9][0-9]%';
 
-- Check the total count of distinct StockCodes
select count(distinct retail.StockCode)
from dbo.online_retail_II retail;
 
 
/*
================================================================================
COLUMN 3: Description
================================================================================
*/
 
-- Check for nulls
select retail.Description
from dbo.online_retail_II retail
where retail.Description is null;
 
-- Check for the count of nulls
select count(*) num_of_null_descr
from dbo.online_retail_II retail
where retail.Description is null;
 
-- Check for blanks
select retail.Description
from dbo.online_retail_II retail
where retail.Description = '' or retail.Description = ' ';
 
-- Check for the count of rows with leading/trailing whitespace
select count(*) num_rows_with_whitespace
from dbo.online_retail_II retail
where datalength(retail.Description) <> datalength(rtrim(ltrim(retail.Description)));
 
-- Check for very short descriptions (real product names are rarely this short)
select distinct retail.Description, len(retail.Description) as descr_length
from dbo.online_retail_II retail
where len(retail.Description) <= 3;
 
-- Check for duplicates
select retail.Description, count(retail.Description) num_of_duplicate_description
from dbo.online_retail_II retail
group by retail.Description
having count(*) > 1;
 
-- Check for the total number of duplicate descriptions
with cte_dupl_description as (
    select retail.Description, count(retail.Description) num_of_duplicate_description
    from dbo.online_retail_II retail
    group by retail.Description
    having count(*) > 1
)
select count(cte_dupl_description.num_of_duplicate_description) total_duplicate_descriptions
from cte_dupl_description;
 
-- Check for leading or trailing whitespaces (distinct values)
select count(distinct retail.Description)
from dbo.online_retail_II retail
where datalength(retail.Description) <> datalength(rtrim(ltrim(retail.Description)));
 
-- Check for upper, lower, and mixed case descriptions
select distinct retail.Description,
	case
        when retail.Description collate Latin1_General_CS_AS = upper(retail.Description) collate Latin1_General_CS_AS then 'ALL UPPERCASE'
		when retail.Description collate Latin1_General_CS_AS = lower(retail.Description) collate Latin1_General_CS_AS then 'ALL LOWERCASE'
		else 'MIXED CASE'
    end as casing_type
from dbo.online_retail_II retail
order by casing_type, retail.Description;
 
-- Check for the count of upper, lower, and mixed case descriptions
select 
    case
        when retail.Description collate Latin1_General_CS_AS = upper(retail.Description) collate Latin1_General_CS_AS then 'ALL UPPERCASE'
        when retail.Description collate Latin1_General_CS_AS = lower(retail.Description) collate Latin1_General_CS_AS then 'ALL LOWERCASE'
        else 'MIXED CASE'
    end as casing_type,
    count(*) as num_rows
from dbo.online_retail_II retail
group by 
    case
        when retail.Description collate Latin1_General_CS_AS = upper(retail.Description) collate Latin1_General_CS_AS then 'ALL UPPERCASE'
        when retail.Description collate Latin1_General_CS_AS = lower(retail.Description) collate Latin1_General_CS_AS then 'ALL LOWERCASE'
        else 'MIXED CASE'
    end;
 
-- Check for placeholder/junk values (confirmed patterns from this dataset)
select distinct retail.Description
from dbo.online_retail_II retail
where retail.Description like '%damage%'
   or retail.Description like '%missing%'
   or retail.Description like '%found%'
   or retail.Description like '%adjust%'
   or retail.Description like '%smash%'
   or retail.Description like '%broken%'
   or retail.Description like '%crush%'
   or retail.Description like '%thrown away%'
   or retail.Description like '%wet%'
   or retail.Description like '%rusty%'
   or retail.Description like '%mould%'
   or retail.Description like '%lost%'
   or retail.Description like '%dotcom%'
   or retail.Description like '%amazon%'
   or retail.Description like '%ebay%'
   or retail.Description like '%test%'
   or retail.Description like '%sample%'
   or retail.Description like '%check%'
   or retail.Description = '?'
   or retail.Description like '?%';
 
-- Check how many distinct descriptions exist per StockCode (a StockCode should generally map to one consistent product name)
with cte_stockcode_multi_desc as (
    select count(distinct Description) num_of_distinct_descriptions
    from dbo.online_retail_II 
    group by StockCode
    having count(distinct Description) > 1
)
select count(*) total_stockcode_multi_desc
from cte_stockcode_multi_desc;
 
-- Check how many distinct StockCodes share the same Description
-- LOWERCASE descriptions (i.e. descriptions that are not all-uppercase)
with cte_lowercase_desc_multi_stockcode as (
    select retail.Description, 
        count(distinct retail.StockCode) distinct_stockcodes
    from dbo.online_retail_II retail
    where (retail.Description is not null) 
    and (retail.Description collate Latin1_General_CS_AS <> upper(retail.Description) collate Latin1_General_CS_AS)
    group by retail.Description
    having count(distinct retail.StockCode) > 1
)
select count(*) total_lowercase_desc_multi_stockcode
from cte_lowercase_desc_multi_stockcode;
 
-- Check how many distinct StockCodes share the same Description
-- UPPERCASE descriptions (i.e. descriptions that are not all-lowercase)
with cte_uppercase_desc_multi_stockcode as (
    select retail.Description, 
        count(distinct retail.StockCode) distinct_stockcodes
    from dbo.online_retail_II retail
    where (retail.Description is not null) 
    and (retail.Description collate Latin1_General_CS_AS <> lower(retail.Description) collate Latin1_General_CS_AS)
    group by retail.Description
    having count(distinct retail.StockCode) > 1
)
select count(*) total_uppercase_desc_multi_stockcode
from cte_uppercase_desc_multi_stockcode;
 
 
/*
================================================================================
COLUMN 4: Price
================================================================================
*/
 
-- Check for nulls 
select retail.Price 
from dbo.online_retail_II retail
where retail.Price is null;
 
-- Check for the total number of nulls
select count(*) num_of_nulls_in_price
from dbo.online_retail_II retail
where retail.Price is null;
 
-- Check for negative or zero values 
select retail.Price 
from dbo.online_retail_II retail
where retail.Price <= 0;
 
-- Check for the total number of zero or negative Price values
select count(*)
from dbo.online_retail_II retail
where retail.Price <= 0;
 
-- Check for min and max values
select min(retail.Price) min_value, 
    max(retail.Price) max_value
from dbo.online_retail_II retail;
 
-- Check for the average value
select avg(retail.Price)
from dbo.online_retail_II retail;
 
-- Check for the median value
select distinct 
    PERCENTILE_CONT(0.5) within group (order by retail.Price) over () as median
from dbo.online_retail_II retail
where retail.Price > 0;
 
-- Check for the 95th percentile value
select distinct 
    PERCENTILE_CONT(0.95) within group (order by retail.Price) over () as p95_value
from dbo.online_retail_II retail
where retail.Price > 0;
 
-- Check for the 99th percentile value
select distinct 
    PERCENTILE_CONT(0.99) within group (order by retail.Price) over () as p99_value
from dbo.online_retail_II retail
where retail.Price > 0;
 
-- Check for price consistency per StockCode
-- (the same product should generally have a stable price)
select 
    retail.StockCode,
    stdev(retail.Price) stdev_price, 
    count(distinct retail.Price) distinct_price
from dbo.online_retail_II retail
where retail.Price > 0
group by retail.StockCode
having count(distinct retail.Price) > 1 
order by distinct_price asc;
 
 
/*
================================================================================
COLUMN 5: InvoiceDate
================================================================================
*/
 
-- Check for nulls
select retail.InvoiceDate
from dbo.online_retail_II retail
where retail.InvoiceDate is null;
 
-- Check for min and max dates (date range of the dataset)
select min(retail.InvoiceDate) minInvoiceDate, 
    max(retail.InvoiceDate) maxInvoiceDate
from dbo.online_retail_II retail;
 
-- Check for future dates (beyond today / expected dataset range)
select retail.InvoiceDate
from dbo.online_retail_II retail
where retail.InvoiceDate > getdate();
 
-- Check for time component anomalies
-- (if one time value, e.g. 00:00:00, dominates, that suggests date-only data
--  rather than real transaction times)
select cast(retail.InvoiceDate as time) timePortion, 
    count(*) row_count
from dbo.online_retail_II retail
group by cast(retail.InvoiceDate as time)
order by row_count desc;
 
-- Check InvoiceDate consistency per Invoice
-- (the same invoice should have a single date, not multiple timestamps)
select retail.Invoice, count(distinct retail.InvoiceDate) row_count
from dbo.online_retail_II retail
group by retail.Invoice
having count(distinct retail.InvoiceDate) > 1
order by row_count desc;
 
-- Check for duplicate InvoiceDate values (frequency check)
select retail.InvoiceDate, count(*) row_count
from dbo.online_retail_II retail
group by retail.InvoiceDate
having count(*) > 1
order by row_count desc;

select retail.Invoice, count(*) 
from dbo.online_retail_II retail
where retail.InvoiceDate = '2011-10-31 14:41:00'
group by retail.Invoice
order by count(*) desc;
 
 
/*
================================================================================
COLUMN 6: Quantity
================================================================================
*/
 
-- Check for nulls
select retail.Quantity
from dbo.online_retail_II retail
where retail.Quantity is null;
 
-- Check for zero values 
select retail.Quantity
from dbo.online_retail_II retail
where retail.Quantity = 0;
 
-- Check for negative values (returns/cancellations)
select retail.Quantity
from dbo.online_retail_II retail
where retail.Quantity < 0;
 
-- Check for the total number of negative values
select count(retail.Quantity) total_num_of_negative_values
from dbo.online_retail_II retail
where retail.Quantity < 0;
 
-- Check for min, max, and average values
select min(retail.Quantity) min_value, 
    max(retail.Quantity) max_value, 
    avg(retail.Quantity) avg_value
from dbo.online_retail_II retail;
 
-- Check for the median value
select distinct 
    PERCENTILE_CONT(0.5) within group (order by retail.Quantity) over () as median
from dbo.online_retail_II retail;
 
-- Check for the 95th percentile value
select distinct 
    PERCENTILE_CONT(0.95) within group (order by retail.Quantity) over () as p95_value
from dbo.online_retail_II retail;
 
-- Check for the 99th percentile value
select distinct 
    PERCENTILE_CONT(0.99) within group (order by retail.Quantity) over () as p99_value
from dbo.online_retail_II retail;
 
-- Check for duplicate Quantity values (frequency check)
select retail.Quantity, count(*) row_count
from dbo.online_retail_II retail
group by retail.Quantity
having count(*) > 1
order by row_count desc;
 
-- Check whether negative Quantity correlates with cancelled invoices (Invoice like 'C%')
-- (if cancellations don't line up almost entirely with negative Quantity,
--  that signals an inconsistent labeling convention)
select 
    case when retail.Invoice like 'C%' then 'Cancelled' else 'Normal invoice' 
    end as normal_cancelled_invoices,
    case when retail.Quantity < 0 then 'Negative or zero quantity' else 'Normal quantity' 
    end as normal_negative_quantities, 
    count(*)
from dbo.online_retail_II retail
group by 
    (case when retail.Invoice like 'C%' then 'Cancelled' else 'Normal invoice' end),
    (case when retail.Quantity < 0 then 'Negative or zero quantity' else 'Normal quantity' end);
 
-- Check for extreme outliers (unusually large quantities)
-- (filter absolute Quantity values well beyond the p99 threshold and individually — bulk wholesale orders and data entry errors can look alike)
with cte_perc99value as (
    select PERCENTILE_CONT(0.99) within group (order by retail.Quantity) over () as p99_value,
        retail.Quantity qnt, 
        retail.Invoice invc, 
        retail.StockCode stcode
    from dbo.online_retail_II retail
) 
select cte_perc99value.p99_value, 
    cte_perc99value.invc, 
    cte_perc99value.stcode, 
    cte_perc99value.qnt
from cte_perc99value
where abs(cte_perc99value.qnt) > cte_perc99value.p99_value
order by abs(cte_perc99value.qnt) desc;
 
-- Check Quantity vs Price relationship for returns
-- (expected convention: negative Quantity paired with a non-negative Price; a negative Price on top of negative Quantity may signal a double-counted adjustment)
select count(*) rows_with_odd_quantities, 
    case 
        when retail.Price < 0 then 'Negative price' when retail.Price = 0 then 'Zero price' when retail.Price > 0 then 'Positive price' 
    end as PRICES
from dbo.online_retail_II retail
where retail.Quantity <= 0
group by 
    case 
        when retail.Price < 0 then 'Negative price' when retail.Price = 0 then 'Zero price' when retail.Price > 0 then 'Positive price' 
    end;
 
 
/*
================================================================================
COLUMN 7: Customer_ID
================================================================================
*/
 
-- Check for nulls
select retail.Customer_ID
from dbo.online_retail_II retail
where retail.Customer_ID is null;
 
-- Check for the total number of nulls
select count(*) count_of_nulls
from dbo.online_retail_II retail
where retail.Customer_ID is null;
 
-- Check for the percentage of nulls
with cte_nullcount as (
    select count(*) count_of_nulls
    from dbo.online_retail_II retail
    where retail.Customer_ID is null
), cte_total_row_count as (
    select count(*) as total_row_count
    from dbo.online_retail_II retail
)
select (cte_nullcount.count_of_nulls / 
    cast(cte_total_row_count.total_row_count as float) * 100) as percentage_of_nulls
from cte_nullcount, cte_total_row_count;
 
-- Check whether missing Customer_ID clusters around a particular Country or Invoice pattern
-- (if nulls concentrate in one country or in cancellation invoices, that points to a
--  systematic cause, e.g. guest checkouts or manual stock adjustments, rather than
--  random missingness)
select retail.Country, 
    count(*),
    case 
        when retail.Invoice like 'C%' then 'Cancelled invoice' else 'Normal'
    end as null_grouping
from dbo.online_retail_II retail
where Customer_ID is null
group by retail.Country, 
    case when retail.Invoice like 'C%' then 'Cancelled invoice' else 'Normal' end;
 
-- Check whether null Customer_ID maps to non-cancellation invoices
select count(*) number_of_null_customerids, 
    (case when retail.Invoice like 'C%' then 'Cancelled transaction' else 'Uknown transaction' end) transaction_flag
from dbo.online_retail_II retail
where retail.Customer_ID is null
group by  
    case when retail.Invoice like 'C%' then 'Cancelled transaction' else 'Uknown transaction' end;
 
-- Check how many null Customer_ID rows are cancelled invoices
select *
from dbo.online_retail_II retail
where retail.Customer_ID is null
  and retail.Invoice like 'C%';
 
-- Check whether a single Invoice maps to more than one Customer_ID
select retail.Invoice, count(distinct retail.Customer_ID) distinct_customer_ids
from dbo.online_retail_II retail
group by retail.Invoice
having count(distinct retail.Customer_ID) > 1;
 
-- Check for min and max Customer_ID values (sanity check that the ID range looks like real IDs)
select min(retail.Customer_ID) min_customerid, 
    max(retail.Customer_ID) max_customerid
from dbo.online_retail_II retail;
 
-- Check whether any single Customer_ID maps to more than one Country
-- (more than one distinct country per ID could mean inconsistent records, or that
--  Customer_ID isn't as uniquely tied to one country as assumed)
select retail.Customer_ID, count(distinct retail.Country)
from dbo.online_retail_II retail
where retail.Customer_ID is not null
group by retail.Customer_ID
having count(distinct retail.Country) > 1;
 
-- Check whether null Customer_ID correlates with zero or negative Price
-- (bucket null-Customer_ID rows by Price sign; heavy clustering around zero-Price
--  rows would point toward free items/samples rather than genuine missing-customer sales)
select retail.Customer_ID, 
    case 
        when retail.Price = 0 then 'Zero' 
        when retail.Price < 0 then 'Negative' 
        else 'Positive'
    end as price_bucketing
from dbo.online_retail_II retail
where retail.Customer_ID is null;
 
-- Count the instances of the price bucketing above
with cte_price_segmentation as (
    select retail.Customer_ID, 
        case 
            when retail.Price = 0 then 'Zero' 
            when retail.Price < 0 then 'Negative' 
            else 'Positive'
        end as price_bucketing
    from dbo.online_retail_II retail
    where retail.Customer_ID is null
)
select price_bucketing, 
    count(*) as row_count
from cte_price_segmentation 
group by cte_price_segmentation.price_bucketing;
 
 
/*
================================================================================
COLUMN 8: Country
================================================================================
*/
 
-- Check for nulls
select retail.Country
from dbo.online_retail_II retail
where retail.Country is null;
 
-- Check for blanks
select retail.Country
from dbo.online_retail_II retail
where retail.Country = '' or retail.Country = ' ';
 
-- Check the full list of distinct Country values along with row counts
-- (with only ~40 expected countries, eyeballing the full list catches inconsistent
--  naming, e.g. "United Kingdom" vs "UK", typos, or unexpected entries)
select retail.Country, 
    count(*) as country_row_count
from dbo.online_retail_II retail
group by retail.Country;
 
-- Check for leading or trailing whitespaces
select retail.Country
from dbo.online_retail_II retail
where retail.Country <> ltrim(rtrim(retail.Country));
 
-- Check for casing consistency
select retail.Country
from dbo.online_retail_II retail
where retail.Country <> upper(retail.Country);
 
select retail.Country
from dbo.online_retail_II retail
where retail.Country <> lower(retail.Country);
 
-- Check for placeholder/non-country values (e.g. "Unspecified", "European Community")
with cte_country_segmentation as (
    select retail.Country, 
        case 
            when retail.Country = 'Unspecified' then 'Unspecified country'
            when retail.Country = 'European Community' then 'Unspecified country in europe'
        end as country_bucketing
    from dbo.online_retail_II retail
)
select cte_country_segmentation.country_bucketing, 
    count(*) row_count
from cte_country_segmentation 
where cte_country_segmentation.country_bucketing is not null
group by cte_country_segmentation.country_bucketing;
 
-- Check the total count of distinct countries
select count(distinct retail.Country)
from dbo.online_retail_II retail;
 
 
/*
================================================================================
FULL-ROW DUPLICATE CHECK
================================================================================
*/
 
-- Check for exact duplicate rows across every column
select retail.Country, 
    retail.Customer_ID, 
    retail.Description, 
    retail.Invoice, 
    retail.InvoiceDate, 
    retail.Price, 
    retail.Quantity, 
    retail.StockCode, 
    count(*) duplicate_count
from dbo.online_retail_II retail
group by retail.Country, 
    retail.Customer_ID, 
    retail.Description, 
    retail.Invoice, 
    retail.InvoiceDate, 
    retail.Price, 
    retail.Quantity, 
    retail.StockCode
having count(*) > 1;
 
 
/*
================================================================================
OVERALL ROW COUNTS
================================================================================
*/
 
-- Check the non-null row count for every column, in one row
select 
    count(retail.Invoice) Invoice_count,
    count(retail.StockCode) StockCode_count,
    count(retail.Description) Description_count,
    count(retail.Quantity) Quantity_count,
    count(retail.InvoiceDate) InvoiceDate_count,
    count(retail.Price) Price_count,
    count(retail.Customer_ID) Customer_ID_count,
    count(retail.Country) Country_count
from dbo.online_retail_II retail;
 
-- Check the total number of rows in the dataset
select count(*)
from dbo.online_retail_II retail;