-- =====================================================
-- 1. Data Quality Checks
-- =====================================================

-- Row Count
SELECT COUNT(*) AS total_records
FROM aqi_raw;

-- Date Range
SELECT 
    MIN(date) AS start_date,
    MAX(date) AS end_date
FROM aqi_raw;

-- Null Analysis
SELECT
    COUNT(*) FILTER (WHERE date IS NULL) AS null_date,
    COUNT(*) FILTER (WHERE city IS NULL) AS null_city,
    COUNT(*) FILTER (WHERE aqi_value IS NULL) AS null_aqi
FROM aqi_raw;


-- =====================================================
-- 2. Data Transformation
-- =====================================================

CREATE TABLE aqi_city_daily AS
SELECT 
    date,
    month,
    city,
    ROUND(AVG(aqi_value), 0) AS aqi_value,
    MAX(air_quality) AS air_quality,
    MAX(prominent_pollutant) AS prominent_pollutant
FROM aqi_raw
GROUP BY date, city, month;


-- =====================================================
-- 3. Yearly AQI Trend (India Level)
-- =====================================================

CREATE OR REPLACE VIEW vw_yearly_aqi_trend AS
SELECT
    EXTRACT(YEAR FROM date) AS year,
    ROUND(AVG(aqi_value), 2) AS avg_aqi
FROM aqi_city_daily
GROUP BY EXTRACT(YEAR FROM date)
ORDER BY year;


-- =====================================================
-- 4. Monthly AQI Trend
-- =====================================================

CREATE OR REPLACE VIEW vw_monthly_aqi_trend AS
SELECT
    EXTRACT(MONTH FROM date) AS month_num,
    TO_CHAR(date, 'Month') AS month,
    ROUND(AVG(aqi_value), 2) AS avg_aqi
FROM aqi_city_daily
GROUP BY EXTRACT(MONTH FROM date), TO_CHAR(date, 'Month')
ORDER BY month_num;


-- =====================================================
-- 5. City-Level Analysis
-- =====================================================

ALTER TABLE aqi_city_daily
ADD COLUMN city_clean TEXT;

UPDATE aqi_city_daily
SET city_clean = INITCAP(TRIM(REPLACE(city,'_',' ')));

CREATE OR REPLACE VIEW vw_city_avg_aqi AS
SELECT
    city_clean,
    ROUND(AVG(aqi_value), 2) AS avg_aqi
FROM aqi_city_daily
GROUP BY city_clean
ORDER BY avg_aqi DESC;


-- =====================================================
-- 6. Yearly Pollution Ranking by City
-- =====================================================

CREATE OR REPLACE VIEW vw_city_year_ranking AS
SELECT
    year,
    city_clean,
    avg_aqi,
    DENSE_RANK() OVER (
        PARTITION BY year
        ORDER BY avg_aqi DESC
    ) AS pollution_rank
FROM (
    SELECT
        EXTRACT(YEAR FROM date)::INT AS year,
        city_clean,
        ROUND(AVG(aqi_value), 2) AS avg_aqi
    FROM aqi_city_daily
    GROUP BY EXTRACT(YEAR FROM date), city_clean
) t;


-- =====================================================
-- 7. Regional Severity Analysis (Delhi NCR vs Rest)
-- =====================================================

CREATE OR REPLACE VIEW vw_ncr_severity_summary AS
SELECT 
    region_flag,
    COUNT(*) AS total_days,
    ROUND(
        COUNT(CASE WHEN aqi_severity IN ('Poor','Very Poor','Severe') THEN 1 END)
        *100.0 / COUNT(*), 2
    ) AS unhealthy_day_percentage
FROM (
    SELECT 
        date,
        city_clean,
        aqi_value,
        CASE 
            WHEN city_clean IN (
                'Delhi','Noida','Greater Noida',
                'Ghaziabad','Gurugram','Faridabad','Sonipat'
            )
            THEN 'Delhi NCR'
            ELSE 'Rest of India'
        END AS region_flag,
        CASE
            WHEN aqi_value <= 50 THEN 'Good'
            WHEN aqi_value <= 100 THEN 'Satisfactory'
            WHEN aqi_value <= 200 THEN 'Moderate'
            WHEN aqi_value <= 300 THEN 'Poor'
            WHEN aqi_value <= 400 THEN 'Very Poor'
            ELSE 'Severe'
        END AS aqi_severity
    FROM aqi_city_daily
) t
GROUP BY region_flag;


-- =====================================================
-- 8. AQI Volatility Analysis
-- =====================================================

CREATE OR REPLACE VIEW vw_city_volatility AS
SELECT 
    city_clean,
    ROUND(AVG(aqi_value), 2) AS avg_aqi,
    ROUND(STDDEV(aqi_value), 2) AS aqi_volatility
FROM aqi_city_daily
GROUP BY city_clean
ORDER BY aqi_volatility DESC;



