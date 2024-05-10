--Inspect data 
SELECT * FROM [RFM].[dbo].[Auto_Sales_data]

--Add year_id and month_id column
ALTER TABLE [RFM].[dbo].[Auto_Sales_data]
ADD year_id INT,
    month_id INT;

UPDATE [RFM].[dbo].[Auto_Sales_data]
SET year_id = YEAR(CONVERT(DATE, ORDERDATE, 103)),
    month_id = MONTH(CONVERT(DATE, ORDERDATE, 103));

--Save new dataset (with added columns year_id and month_id) as a flat csv file for later analysis in Tableau

--Checking unique values
select distinct status from [RFM].[dbo].[Auto_Sales_data]
select distinct year_id from [RFM].[dbo].[Auto_Sales_data]
select distinct productline from [RFM].[dbo].[Auto_Sales_data]
select distinct country from [RFM].[dbo].[Auto_Sales_data]
select distinct dealsize from [RFM].[dbo].[Auto_Sales_data]

--Grouping sales by productline
select PRODUCTLINE, sum(cast(sales as decimal)) Revenue
from Auto_Sales_data
group by PRODUCTLINE
order by 2 desc

--Grouping sales by year
select year_id, sum(cast(sales as decimal)) Revenue
from Auto_Sales_data
group by year_id
order by 2 desc

--We see that 2020 is much worse than previous years so we check if they operate whole year and if we have data for all months and we see we have data for only 5 months in year 2020.
--When we check for years 2018 and 2019 we see they operated in all months during 2018 and 2019
select distinct month_id from Auto_Sales_data
where year_id = 2020

--Grouping sales by dealsize
--We can see that the most revenue came from medium deals 
select DEALSIZE, sum(cast(sales as decimal)) Revenue
from Auto_Sales_data
group by DEALSIZE
order by 2 desc

--Now we check what was the best month for sale in specific year and how much they earned during that month?
select month_id,sum(cast(sales as decimal)) Revenue, count(ordernumber) Frequency
from Auto_Sales_data
where year_id = 2018 -- change to see for other years
group by month_id 
order by 2 desc

--In both years 2018 and 2019, for wich we have whole years data, November was best month. Now we check what is the most selled product in November?
--We see that Classic Cars are leaders in both year 2018 and 2019
select month_id,productline, sum(cast(sales as decimal)) Revenue, count(ordernumber) Frequency
from Auto_Sales_data
where year_id = 2018 and month_id=11 -- change year_id to see for other year
group by month_id,productline
order by 3 desc

--Who is the best customer? RFM Analysis

SELECT
    customername,
    SUM(CAST(sales AS DECIMAL)) AS MonetaryValue,
    AVG(CAST(sales AS DECIMAL)) AS AvgMonetaryValue,
    COUNT(ordernumber) AS Frequency,
    MAX(TRY_CONVERT(DATE, orderdate, 103)) AS last_order_date,
    (SELECT MAX(TRY_CONVERT(DATE, orderdate, 103)) FROM Auto_Sales_data) AS max_order_date,--We check also max order date in entire dataset, so we can calculate diference between max_order_date and last_order_date for each customer becuase that represent Recency in our RFM analysis
    DATEDIFF(DAY, MAX(TRY_CONVERT(DATE, orderdate, 103)), (SELECT MAX(TRY_CONVERT(DATE, orderdate, 103)) FROM Auto_Sales_data)) AS Recency --In DATEDIFF function for interval we chose DD that is interval in days and for start interval is last order for each customer and end interval is last order of whole dataset and difference is Recency
from Auto_Sales_data
FROM
    Auto_Sales_data
GROUP BY
    customername

-- We are getting 89 records. Now we want to do ntile and group these records in for equal groups.
--We put whole previous query in CTE and than fo NTILE function

--Saved everything as temp table 
drop table if exists #rfm;
with rfm as 
(
	SELECT
		customername,
		SUM(CAST(sales AS DECIMAL)) AS MonetaryValue,
		AVG(CAST(sales AS DECIMAL)) AS AvgMonetaryValue,
		COUNT(ordernumber) AS Frequency,
		MAX(TRY_CONVERT(DATE, orderdate, 103)) AS last_order_date,
		(SELECT MAX(TRY_CONVERT(DATE, orderdate, 103)) FROM Auto_Sales_data) AS max_order_date,--We check also max order date in entire dataset, so we can calculate diference between max_order_date and last_order_date for each customer becuase that represent Recency in our RFM analysis
		DATEDIFF(DAY, MAX(TRY_CONVERT(DATE, orderdate, 103)), (SELECT MAX(TRY_CONVERT(DATE, orderdate, 103)) FROM Auto_Sales_data)) AS Recency --In DATEDIFF function for interval we chose DD that is interval in days and for start interval is last order for each customer and end interval is last order of whole dataset and difference is Recency
	from Auto_Sales_data
	GROUP BY
		customername
), 
rfm_calc as --here we add CTE including previous query and adding ntile
(
	select r.*,
	NTILE(4) OVER (ORDER BY Recency) rfm_recency,--we order customers in 4 groups based on recency, so last time they bought products,the closer the date of customer last purchase is to max_order_date in dataset, the lower the ntile group (rfm_recency) number is 
	NTILE(4) OVER (ORDER BY Frequency) rfm_frequency,--we order customer in 4 groups based on frequency, so how often they were buying products, the higher the frequency the higher ntile group (rfm_freqency) number is 
	NTILE(4) OVER (ORDER BY MonetaryValue) rfm_monetary -- we order customer based on monetary, so how much money they spent on products, the more money they spent the hire ntile (rfm_monetary) group number is
	from rfm r
)
--
select c.*,rfm_recency+rfm_frequency+rfm_monetary as rfm_cell,
cast(rfm_recency as varchar) + cast(rfm_frequency as varchar) + cast(rfm_monetary as varchar) as rfm_cell_string
into #rfm --here we  are saving final CTE and our results in temp table called #rfm
from rfm_calc as c

--Now we can just select from temp table 
select * from #rfm

--Now we are doing segmentations using CASE statement
--Later after segmentation we know which customer to target with witch marketing program
select CUSTOMERNAME, rfm_recency,rfm_frequency,rfm_monetary,
	case 
		when rfm_cell_string in (111,112,121,122,123,132,211,212,114,141) then 'lost customers' 
		when rfm_cell_string in (133,134,143,144,244,334,343,344) then 'slipping away' --big spenders who haven't purchased lately, they buy a lot and amount is big but they did not bought for long time so frequency group is smaller
		when rfm_cell_string in (311,411,331) then 'new customers' --recency is 3 so they recently bought something but freqeuncy is 1 they only bought once and monetary is 1 so they only bought once but they have potential to become new cusotmers
		when rfm_cell_string in (222,223,233,322) then 'potential customers'
		when rfm_cell_string in (323,333,321,422,332,432) then 'loyal customers' -- recency 4 and frequency 4 so they buy frequentily and also monetary 4 so they buy a lot
	end as rfm_segmentation_groups
from #rfm

--What products are msot often sold together?
--We can see that ordernumber is not unique, on one order there can be multiple line items (rn>1)
select ordernumber, count(*) as rn
from Auto_Sales_data
where status = 'Shipped'
group by ordernumber

--We will select all ordernumbers where rn=2 so we would like to see which two products are often sold together?

SELECT
    distinct ordernumber,
    STUFF(
        (SELECT ',' + PRODUCTCODE
         FROM Auto_Sales_data as p
         WHERE ordernumber IN
               (SELECT ordernumber
                FROM (SELECT ordernumber, COUNT(*) AS rn
                      FROM Auto_Sales_data AS p
                      WHERE status = 'Shipped'
                      GROUP BY ordernumber) AS sub
                WHERE rn = 2)
				and p.ORDERNUMBER = s.ORDERNUMBER
         FOR XML PATH('')), 1, 1, '') AS ProductCodes ----with adding stuff and 1,1,'' we are using stuff function and replace first character on position 1 with nothing so we drop first comma from xml and convert xml to string
FROM
    Auto_Sales_data AS s
order by 2 desc
