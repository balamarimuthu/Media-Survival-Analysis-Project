-- Ad-Hoc Request 1: Monthly Circulation Drop Check
-- Generate a report showing the top 3 months (2019–2024) where any city recorded the sharpest month-over-month decline in net_circulation.
WITH date_converted_sales AS (
    SELECT
        t1.Net_circulation,
        t2.city,
        CASE
            WHEN TRIM(t1.sale_month) LIKE '%/%' THEN SUBSTRING_INDEX(TRIM(t1.sale_month), '/', 1)  
            WHEN TRIM(t1.sale_month) LIKE '%-%' THEN CONCAT('20', SUBSTRING_INDEX(TRIM(t1.sale_month), '-', -1))
        END AS sales_year,
        CASE
            WHEN TRIM(t1.sale_month) LIKE '%/%' THEN SUBSTRING_INDEX(TRIM(t1.sale_month), '/', -1)
            WHEN TRIM(t1.sale_month) LIKE '%-%' THEN
                CASE LOWER(SUBSTRING_INDEX(TRIM(t1.sale_month), '-', 1))   -- CONVERT INTO LOWERCASE
                    WHEN 'jan' THEN 1  WHEN 'feb' THEN 2  WHEN 'mar' THEN 3
                    WHEN 'apr' THEN 4  WHEN 'may' THEN 5  WHEN 'jun' THEN 6
                    WHEN 'jul' THEN 7  WHEN 'aug' THEN 8  WHEN 'sep' THEN 9
                    WHEN 'oct' THEN 10 WHEN 'nov' THEN 11 WHEN 'dec' THEN 12
                END
        END AS sales_month
    FROM
        fact_print_sales AS t1
    JOIN
        dim_city AS t2 ON t1.city_id = t2.city_id
),
monthly_circulation AS (
    SELECT
        sales_year,
        sales_month,
        city,
        SUM(Net_circulation) AS total_circulation
    FROM
        date_converted_sales
    WHERE
        sales_year BETWEEN 2019 AND 2024
    GROUP BY
        sales_year, sales_month, city
),
mom_change AS (
    SELECT
        sales_year,
        sales_month,
        city,
        total_circulation,
        LAG(total_circulation, 1, 0) OVER (PARTITION BY city ORDER BY sales_year, sales_month) AS previous_month_circulation
    FROM
        monthly_circulation
)
SELECT
    -- Added a 'previous_month' column for clarity
    DATE_FORMAT((MAKEDATE(sales_year, 1) + INTERVAL sales_month - 1 MONTH) - INTERVAL 1 MONTH, '%Y-%m') AS previous_month,
    -- Renamed the original 'month' column
    DATE_FORMAT(MAKEDATE(sales_year, 1) + INTERVAL sales_month - 1 MONTH, '%Y-%m') AS current_month,
    city,
    previous_month_circulation,
    total_circulation,
    (previous_month_circulation - total_circulation) AS net_circulation_decline
FROM
    mom_change
WHERE
    previous_month_circulation > total_circulation
ORDER BY
    net_circulation_decline DESC
LIMIT 5;

-- Ad-Hoc Request 2: Ad Category Contribution
-- Identify ad categories that contributed > 50% of total yearly ad revenue.
-- (Modified to find the top contributor per year, as no category was > 50%)
with clean_yearly_revenue as(
select
	case
		when locate('-', t1.time_quarter)=5 then left (t1.time_quarter,4)
        when locate('-',t1.time_quarter)=3 then right (t1.time_quarter,4)
        else right(t1.time_quarter,4)
	end as ad_year,
    t2.standard_ad_category,
    sum(
		case
			when t1.currency='USD'  then t1.ad_revenue *88.14
            when t1.currency='EUR'  then t1.ad_revenue * 103.07
            when t1.currency in ('INR' ,'IN RUPEES') then t1.ad_revenue
            else t1.ad_revenue
		end
) as category_revenue_inr
from 
	fact_ad_revenue as t1
join 
	dim_ad_category as t2 on t1.ad_category = t2.ad_category_id
    group by
		ad_year , t2.standard_ad_category
)
 select
	ad_year,
    standard_ad_category,
    category_revenue_inr,
    round(		
		(category_revenue_inr/ sum(category_revenue_inr) over (partition by ad_year)) *100,
        2
	) as pct_of_year_total
from
	clean_yearly_revenue
order by
	ad_year, pct_of_year_total desc;
-- Ad-Hoc Request 3: Print Efficiency Ranking
-- For 2024, rank cities by print efficiency = net_circulation / copies_printed. Return top 5.
with city_efficinecy_2024 as(
select
	t2.city ,
    sum(t1.Net_Circulation) as total_net_calculation,
    sum(t1.Copies_Sold) as total_copies_sold,
    -- calcualte print efficiency
    (sum(t1.Net_Circulation)/sum(t1.Copies_Sold)) as efficiency_ratio
    from
    fact_print_sales as t1
    join
    dim_city as t2 on t1.City_ID =t2.city_id
    where 
    case 
		when trim(t1.sale_month) like "%/%" then SUBSTRING_INDEX(trim(t1.sale_month),'/',1)
        when trim(t1.sale_month) like "%-%" then concat(20,SUBSTRING_INDEX(trim(t1.sale_month),'-',-1))
	end = '2024'
    
group by 
	t2.city
)
select
city
total_copies_sold,
total_net_calculation,
efficiency_ratio,
-- addrank based effiecienccy ratio
rank() OVER(ORDER BY efficiency_ratio desc) as efficiency_rank_2024
from
city_efficinecy_2024
order by 
efficiency_rank_2024
limit 5;
-- Ad-Hoc Request 4: Internet Penetration Change
-- For each city, compute the change in internet penetration from Q1-2021 to Q4-2021 and identify the city with the highest improvement.
with q1_rates as(
select
	city_id ,
    internet_penetration as internet_penetration_q1
    from
    fact_city_readiness
    where 
    time_quarter ='2021-Q1'
),
q4_rates as (
	select
    city_id,
        internet_penetration as internet_penetration_q4
	from
    fact_city_readiness
    where
    time_quarter ='2021-Q4'
)
select
	c.city,
    q1.internet_penetration_q1,
    q4.internet_penetration_q4,
    (q4.internet_penetration_q4 -q1.internet_penetration_q1) as delta_internet_rate
    
from
	q1_rates as q1
join 
	q4_rates as q4 on q1.city_id =q4.city_id
    
join
	dim_city as c on q1.city_id =c.city_id
order by
delta_internet_rate desc
limit 3;

-- Ad-Hoc Request 5: Strictly Decreasing Trends
-- Find cities where both net_circulation and ad_revenue decreased every year from 2019 through 2024 (strictly decreasing sequences).
-- Step 1: Aggregate yearly circulation for each city
WITH yearly_circulation AS (
    SELECT
        t1.City_ID,
        CASE
            WHEN TRIM(t1.sale_month) LIKE '%/%' THEN SUBSTRING_INDEX(TRIM(t1.sale_month), '/', 1)
            WHEN TRIM(t1.sale_month) LIKE '%-%' THEN CONCAT('20', SUBSTRING_INDEX(TRIM(t1.sale_month), '-', -1))
        END AS metric_year,
        SUM(t1.Net_Circulation) AS yearly_net_circulation
    FROM
        fact_print_sales AS t1
    GROUP BY
        t1.City_ID, metric_year
),
-- Step 2: Aggregate yearly ad revenue for each city by linking through edition_id
yearly_revenue AS (
    SELECT
        fps.City_ID,
        CASE
            WHEN LOCATE('-', far.time_quarter) = 5 THEN LEFT(far.time_quarter, 4)
            WHEN LOCATE('-', far.time_quarter) = 3 THEN RIGHT(far.time_quarter, 4)
            ELSE RIGHT(far.time_quarter, 4)
        END AS metric_year,
        SUM(
            CASE
                WHEN far.currency = 'USD' THEN far.ad_revenue * 83.0
                WHEN far.currency = 'EUR' THEN far.ad_revenue * 90.0
                WHEN far.currency IN ('INR', 'IN RUPEES') THEN far.ad_revenue
                ELSE far.ad_revenue
            END
        ) AS yearly_ad_revenue
    FROM fact_ad_revenue AS far
    -- Join through fact_print_sales to get the City_ID
    JOIN fact_print_sales AS fps ON far.edition_id = fps.edition_id
    GROUP BY
        fps.City_ID, metric_year
),
-- Step 3: Combine the two aggregated datasets
yearly_aggregated_data AS (
    SELECT
        yc.City_ID,
        yc.metric_year,
        yc.yearly_net_circulation,
        yr.yearly_ad_revenue
    FROM yearly_circulation AS yc
    JOIN yearly_revenue AS yr ON yc.City_ID = yr.City_ID AND yc.metric_year = yr.metric_year
    WHERE
        yc.metric_year BETWEEN '2019' AND '2024'
),
-- Step 4: Compare each year to the previous year using LAG()
yearly_comparison AS (
    SELECT
        City_ID,
        metric_year,
        yearly_net_circulation,
        yearly_ad_revenue,
        LAG(yearly_net_circulation, 1) OVER (PARTITION BY City_ID ORDER BY metric_year) AS prev_year_circ,
        LAG(yearly_ad_revenue, 1) OVER (PARTITION BY City_ID ORDER BY metric_year) AS prev_year_rev
    FROM yearly_aggregated_data
),
-- Step 5: Check the trend for each city
trend_check AS (
    SELECT
        City_ID,
        COUNT(DISTINCT metric_year) AS total_years,
        SUM(CASE WHEN yearly_net_circulation < prev_year_circ THEN 1 ELSE 0 END) AS circ_decrease_count,
        SUM(CASE WHEN yearly_ad_revenue < prev_year_rev THEN 1 ELSE 0 END) AS rev_decrease_count
    FROM yearly_comparison
    WHERE metric_year > '2019'
    GROUP BY City_ID
)
-- Step 6: Join the yearly data with the trend flags for the final report
SELECT
    c.city AS city_name,
    y.metric_year AS year,
    y.yearly_net_circulation,
    y.yearly_ad_revenue,
    CASE
        WHEN tc.total_years = 6 AND tc.circ_decrease_count = 5 THEN 'Yes'
        ELSE 'No'
    END AS is_declining_print,
    CASE
        WHEN tc.total_years = 6 AND tc.rev_decrease_count = 5 THEN 'Yes'
        ELSE 'No'
    END AS is_declining_ad_revenue,
    CASE
        WHEN tc.total_years = 6 AND tc.circ_decrease_count = 5 AND tc.rev_decrease_count = 5 THEN 'Yes'
        ELSE 'No'
    END AS is_declining_both
FROM
    yearly_aggregated_data AS y
JOIN
    dim_city AS c ON y.City_ID = c.city_id
LEFT JOIN
    trend_check AS tc ON y.City_ID = tc.City_ID
ORDER BY
    city_name, year;
-- Ad-Hoc Request 6: Digital Readiness Outlier
-- In 2021, identify the city with the highest digital readiness score but among the bottom 3 in digital pilot engagement.
with city_scores_2021 as(
select 
	cr.city_id,
    avg(cr.smartphone_penetration +cr.internet_penetration+cr.literacy_rate/3) as readiness_score_2021,
    sum(dp.users_reached+dp.downloads_or_accesses) as engagement_metric_2021
from
	fact_city_readiness as cr
join fact_digital_pilot as dp on cr.city_id =dp.city_id
where
	left (trim(cr.time_quarter),4)='2021' and 
    left(trim(dp.launch_month),4)='2021'
group by
	cr.city_id
),
city_ranks as (
	select
		city_id,
        readiness_score_2021,
        engagement_metric_2021,
        rank() over (order by readiness_score_2021 desc) as reaadiness_rank_desc,
        rank() over (order by engagement_metric_2021 asc) as engagement_rank_asc
	from
		city_scores_2021
)
select
	c.city as city_name,
    cr.readiness_score_2021,
    cr.engagement_metric_2021,
    cr.reaadiness_rank_desc,
    cr.engagement_rank_asc,
    case
		when cr.city_id=(
        SELECT city_id from city_ranks
        where engagement_rank_asc <= 3
        order by reaadiness_rank_desc asc
        limit 1
	) then "yes"
    else "no"
    end as is_outlier
from
city_ranks as cr
join
dim_city as c on cr.city_id =c.city_id
order by 
reaadiness_rank_desc;
