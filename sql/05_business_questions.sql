/*
================================================================================
END-TO-END RETAIL RETENTION ANALYSIS - BUSINESS QUESTIONS
================================================================================
*/

-- Q1 What are the top 10 products by total revenue?
select top 10 sales.description [Product Name], sum(sales.sales_amount) [Total Revenue Per Product]
from rpt.vw_valid_sales sales
where sales.customer_key <> -1 
group by sales.description
order by sum(sales.sales_amount) desc;

-- Q2 What are the top 10 products by total quantity?
select top 10 sales.description [Product Name], sum(sales.quantity) [Total Quantity per Product]
from rpt.vw_valid_sales sales
where sales.customer_key <> -1
group by sales.description
order by sum(sales.quantity) desc;

-- Q3 How many repeat customers are there per country?
select sales.country_name [Country], count(distinct cus.customer_id) [Number of Repeat Customers per Country]
from rpt.vw_valid_sales sales
inner join rpt.vw_customer_summary cus
	on sales.customer_id = cus.customer_id
where (sales.customer_key <> -1) and (cus.is_repeat_customer = 1)
group by sales.country_name
order by count(distinct cus.customer_id) desc;

-- Q4 What's the average time between a repeat customer's first and second order?
select avg(cus.days_to_second_order) [Average Time Between First and Second Order]
from rpt.vw_customer_summary cus
where (cus.customer_key <> -1) and (cus.is_repeat_customer = 1);

-- Q5 How is the time distributed across repeat customers - fast, medium, or slow?
select 
	case 
		when cus.days_to_second_order <= 30 then 'Fast'
		when cus.days_to_second_order >= 31 and cus.days_to_second_order <= 90 then 'Medium' else
		'Slow'
	end [Customer Time Distribution], 
	count(distinct cus.customer_id) [Total Number of Repeat Customers]
from rpt.vw_customer_summary cus
where (cus.customer_key <> -1) and (cus.is_repeat_customer = 1)
group by 
	case 
		when cus.days_to_second_order <= 30 then 'Fast'
		when cus.days_to_second_order >= 31 and cus.days_to_second_order <= 90 then 'Medium' else
		'Slow'
	end;

-- Q6 How much total revenue comes from repeat customers vs one-time customers, and what % of the grand total does each represent?
select 
	case when cus.is_repeat_customer = 1 then 'Repeat Customer' else 'One-Time Customer' end [Customer Categorization], 
	sum(cus.total_revenue) [Total Revenue per Customer Category],
	sum(cus.total_revenue) * 100 / sum(sum(cus.total_revenue)) over () [Percentage of Grand Total Revenue]
from rpt.vw_customer_summary cus
where (cus.customer_key <> -1)
group by case when cus.is_repeat_customer = 1 then 'Repeat Customer' else 'One-Time Customer' end;

-- Q7 What is the AOV (total revenue / total orders) and the CLV proxy (total revenue / number of customers) for each customer_segment?
select 
	cus.customer_segment,
	(sum(cus.total_revenue) / sum(cus.order_count)) [Average Order Value / AOV], 
	(sum(cus.total_revenue) / count(cus.customer_id)) [Customer Lifetime Value / CLV]
from rpt.vw_customer_summary cus
where (cus.customer_key <> -1)
group by cus.customer_segment;

-- Q8 In one result row, show gross Sale revenue, net valid revenue (from the view), and the value of every non-Sale transaction type
with cte_gross_rev as (
	select sum(fs.sales_amount) [Gross Sale Revenue]
	from fact.sales fs
	where fs.transaction_type = 'Sale'
), 
cte_net_rev as (
	select sum(sales.sales_amount) [Net Revenue]
	from rpt.vw_valid_sales sales
), 
cte_nonsale_inv_value as (
	select sum(fs.sales_amount) [Non-Sale Revenue]
	from fact.sales fs
	where fs.transaction_type <> 'Sale'
)
select 
	c1.[Gross Sale Revenue], 
	c2.[Net Revenue], 
	c3.[Non-Sale Revenue]
from cte_gross_rev c1
cross join cte_net_rev c2
cross join cte_nonsale_inv_value c3;

-- Q9 Cohort analysis: revenue by cohort month and months since first purchase
select 
	format(cus.first_order_date, 'yyyy-MM') [Cohort Month],
	datediff(month, cus.first_order_date, sales.full_date) [Months since first purchase],
	sum(sales.sales_amount) [Revenue]
from rpt.vw_valid_sales sales
inner join rpt.vw_customer_summary cus
	on sales.customer_id = cus.customer_id
where cus.customer_key <> -1
group by 
	format(cus.first_order_date, 'yyyy-MM'), 
	datediff(month, cus.first_order_date, sales.full_date)
order by 
	[Cohort Month], 
	[Months since first purchase];

-- Q9b Cohort analysis (pivot): active customers by cohort month and months since first purchase
with cohort as (
	select 
		format(cus.first_order_date, 'yyyy-MM') [Cohort Month],
		datediff(month, cus.first_order_date, sales.full_date) [Months Since the First Purchase],
		count(distinct sales.customer_id) [Active Customers]
	from rpt.vw_valid_sales sales
	inner join rpt.vw_customer_summary cus
		on sales.customer_id = cus.customer_id
	where cus.customer_key <> -1
	group by format(cus.first_order_date, 'yyyy-MM'), datediff(month, cus.first_order_date, sales.full_date)
)
select 
	[Cohort Month], 
	[0], [1], [2], [3], [4], [5], [6], [7], [8], [9], [10], [11], [12]
from cohort
pivot (
	sum([Active Customers])
	for [Months Since the First Purchase] in ([0], [1], [2], [3], [4], [5], [6], [7], [8], [9], [10], [11], [12])
) as piv
order by [Cohort Month];
