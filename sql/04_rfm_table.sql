create procedure rpt.calculateRFMtable
as 
begin
	-- Calculating the RFM Table for customers --
	-- Grain: one row per customer, with the three RFM inputs needed for clustering.
	-- Guest checkouts (customer_key = -1) are excluded throughout.

	-- STEP 1: Calculating each customer's most recent order date (their own "last seen" point)
	with cte_recent_order_date_customer as (
		select ord.customer_id, max(ord.order_date) [Most Recent Order Date per Customer]
		from rpt.vw_orders ord
		where ord.customer_key <> -1
		group by ord.customer_id
	),
	-- STEP 2: The single latest order date across the whole dataset (our stand-in for "today", since this is historical data)
	cte_latest_order_date as (
		select max(ord.order_date) [Latest Order Date]
		from rpt.vw_orders ord
	)
	-- Recency: What is the number of days between a customer's last order and the dataset's most recent date; lower it is, the more recently active
	-- Frequency: How many orders this customer has placed in total
	-- Monetary: The total revenue this customer has generated
	select 
		datediff(day, c1.[Most Recent Order Date per Customer], c2.[Latest Order Date]) as [Recency],
		cus.order_count as [Frequency], 
		cus.total_revenue as [Monetary]
	from cte_recent_order_date_customer c1
	cross join cte_latest_order_date c2       -- applies the single dataset-wide date to every customer row
	inner join rpt.vw_customer_summary cus
		on c1.customer_id = cus.customer_id
	where cus.customer_key <> -1 -- redundant with the CTE's own filter, but kept explicit here too
	order by cus.total_revenue desc;
end;
