--kpi
SELECT 
--TOTAL COMPLETED ORDERS
COUNT(DISTINCT o.order_id) as total_completed_orders,
--TOTAL REVENUE
SUM(ot.quantity * ot.unit_price) as total_revenue,
-- TOTAL UNIT SOLD
SUM(ot.quantity) as total_unit_sold,
-- AVERAGE ORDER VALUE
ROUND(SUM(ot.quantity * ot.unit_price) / COUNT(DISTINCT o.order_id), 2) as avg_order_value,
-- AVERAGE UNIT PER ORDER
ROUND(SUM(ot.quantity) / COUNT(DISTINCT o.order_id), 2) as avg_unit_sold
FROM order_items ot JOIN order_receipts o ON ot.order_id = o.order_id
WHERE o.order_status = 'Completed';

--COMPLETED VS UNSUCCESSFUL ORDERS
--number of completed orders
WITH orders_completed as (
SELECT COUNT(DISTINCT order_id) as completed_orders
FROM order_receipts 
WHERE order_status = 'Completed'
),
--total returned and cancelled orders
unsuccessful as (
SELECT COUNT(DISTINCT order_id) as unsuccessful_orders
FROM order_receipts 
WHERE order_status IN ('Returned', 'Cancelled')
),
--overall total orders
overall_transaction as (
SELECT COUNT(DISTINCT order_id) as orders FROM order_receipts
)
SELECT ROUND((oc.completed_orders::NUMERIC / ov.orders) * 100, 2) as completed_orders,
ROUND((u.unsuccessful_orders::NUMERIC / ov.orders) * 100, 2) as unsuccessful_orders
FROM orders_completed oc, unsuccessful u, overall_transaction ov;


--MONTHLY KPIs
SELECT DATE_TRUNC('month', o.order_date) as sale_month,
COALESCE(COUNT(DISTINCT CASE WHEN o.order_status = 'Completed' THEN o.order_id END), 0) as total_completed_orders,
COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity * ot.unit_price END), 0) as total_revenue,
COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity END), 0) as total_unit_sold,
COALESCE(COUNT(DISTINCT CASE WHEN o.order_status = 'Completed' THEN c.customer_id END), 0) as total_customer,
ROUND(COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity * ot.unit_price END), 0) / NULLIF(COUNT(DISTINCT CASE WHEN o.order_status = 'Completed' THEN o.order_id END), 0) ,2) as avg_order_value,
COALESCE(COUNT(DISTINCT CASE WHEN o.order_status = 'Returned' THEN o.order_id END), 0) as total_returned,
COALESCE(COUNT(DISTINCT CASE WHEN o.order_status = 'Cancelled' THEN o.order_id END), 0) as total_cancelled
FROM order_receipts o LEFT JOIN order_items ot ON o.order_id = ot.order_id 
LEFT JOIN customer c ON c.customer_id = o.customer_id
GROUP BY DATE_TRUNC('month', o.order_date)
ORDER BY sale_month;

--NEW CUSTOMER PER MONTH
WITH first_purchase AS (
    SELECT
        o.customer_id,
        DATE_TRUNC('month', MIN(o.order_date)) AS first_purchase_month
    FROM order_receipts o
    WHERE o.order_status = 'Completed'
    GROUP BY o.customer_id
)
SELECT
    first_purchase_month AS month,
    COALESCE(COUNT(DISTINCT customer_id),0) AS new_customer
FROM first_purchase
GROUP BY first_purchase_month
ORDER BY first_purchase_month;


--COMPARING MONTHS WITH HIGHEST REVENUE AND LOWER REVENUE
SELECT p.category,
COUNT(DISTINCT CASE WHEN o.order_status = 'Completed' AND o.order_date BETWEEN '2026-10-01' AND '2026-10-31' THEN ot.order_items_id END) as oct_total_purchased,
SUM(CASE WHEN o.order_status = 'Completed' AND o.order_date BETWEEN '2026-10-01' AND '2026-10-31' THEN ot.quantity ELSE 0 END) as oct_total_unit_sold,
SUM(CASE WHEN o.order_status = 'Completed' AND o.order_date BETWEEN '2026-10-01' AND '2026-10-31' THEN ot.quantity * ot.unit_price ELSE 0 END) as oct_total_revenue,
COUNT(DISTINCT CASE WHEN o.order_status = 'Completed' AND o.order_date BETWEEN '2026-11-01' AND '2026-11-30' THEN ot.order_items_id END) as nov_total_purchased,
SUM(CASE WHEN o.order_status = 'Completed' AND o.order_date BETWEEN '2026-11-01' AND '2026-11-30' THEN ot.quantity ELSE 0 END) as nov_total_unit_sold,
SUM(CASE WHEN o.order_status = 'Completed' AND o.order_date BETWEEN '2026-11-01' AND '2026-11-30' THEN ot.quantity * ot.unit_price ELSE 0 END) as nov_total_revenue
FROM product p JOIN order_items ot ON p.product_id = ot.product_id
JOIN order_receipts o ON o.order_id = ot.order_id
GROUP BY p.category


--MONTH-TO-MONTH REVENUE PERCENTAGE GROWTH
WITH monthly_revenue as (
SELECT DATE_TRUNC('month', o.order_date) as sale_month, SUM(ot.quantity * ot.unit_price) as total_revenue
FROM order_receipts o JOIN order_items ot ON o.order_id = ot.order_id
WHERE o.order_status = 'Completed'
GROUP BY DATE_TRUNC('month', o.order_date)
),
lagged as (
SELECT sale_month, total_revenue as this_month_revenue,
LAG(total_revenue) OVER(ORDER BY sale_month) as previous_month_revenue
FROM monthly_revenue
)
SELECT sale_month, this_month_revenue, previous_month_revenue,
CASE 
WHEN previous_month_revenue = 0 OR previous_month_revenue IS NULL THEN NULL
ELSE ROUND((this_month_revenue - previous_month_revenue) / previous_month_revenue * 100, 2)
END as growth_percentage
FROM lagged;


--MONTHLY CATEGORY REVENUE PERCENTAGE
WITH monthly as (
SELECT DATE_TRUNC('month', o.order_date) as sale_month, p.category,
COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity * ot.unit_price END), 0) as total_revenue
FROM order_receipts o LEFT JOIN order_items ot ON o.order_id = ot.order_id
LEFT JOIN product p ON p.product_id = ot.product_id
GROUP BY DATE_TRUNC('month', o.order_date), p.category
),
overall_rev as (
SELECT DATE_TRUNC('month', o.order_date) as sale_months, SUM(ot.quantity * ot.unit_price) as overall_revenue
FROM order_receipts o JOIN order_items ot ON o.order_id = ot.order_id
WHERE o.order_status = 'Completed'
GROUP BY DATE_TRUNC('month', o.order_date)
)
SELECT m.sale_month, m.category, m.total_revenue, ov.overall_revenue,
ROUND((m.total_revenue::NUMERIC / ov.overall_revenue) * 100, 2) as revenue_percentage
FROM monthly m JOIN overall_rev ov ON m.sale_month = ov.sale_months
ORDER BY m.sale_month, revenue_percentage DESC



-- CENTRAL VISAYAS HIGH COMPLETED ORDER BUT LOW REVENUE VS CENTRAL LUZON LOW COMPLETED ORDER BUT HIGH REVENUE
SELECT p.category,
COALESCE(SUM(CASE WHEN c.region = 'Central Visayas' THEN ot.quantity END), 0) as central_visayas_total,
COALESCE(SUM(CASE WHEN c.region = 'Central Luzon' THEN ot.quantity END), 0) as central_luzon_total
FROM product p LEFT JOIN order_items ot ON p.product_id = ot.product_id
LEFT JOIN order_receipts o ON o.order_id = ot.order_id
LEFT JOIN customer c ON c.customer_id = o.customer_id
WHERE o.order_status = 'Completed'
GROUP BY p.category



--CATEGORY KPIs
WITH category_info as (
SELECT 
    p.category, 
    COALESCE(SUM(ot.quantity * ot.unit_price), 0) AS total_revenue,
	COALESCE(SUM(ot.quantity), 0) AS total_unit_sold,
	NULLIF(COUNT(DISTINCT ot.order_id), 0) as total_purchased,
	ROUND( SUM(ot.quantity * ot.unit_price) / COUNT(DISTINCT o.order_id),2) as avg_order_value
FROM product p
JOIN order_items ot 
    ON p.product_id = ot.product_id
JOIN order_receipts o 
    ON o.order_id = ot.order_id
WHERE o.order_status = 'Completed'
GROUP BY p.category
ORDER BY total_revenue DESC
),
overall_rev as (
SELECT SUM(ot.quantity * ot.unit_price) as overall_revenue,
SUM(ot.quantity) as overall_sold
FROM order_items ot JOIN order_receipts o ON ot.order_id = o.order_id
WHERE o.order_status = 'Completed'
)
SELECT ci.category, ci.total_revenue, ci.total_unit_sold, ci.total_purchased, ci.avg_order_value,
ROUND((ci.total_revenue::NUMERIC / ov.overall_revenue) * 100, 2) as revenue_percentage,
ROUND((ci.total_unit_sold::NUMERIC / ov.overall_sold) * 100, 2) as unit_sold_percentage
FROM category_info ci CROSS JOIN overall_rev ov


--PRODUCT PERFORMANCE
--getting the total revenue of completed orders for each product 
WITH product_revenue as (
SELECT p.category, p.brand, p.product_name,
COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity * ot.unit_price END),0) as total_revenue,
COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity END), 0) as total_unit_sold
FROM product p LEFT JOIN order_items ot ON p.product_id = ot.product_id
LEFT JOIN order_receipts o ON o.order_id = ot.order_id
GROUP BY p.category, p.brand, p.product_name
ORDER BY total_revenue DESC
),
--getting the overall revenue for completed transaction
overall as (
SELECT SUM(ot.quantity * ot.unit_price) as overall_revenue
FROM order_items ot JOIN order_receipts o ON ot.order_id = o.order_id
WHERE o.order_status = 'Completed'
)
--getting the revenue percentage of each product name
SELECT pr.category, pr.brand, pr.product_name, pr.total_revenue, pr.total_unit_sold,
ROUND((pr.total_revenue::NUMERIC / ov.overall_revenue) * 100, 2) as revenue_percentage
FROM product_revenue pr CROSS JOIN overall ov;


--PHONE PRODUCTS REVENUE PERCENTAGE
WITH product_revenue as(
SELECT p.product_name,
COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity * ot.unit_price END), 0) as total_revenue
FROM product p LEFT JOIN order_items ot ON p.product_id = ot.product_id
LEFT JOIN order_receipts o ON o.order_id = ot.order_id
WHERE p.category = 'Phone'
GROUP BY p.product_name
),
phone_overall_rev as (
SELECT SUM(ot.quantity * ot.unit_price) as overall_revenue
FROM order_items ot JOIN order_receipts o ON ot.order_id = o.order_id
JOIN product p ON p.product_id = ot.product_id
WHERE o.order_status = 'Completed' AND p.category = 'Phone'
)
SELECT pr.product_name, pr.total_revenue, po.overall_revenue,
ROUND((pr.total_revenue::NUMERIC / po.overall_revenue) * 100, 2) as revenue_percentage
FROM product_revenue pr CROSS JOIN phone_overall_rev po


--PRODUCT UNIT SOLD PERCENTAGE
WITH product_unit as (
SELECT p.category, p.brand, p.product_name,
COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity END),0) as total_unit_sold
FROM product p LEFT JOIN order_items ot ON p.product_id = ot.product_id
LEFT JOIN order_receipts o ON o.order_id = ot.order_id
GROUP BY p.category, p.brand, p.product_name
ORDER BY total_unit_sold DESC
),
--getting the overall unit sold for completed transaction
overall as (
SELECT SUM(ot.quantity) as overall_unit
FROM order_items ot JOIN order_receipts o ON ot.order_id = o.order_id
WHERE o.order_status = 'Completed'
)
--getting the unit sold percentage of each product name
SELECT pu.category, pu.brand, pu.product_name, pu.total_unit_sold,
ROUND((pu.total_unit_sold::NUMERIC / ov.overall_unit) * 100, 2) as unit_sold_percentage
FROM product_unit pu CROSS JOIN overall ov;


--BRAND KPIs
WITH brand_info as (
SELECT p.brand, 
COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity * ot.unit_price END), 0) as total_revenue,
COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity END), 0) as total_unit_sold,
COALESCE(COUNT(DISTINCT CASE WHEN o.order_status = 'Completed' THEN o.order_id END), 0) as total_orders,
COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity * ot.unit_price END), 0) / NULLIF(COUNT(DISTINCT CASE WHEN o.order_status = 'Completed' THEN o.order_id END), 0) as avg_order_value
FROM product p LEFT JOIN order_items ot ON p.product_id = ot.product_id
LEFT JOIN order_receipts o ON o.order_id = ot.order_id
GROUP BY p.brand
),
overall_rev as (
SELECT SUM(ot.quantity * ot.unit_price) as overall_revenue,
SUM(ot.quantity) as overall_sold
FROM order_items ot JOIN order_receipts o ON ot.order_id = o.order_id
WHERE o.order_status = 'Completed'
)
SELECT bi.brand, bi.total_revenue, bi.total_unit_sold, bi.total_orders, ROUND(bi.avg_order_value, 2) as avg_order_value,
ROUND((bi.total_revenue::NUMERIC / ov.overall_revenue) * 100, 2) as revenue_percentage,
ROUND((bi.total_unit_sold::NUMERIC / ov.overall_sold) * 100, 2) as unit_sold_percentage
FROM brand_info bi CROSS JOIN overall_rev ov
ORDER BY bi.total_unit_sold DESC;

--TOP1 PRODUCT NAME PER BRANDS BY TOTAL UNIT SOLD
SELECT brand, product_name, total_unit_sold FROM(
SELECT p.brand, p.product_name, SUM(ot.quantity) as total_unit_sold,
ROW_NUMBER() OVER(PARTITION BY p.brand ORDER BY SUM(ot.quantity) DESC) as rankings
FROM product p JOIN order_items ot ON p.product_id = ot.product_id
JOIN order_receipts o ON o.order_id = ot.order_id
WHERE o.order_status = 'Completed'
GROUP BY p.brand, p.product_name
)
WHERE rankings = 1;


--TOTAL REVENUE OF CUSTOMER SEGMENT PER BRAND
SELECT p.brand, c.customer_segment,
COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity * ot.unit_price END), 0) as total_revenue
FROM product p LEFT JOIN order_items ot ON p.product_id = ot.product_id
LEFT JOIN order_receipts o ON o.order_id = ot.order_id
LEFT JOIN customer c ON c.customer_id = o.customer_id
GROUP BY p.brand, c.customer_segment
ORDER BY p.brand;

--RANKING OF BRAND BY REVENUE
SELECT p.brand, COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity * ot.unit_price END), 0) as total_revenue
FROM product p LEFT JOIN order_items ot ON p.product_id = ot.product_id
LEFT JOIN order_receipts o ON o.order_id = ot.order_id
GROUP BY p.brand
ORDER BY total_revenue DESC;


--PRODUCT NAME REVENUE PERCENTAGE WITH THEIR BRANDS
WITH brands_order as (
SELECT p.brand, p.product_name, 
COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity * ot.unit_price END), 0) as total_revenue
FROM product p LEFT JOIN order_items ot ON p.product_id = ot.product_id
LEFT JOIN order_receipts o ON o.order_id = ot.order_id
GROUP BY p.brand, p.product_name
),
overall_brands as (
SELECT p.brand, SUM(ot.quantity * ot.unit_price) as overall_revenue
FROM product p JOIN order_items ot ON p.product_id = ot.product_id
JOIN order_receipts o ON o.order_id = ot.order_id
WHERE o.order_status = 'Completed'
GROUP BY p.brand
)
SELECT bo.brand, bo.product_name, bo.total_revenue, ov.overall_revenue,
ROUND((bo.total_revenue::NUMERIC / ov.overall_revenue) * 100, 2) as product_rev_percentage
FROM brands_order bo JOIN overall_brands ov ON bo.brand = ov.brand
ORDER BY bo.brand, bo.total_revenue DESC;


--PRODUCT NAME REVENUE IN EACH REGION
WITH product_region as (
SELECT p.product_name, c.region
FROM
(SELECT DISTINCT product_name
FROM product
)p
CROSS JOIN
(
SELECT DISTINCT region
FROM customer
)c
),
transactions as(
SELECT p.product_name, c.region, NULLIF(COUNT(DISTINCT o.order_id),0) as total_orders
FROM product p JOIN order_items ot ON p.product_id = ot.product_id
JOIN order_receipts O ON o.order_id = ot.order_id
JOIN customer c ON c.customer_id = o.customer_id
WHERE o.order_status = 'Completed'
GROUP BY p.product_name, c.region
)
SELECT pr.product_name, pr.region, COALESCE(t.total_orders,0) as total_orders
FROM product_region pr LEFT JOIN transactions t ON pr.product_name = t.product_name
AND pr.region = t.region
ORDER BY pr.product_name, pr.region;

--TOP 5 PRODUCT NAME BY REVENUE
SELECT p.product_name, COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity * ot.unit_price END), 0) as total_revenue
FROM product p LEFT JOIN order_items ot ON p.product_id = ot.product_id
JOIN order_receipts o ON o.order_id = ot.order_id
GROUP BY p.product_name
ORDER BY total_revenue DESC
LIMIT 5;


--TOP 5 PRODUCT NAME BY UNIT SOLD
SELECT p.product_name, COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity END), 0) as total_unit_sold
FROM product p LEFT JOIN order_items ot ON p.product_id = ot.product_id
JOIN order_receipts o ON o.order_id = ot.order_id
GROUP BY p.product_name
ORDER BY total_unit_sold DESC
LIMIT 5;


--PRODUCT REVENUE BY CUSTOMER SEGMENT
SELECT p.product_name,
COALESCE(SUM(CASE WHEN c.customer_segment = 'VIP' THEN ot.quantity * ot.unit_price END), 0) as VIP_revenue,
COALESCE(SUM(CASE WHEN c.customer_segment = 'Premium' THEN ot.quantity * ot.unit_price END), 0) as Premium_revenue,
COALESCE(SUM(CASE WHEN c.customer_segment = 'Regular' THEN ot.quantity * ot.unit_price END), 0) as Regular_revenue
FROM product p JOIN order_items ot ON p.product_id = ot.product_id
JOIN order_receipts o ON o.order_id = ot.order_id
JOIN customer c ON c.customer_id = o.customer_id
WHERE o.order_status = 'Completed'
GROUP BY p.product_name
ORDER BY p.product_name


--TOP5 BRAND BY UNIT SOLD
SELECT p.brand, SUM(ot.quantity * ot.unit_price) as total_revenue,
SUM(ot.quantity) as total_unit_sold
FROM product p JOIN order_items ot ON p.product_id = ot.product_id
JOIN order_receipts o ON o.order_id = ot.order_id
WHERE o.order_status = 'Completed'
GROUP BY p.brand
ORDER BY total_unit_sold DESC
limit 5;


--CUSTOMER SEGMENT
SELECT c.customer_segment, 
NULLIF(COUNT(DISTINCT CASE WHEN o.order_status = 'Completed' THEN c.customer_id END), 0) as total_count,
COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity * ot.unit_price END), 0) as total_revenue,
COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity END),0) as total_unit_sold,
NULLIF(COUNT(DISTINCT CASE WHEN o.order_status = 'Completed' THEN o.order_id END),0) as total_completed_orders,
ROUND(COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity * ot.unit_price END), 0) / NULLIF(COUNT(DISTINCT CASE WHEN o.order_status = 'Completed' THEN o.order_id END), 0), 2) as avg_order_value
FROM customer c LEFT JOIN order_receipts o ON c.customer_id = o.customer_id
LEFT JOIN order_items ot ON ot.order_id = o.order_id
LEFT JOIN product p ON p.product_id = ot.product_id
GROUP BY c.customer_segment
ORDER BY total_revenue DESC;



--TOTAL UNIT SOLD OF CATEGORY & BRAND PER CUSTOMER SEGMENT
SELECT p.category, p.brand,
COALESCE(SUM(CASE WHEN c.customer_segment = 'VIP' THEN ot.quantity END), 0) as VIP_total_unit_purchased,
COALESCE(SUM(CASE WHEN c.customer_segment = 'Regular' THEN ot.quantity END), 0) as Regular_total_unit_purchased,
COALESCE(SUM(CASE WHEN c.customer_segment = 'Premium' THEN ot.quantity END), 0) as premium_total_unit_purchased
FROM product p LEFT JOIN order_items ot ON p.product_id = ot.product_id
LEFT JOIN order_receipts o ON o.order_id = ot.order_id
LEFT JOIN customer c ON c.customer_id = o.customer_id
WHERE o.order_status = 'Completed'
GROUP BY p.category, p.brand
ORDER BY p.category;


--CUSTOMER SEGMENT TOP 1 CATEGORY AND UNIT SOLD PERCENTAGE
WITH segment_info as (
SELECT customer_segment, category, total_unit_sold, top1 FROM(
SELECT c.customer_segment, p.category, 
SUM(ot.quantity) as total_unit_sold,
ROW_NUMBER() OVER(PARTITION BY c.customer_segment ORDER BY SUM(ot.quantity) DESC) as top1
FROM customer c LEFT JOIN order_receipts o ON c.customer_id = o.customer_id
LEFT JOIN order_items ot ON o.order_id = ot.order_id
LEFT JOIN product p ON p.product_id = ot.product_id
WHERE o.order_status = 'Completed'
GROUP BY c.customer_segment, p.category
)
WHERE top1 = 1
),
overall_unit as (
SELECT c.customer_segment, SUM(ot.quantity) as overall_unit_sold
FROM order_items ot JOIN order_receipts o ON ot.order_id = o.order_id
JOIN customer c ON c.customer_id = o.customer_id
WHERE o.order_status = 'Completed'
GROUP BY c.customer_segment
)
SELECT s.customer_segment, s.category, s.total_unit_sold, 
ov.overall_unit_sold, ROUND((s.total_unit_sold::NUMERIC / ov.overall_unit_sold) * 100, 2) as unit_sold_percentage
FROM segment_info s JOIN overall_unit ov ON s.customer_segment = ov.customer_segment;


--CUSTOMER SEGMENT CATEGORY TOTAL UNIT SOLD AND UNIT SOLD PERCENTAGE (EACH SEGMENT UNIT SOLD)
WITH seg_category as (
SELECT c.customer_segment, p.category, SUM(ot.quantity) as total_unit_sold
FROM customer c JOIN order_receipts o ON c.customer_id = o.customer_id
JOIN order_items ot ON o.order_id = ot.order_id
JOIN product p ON p.product_id = ot.product_id
WHERE o.order_status = 'Completed'
GROUP BY c.customer_segment, p.category
),
overall_category as (
SELECT c.customer_segment, SUM(ot.quantity) as overall_quantity
FROM customer c JOIN order_receipts o ON c.customer_id = o.customer_id
JOIN order_items ot ON o.order_id = ot.order_id
WHERE o.order_status = 'Completed'
GROUP BY c.customer_segment
)
SELECT sc.customer_segment, sc.category, sc.total_unit_sold,
ov.overall_quantity, ROUND((sc.total_unit_sold::NUMERIC / ov.overall_quantity) * 100, 2) as unit_sold_percentage
FROM seg_category sc JOIN overall_category ov ON sc.customer_segment = ov.customer_segment
ORDER BY sc.customer_segment;


--CUSTOMERS KPIs
WITH customer_info as (
SELECT c.customer_id, c.customer_name, c.region,
COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity * ot.unit_price END), 0) as total_revenue,
NULLIF(COUNT(DISTINCT CASE WHEN o.order_status = 'Completed' THEN o.order_id END),0) AS total_orders,
COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity END), 0) as total_unit_purchased
FROM customer c LEFT JOIN order_receipts o ON c.customer_id = o.customer_id
LEFT JOIN order_items ot ON ot.order_id = o.order_id
GROUP BY c.customer_id, c.customer_name, c.region
),
overall_rev as (
SELECT SUM(ot.quantity * ot.unit_price) as overall_revenue,
COUNT(DISTINCT o.order_id) as overall_orders,
SUM(ot.quantity) as overall_unit_sold
FROM order_items ot JOIN order_receipts o ON ot.order_id = o.order_id
WHERE o.order_status = 'Completed'
)
SELECT ci.customer_id, ci.customer_name, ci.region, ci.total_revenue,
ci.total_orders, ci.total_unit_purchased, ROUND((ci.total_revenue::NUMERIC / ov.overall_revenue) * 100, 2) as revenue_percentage,
ROUND((ci.total_orders::NUMERIC / ov.overall_orders) * 100, 2) as order_percentage,
ROUND((ci.total_unit_purchased::NUMERIC / ov.overall_unit_sold) * 100, 2) as unit_sold_percentage
FROM customer_info ci CROSS JOIN overall_rev ov
ORDER BY total_revenue DESC;


--CUSTOMER MOST PURCHASED CATEGORY (across their orders)
SELECT customer_id, customer_name, region, category as top_category, total_purchased FROM(
SELECT c.customer_id, c.customer_name, c.region, p.category,
NULLIF(COUNT(DISTINCT CASE WHEN o.order_status = 'Completed' THEN ot.order_items_id END), 0) as total_purchased,
ROW_NUMBER() OVER(PARTITION BY c.customer_id ORDER BY COUNT(DISTINCT o.order_id) DESC) as rankings
FROM customer c LEFT JOIN order_receipts o ON c.customer_id = o.customer_id
LEFT JOIN order_items ot ON o.order_id = ot.order_id
LEFT JOIN product p ON p.product_id = ot.product_id
GROUP BY c.customer_id, c.customer_name, c.region, p.category
)
WHERE rankings = 1;


--MOST REVENUE GENERATED CITY
SELECT c.city, c.region,
COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity * ot.unit_price END),0) as total_revenue,
COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity END), 0) as total_unit_sold,
NULLIF(COUNT(DISTINCT CASE WHEN o.order_status = 'Completed' THEN o.order_id END), 0) as total_completed_orders
FROM customer c LEFT JOIN order_receipts o ON c.customer_id = o.customer_id
LEFT JOIN order_items ot ON o.order_id = ot.order_id
GROUP BY c.city, c.region
ORDER BY total_revenue DESC;


--REGION MOST GENERATED REVENUE AND CUSTOMER NUMBER
SELECT c.region, 
SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity * ot.unit_price END) as region_revenue,
COUNT(DISTINCT CASE WHEN o.order_status = 'Completed' THEN ot.quantity * ot.unit_price END) as region_completed_orders,
SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity END) as region_total_unit_sold,
COUNT(DISTINCT CASE WHEN o.order_status = 'Completed' THEN o.customer_id END) as total_customer,
ROUND(COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity * ot.unit_price END),0) / NULLIF(COUNT(DISTINCT CASE WHEN o.order_status = 'Completed' THEN o.order_id END), 0),2) as avg_order_value
FROM customer c LEFT JOIN order_receipts o ON c.customer_id = o.customer_id
LEFT JOIN order_items ot ON o.order_id = ot.order_id
GROUP BY c.region
ORDER BY region_revenue DESC;


--REGION WITH SALES OF ALL CATEGORY
SELECT c.region, COUNT(DISTINCT p.category) as total_number_of_category
FROM customer c JOIN order_receipts o ON c.customer_id = o.customer_id
JOIN order_items ot ON o.order_id = ot.order_id
JOIN product p ON p.product_id = ot.product_id
WHERE o.order_status = 'Completed'
GROUP BY c.region
HAVING COUNT(DISTINCT p.category) = 5;



--PAYMENT METHOD REVENUE
SELECT o.payment_method, 
COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity * ot.unit_price END), 0) as total_revenue,
NULLIF(COUNT(DISTINCT CASE WHEN o.order_status = 'Completed' THEN o.order_id END), 0) as total_order,
ROUND(COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity * ot.unit_price END), 0) / NULLIF(COUNT(DISTINCT CASE WHEN o.order_status = 'Completed' THEN o.order_id END), 0),2) as avg_order_value
FROM order_receipts o LEFT JOIN order_items ot ON o.order_id = ot.order_id
GROUP BY o.payment_method
ORDER BY total_revenue DESC;


--CATEGORY ASSOCIATED WITH PAYMENT METHOD
SELECT o.payment_method, p.category, COUNT(DISTINCT o.order_id) as total_purchased
FROM order_receipts o JOIN order_items ot ON o.order_id = ot.order_id
JOIN product p ON p.product_id = ot.product_id
WHERE o.order_status = 'Completed'
GROUP BY o.payment_method, p.category
ORDER BY o.payment_method;

--TOP PRODUCT NAME IN EACH PAYMENT METHOD
SELECT payment_method, product_name, total_revenue FROM(
SELECT o.payment_method, p.product_name, SUM(ot.quantity * ot.unit_price) as total_revenue,
ROW_NUMBER() OVER(PARTITION BY o.payment_method ORDER BY SUM(ot.quantity * ot.unit_price) DESC) as rankings
FROM order_receipts o JOIN order_items ot ON o.order_id = ot.order_id
JOIN product p ON p.product_id = ot.product_id
WHERE o.order_status = 'Completed'
GROUP BY o.payment_method, p.product_name
)
WHERE rankings = 1;


--MOST ASSOCIATED PAYMENT METHOD WITH THE HIGHEST REVENUE PRODUCT

WITH high_value as ( --for getting the highest revenue product
SELECT p.product_name, 
COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity * ot.unit_price END), 0) as total_revenue
FROM product p LEFT JOIN order_items ot ON p.product_id = ot.product_id
LEFT JOIN order_receipts o ON o.order_id = ot.order_id
GROUP BY p.product_name
ORDER BY total_revenue DESC
LIMIT 1
)
--for getting the most associated payment method bu number of order line
SELECT h.product_name, o.payment_method, COUNT(DISTINCT ot.order_items_id) as total_purchased
FROM high_value h JOIN product p ON p.product_name = h.product_name
JOIN order_items ot ON ot.product_id = p.product_id
JOIN order_receipts o ON o.order_id = ot.order_id
WHERE o.order_status = 'Completed'
GROUP BY h.product_name, o.payment_method
ORDER BY total_purchased DESC
LIMIT 1;


--SHIPPING METHOD
WITH shipping as (
SELECT o.shipping_method, 
NULLIF(COUNT(DISTINCT CASE WHEN o.order_status = 'Completed' THEN o.order_id END), 0) as total_completed_orders,
COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity * ot.unit_price END), 0) as total_revenue,
NULLIF(COUNT(DISTINCT CASE WHEN o.order_status = 'Completed' THEN o.customer_id END), 0) as total_customer,
ROUND(COALESCE(SUM(CASE WHEN o.order_status = 'Completed' THEN ot.quantity * ot.unit_price END) , 0) / NULLIF(COUNT(DISTINCT CASE WHEN o.order_status = 'Completed' THEN o.order_id END),0),2) as avg_order_value
FROM order_receipts o LEFT JOIN order_items ot ON o.order_id = ot.order_id
GROUP BY o.shipping_method
),
overall_ord as (
SELECT COUNT(DISTINCT o.order_id) as overall_order
FROM order_receipts o JOIN order_items ot ON o.order_id = ot.order_id
WHERE o.order_status = 'Completed'
)
SELECT s.shipping_method, s.total_completed_orders, s.total_revenue,
s.total_customer, s.avg_order_value, ROUND((s.total_completed_orders::NUMERIC / ov.overall_order) * 100, 2) as order_percentage
FROM shipping s CROSS JOIN overall_ord ov;


--TOTAL LOSES FROM CANCELLED AND RETURNED ORDERS
SELECT o.order_status, 
COALESCE(SUM(ot.quantity * ot.unit_price),0) as total_revenue
FROM order_receipts o JOIN order_items ot ON o.order_id = ot.order_id
WHERE o.order_status IN ('Cancelled', 'Returned')
GROUP BY o.order_status;


--ORDER STATUS RATES, REVENUE ETC.
WITH orders as (
SELECT o.order_status,
COALESCE(SUM(ot.quantity * ot.unit_price),0) as total_revenue,
NULLIF(COUNT(DISTINCT o.order_id), 0) as total_orders
FROM order_receipts o JOIN order_items ot ON o.order_id = ot.order_id
GROUP BY o.order_status
),
overall_ord as (
SELECT COUNT(DISTINCT order_id) as overall_order
FROM order_receipts
)
SELECT ors.order_status, ors.total_revenue, ors.total_orders,
ov.overall_order, ROUND((ors.total_orders::NUMERIC / ov.overall_order) * 100, 2) as rate
FROM orders ors CROSS JOIN overall_ord ov;


--MOST CANCELLED AND RETURNED PRODUCT
SELECT order_status, product_name, total_unit FROM(
SELECT o.order_status, p.product_name, SUM(ot.quantity) as total_unit,
ROW_NUMBER() OVER(PARTITION BY o.order_status ORDER BY SUM(ot.quantity) DESC) as rankings
FROM order_receipts o JOIN order_items ot ON o.order_id = ot.order_id
JOIN product p ON p.product_id = ot.product_id
WHERE o.order_status IN ('Returned', 'Cancelled')
GROUP BY o.order_status, p.product_name
)
WHERE rankings = 1;

--CANCELLED AND RETURNED CATEGORY
SELECT order_status, category, total_unit, total_revenue, rankings FROM(
SELECT o.order_status, p.category, SUM(ot.quantity) as total_unit, SUM(ot.quantity * ot.unit_price) as total_revenue,
ROW_NUMBER() OVER(PARTITION BY o.order_status ORDER BY SUM(ot.quantity) DESC) as rankings
FROM order_receipts o JOIN order_items ot ON o.order_id = ot.order_id
JOIN product p ON p.product_id = ot.product_id
WHERE o.order_status IN ('Returned', 'Cancelled')
GROUP BY o.order_status, p.category
);

--CANCELLED AND RETURNED BRAND
SELECT order_status, brand, total_unit, total_revenue, rankings FROM(
SELECT o.order_status, p.brand, SUM(ot.quantity) as total_unit, SUM(ot.quantity * ot.unit_price) as total_revenue,
ROW_NUMBER() OVER(PARTITION BY o.order_status ORDER BY SUM(ot.quantity) DESC) as rankings
FROM order_receipts o JOIN order_items ot ON o.order_id = ot.order_id
JOIN product p ON p.product_id = ot.product_id
WHERE o.order_status IN ('Returned', 'Cancelled')
GROUP BY o.order_status, p.brand
);


--CUSTOMER SEGMENT WITH THE MOST CANCELLED AND RETURNED ORDERS
SELECT order_status, customer_segment, total_order, total_revenue, rankings FROM(
SELECT o.order_status, c.customer_segment, COUNT(DISTINCT o.order_id) as total_order, SUM(ot.quantity * ot.unit_price) as total_revenue,
ROW_NUMBER() OVER(PARTITION BY o.order_status ORDER BY COUNT(DISTINCT o.order_id) DESC) as rankings
FROM order_receipts o JOIN order_items ot ON o.order_id = ot.order_id
JOIN customer c ON c.customer_id = o.customer_id
WHERE o.order_status IN ('Returned', 'Cancelled')
GROUP BY o.order_status, c.customer_segment
);


--REGION WITH HIGHEST CANCELLED AND RETURNED ORDER
SELECT order_status, region, total_order, total_revenue, rankings FROM(
SELECT o.order_status, c.region, COUNT(DISTINCT o.order_id) as total_order, SUM(ot.quantity * ot.unit_price) as total_revenue,
ROW_NUMBER() OVER(PARTITION BY o.order_status ORDER BY COUNT(DISTINCT o.order_id) DESC) as rankings
FROM order_receipts o JOIN customer c ON c.customer_id = o.customer_id
JOIN order_items ot ON o.order_id = ot.order_id
WHERE o.order_status IN ('Returned', 'Cancelled')
GROUP BY o.order_status, c.region
);

--TOP CROSS SELLING BY CATEGORY AND ORDER PERCENTAGE
WITH categories_orders as (
SELECT p1.category as category1, p2.category as category2,
COUNT(DISTINCT o.order_id) as total_orders
FROM order_items ot JOIN order_items ot1 ON ot.order_id = ot1.order_id
AND ot.product_id < ot1.product_id
JOIN product p1 ON p1.product_id = ot.product_id
JOIN product p2 ON p2.product_id = ot1.product_id
JOIN order_receipts o ON o.order_id = ot.order_id
WHERE o.order_status = 'Completed'
GROUP BY p1.category, p2.category
ORDER BY total_orders DESC
),
overall_ord as (
SELECT COUNT(DISTINCT o.order_id) as overall_order
FROM order_receipts o JOIN order_items ot ON o.order_id = ot.order_id
WHERE o.order_status = 'Completed'
)
SELECT co.category1, co.category2, co.total_orders,
ROUND((co.total_orders::NUMERIC / ov.overall_order) * 100, 2) as order_percentage
FROM categories_orders co CROSS JOIN overall_ord ov;


--TOP CROSS SELLING PRODUCT NAME
SELECT p1.product_name as product1, p2.product_name as product2,
COUNT(DISTINCT o.order_id) as total_orders
FROM order_items ot JOIN order_items ot1 ON ot.order_id = ot1.order_id
AND ot.product_id < ot1.product_id
JOIN product p1 ON ot.product_id = p1.product_id
JOIN product p2 ON ot1.product_id = p2.product_id
JOIN order_receipts o ON o.order_id = ot.order_id
WHERE o.order_status = 'Completed'
GROUP BY p1.product_name, p2.product_name
ORDER BY total_orders DESC;


