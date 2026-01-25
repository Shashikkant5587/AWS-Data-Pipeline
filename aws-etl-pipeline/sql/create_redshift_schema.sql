-- ETL Pipeline Redshift Schema Creation Script
-- Run this script after Redshift cluster is created

-- Create schemas
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS dimensions;
CREATE SCHEMA IF NOT EXISTS facts;

-- Create staging tables
CREATE TABLE IF NOT EXISTS staging.users_staging (
    user_id BIGINT,
    username VARCHAR(100),
    email VARCHAR(255),
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    status VARCHAR(20),
    extraction_timestamp TIMESTAMP
);

CREATE TABLE IF NOT EXISTS staging.orders_staging (
    order_id BIGINT,
    user_id BIGINT,
    product_id BIGINT,
    order_date DATE,
    quantity INTEGER,
    unit_price DECIMAL(10,2),
    total_amount DECIMAL(10,2),
    order_status VARCHAR(50),
    created_at TIMESTAMP,
    extraction_timestamp TIMESTAMP
);

CREATE TABLE IF NOT EXISTS staging.products_staging (
    product_id BIGINT,
    product_name VARCHAR(255),
    category VARCHAR(100),
    price DECIMAL(10,2),
    description TEXT,
    created_at TIMESTAMP,
    extraction_timestamp TIMESTAMP
);

-- Create dimension tables
CREATE TABLE IF NOT EXISTS dimensions.dim_users (
    user_key BIGINT IDENTITY(1,1) PRIMARY KEY,
    user_id BIGINT NOT NULL,
    username VARCHAR(100),
    email VARCHAR(255),
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    full_name VARCHAR(255),
    created_date DATE,
    updated_date DATE,
    is_active BOOLEAN,
    effective_date DATE NOT NULL,
    expiry_date DATE NOT NULL,
    is_current BOOLEAN NOT NULL,
    created_timestamp TIMESTAMP DEFAULT GETDATE(),
    updated_timestamp TIMESTAMP DEFAULT GETDATE()
) 
DISTSTYLE KEY 
DISTKEY(user_id)
SORTKEY(user_id, effective_date);

CREATE TABLE IF NOT EXISTS dimensions.dim_products (
    product_key BIGINT IDENTITY(1,1) PRIMARY KEY,
    product_id BIGINT NOT NULL,
    product_name VARCHAR(255),
    category VARCHAR(100),
    price DECIMAL(10,2),
    description TEXT,
    created_date DATE,
    effective_date DATE NOT NULL,
    expiry_date DATE NOT NULL,
    is_current BOOLEAN NOT NULL,
    created_timestamp TIMESTAMP DEFAULT GETDATE(),
    updated_timestamp TIMESTAMP DEFAULT GETDATE()
)
DISTSTYLE KEY
DISTKEY(product_id)
SORTKEY(product_id, effective_date);

CREATE TABLE IF NOT EXISTS dimensions.dim_date (
    date_key INTEGER PRIMARY KEY,
    full_date DATE NOT NULL,
    day_of_week INTEGER,
    day_name VARCHAR(10),
    day_of_month INTEGER,
    day_of_year INTEGER,
    week_of_year INTEGER,
    month_number INTEGER,
    month_name VARCHAR(10),
    quarter INTEGER,
    year INTEGER,
    is_weekend BOOLEAN,
    is_holiday BOOLEAN
)
DISTSTYLE ALL
SORTKEY(date_key);

-- Create fact tables
CREATE TABLE IF NOT EXISTS facts.fact_orders (
    order_key BIGINT IDENTITY(1,1) PRIMARY KEY,
    order_id BIGINT NOT NULL,
    user_key BIGINT,
    product_key BIGINT,
    order_date_key INTEGER,
    order_date DATE,
    quantity INTEGER,
    unit_price DECIMAL(10,2),
    total_amount DECIMAL(10,2),
    order_status VARCHAR(50),
    created_timestamp TIMESTAMP DEFAULT GETDATE(),
    updated_timestamp TIMESTAMP DEFAULT GETDATE(),
    FOREIGN KEY (user_key) REFERENCES dimensions.dim_users(user_key),
    FOREIGN KEY (product_key) REFERENCES dimensions.dim_products(product_key),
    FOREIGN KEY (order_date_key) REFERENCES dimensions.dim_date(date_key)
)
DISTSTYLE KEY
DISTKEY(user_key)
SORTKEY(order_date, order_id);

-- Create indexes for better performance
CREATE INDEX idx_dim_users_user_id ON dimensions.dim_users(user_id);
CREATE INDEX idx_dim_users_current ON dimensions.dim_users(is_current);
CREATE INDEX idx_dim_products_product_id ON dimensions.dim_products(product_id);
CREATE INDEX idx_dim_products_current ON dimensions.dim_products(is_current);
CREATE INDEX idx_fact_orders_order_date ON facts.fact_orders(order_date);
CREATE INDEX idx_fact_orders_user_key ON facts.fact_orders(user_key);

-- Populate date dimension (for 5 years: 2020-2025)
INSERT INTO dimensions.dim_date (
    date_key, full_date, day_of_week, day_name, day_of_month, day_of_year,
    week_of_year, month_number, month_name, quarter, year, is_weekend, is_holiday
)
SELECT 
    TO_NUMBER(TO_CHAR(date_series, 'YYYYMMDD'), '99999999') as date_key,
    date_series as full_date,
    EXTRACT(DOW FROM date_series) as day_of_week,
    TO_CHAR(date_series, 'Day') as day_name,
    EXTRACT(DAY FROM date_series) as day_of_month,
    EXTRACT(DOY FROM date_series) as day_of_year,
    EXTRACT(WEEK FROM date_series) as week_of_year,
    EXTRACT(MONTH FROM date_series) as month_number,
    TO_CHAR(date_series, 'Month') as month_name,
    EXTRACT(QUARTER FROM date_series) as quarter,
    EXTRACT(YEAR FROM date_series) as year,
    CASE WHEN EXTRACT(DOW FROM date_series) IN (0, 6) THEN TRUE ELSE FALSE END as is_weekend,
    FALSE as is_holiday -- You can update this based on your business calendar
FROM (
    SELECT '2020-01-01'::DATE + ROW_NUMBER() OVER (ORDER BY 1) - 1 as date_series
    FROM (
        SELECT 1 as n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL
        SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10
    ) t1
    CROSS JOIN (
        SELECT 1 as n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL
        SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10
    ) t2
    CROSS JOIN (
        SELECT 1 as n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL
        SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10
    ) t3
    CROSS JOIN (
        SELECT 1 as n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL
        SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10
    ) t4
) date_range
WHERE date_series <= '2025-12-31'::DATE;

-- Create views for easy querying
CREATE OR REPLACE VIEW facts.v_order_summary AS
SELECT 
    fo.order_date,
    du.username,
    du.email,
    dp.product_name,
    dp.category,
    fo.quantity,
    fo.unit_price,
    fo.total_amount,
    fo.order_status,
    dd.month_name,
    dd.quarter,
    dd.year
FROM facts.fact_orders fo
JOIN dimensions.dim_users du ON fo.user_key = du.user_key AND du.is_current = TRUE
JOIN dimensions.dim_products dp ON fo.product_key = dp.product_key AND dp.is_current = TRUE
JOIN dimensions.dim_date dd ON fo.order_date_key = dd.date_key;

-- Grant permissions
GRANT USAGE ON SCHEMA staging TO PUBLIC;
GRANT USAGE ON SCHEMA dimensions TO PUBLIC;
GRANT USAGE ON SCHEMA facts TO PUBLIC;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA staging TO PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA dimensions TO PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA facts TO PUBLIC;

-- Analyze tables for query optimization
ANALYZE staging.users_staging;
ANALYZE staging.orders_staging;
ANALYZE staging.products_staging;
ANALYZE dimensions.dim_users;
ANALYZE dimensions.dim_products;
ANALYZE dimensions.dim_date;
ANALYZE facts.fact_orders;