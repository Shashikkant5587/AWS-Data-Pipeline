# Design Document

## Overview

The AWS ETL Pipeline is a cloud-native data processing system built using AWS services for extracting, transforming, and loading data at scale. The architecture leverages serverless and managed services including AWS Glue, Lambda, Step Functions, S3, Redshift, Kinesis, and CloudWatch to create a robust, scalable, and cost-effective data pipeline solution.

## Architecture

### AWS Services Stack

**Data Storage:**
- **Amazon S3**: Data lake for raw and processed data storage with Apache Iceberg table format
- **Amazon Redshift**: Data warehouse for analytics workloads
- **AWS Glue Data Catalog**: Centralized metadata repository with Iceberg table support

**Data Processing:**
- **AWS Glue**: Serverless ETL service for data transformation with Iceberg support
- **AWS Lambda**: Serverless compute for lightweight processing
- **Amazon EMR**: Big data processing for complex transformations and Iceberg operations
- **AWS Batch**: Containerized batch processing

**Data Streaming:**
- **Amazon Kinesis Data Streams**: Real-time data ingestion
- **Amazon Kinesis Data Firehose**: Data delivery to destinations
- **Amazon Kinesis Analytics**: Stream processing and analytics

**Orchestration & Workflow:**
- **AWS Step Functions**: Workflow orchestration and state management
- **Amazon EventBridge**: Event-driven architecture
- **AWS Lambda**: Trigger functions and workflow coordination

**Monitoring & Alerting:**
- **Amazon CloudWatch**: Metrics, logs, and monitoring
- **AWS SNS**: Notifications and alerting
- **AWS CloudTrail**: API activity logging
- **AWS X-Ray**: Distributed tracing

**Security & Access:**
- **AWS IAM**: Identity and access management
- **AWS KMS**: Key management and encryption
- **AWS Secrets Manager**: Credentials management
- **AWS VPC**: Network isolation

### Architecture Diagram

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Data Sources  │    │   Streaming     │    │   File Sources  │
│                 │    │   Sources       │    │                 │
│ • PostgreSQL    │    │ • Kinesis       │    │ • CSV Files     │
│ • MySQL         │    │ • Kafka         │    │ • JSON Files    │
│ • REST APIs     │    │ • IoT Events    │    │ • Parquet       │
└─────────┬───────┘    └─────────┬───────┘    └─────────┬───────┘
          │                      │                      │
          ▼                      ▼                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Data Ingestion Layer                         │
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │AWS Lambda   │  │Kinesis Data │  │AWS Glue     │            │
│  │(API Extract)│  │Streams      │  │(File Crawl) │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Data Lake (S3)                             │
│                                                                 │
│  Raw Data Bucket                 Processed Data Bucket          │
│  ├── year=2024/                 ├── year=2024/                 │
│  │   ├── month=01/              │   ├── month=01/              │
│  │   │   ├── day=15/            │   │   ├── day=15/            │
│  │   │   │   └── data.json      │   │   │   └── data.parquet   │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                 Data Processing Layer                           │
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │AWS Glue ETL │  │Lambda       │  │EMR Spark    │            │
│  │Jobs         │  │Functions    │  │Jobs         │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                 Data Warehouse Layer                            │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Amazon Redshift                            │   │
│  │                                                         │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │   │
│  │  │   Staging   │  │   Facts     │  │ Dimensions  │    │   │
│  │  │   Tables    │  │   Tables    │  │   Tables    │    │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘    │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                 Orchestration Layer                             │
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │Step         │  │EventBridge  │  │CloudWatch   │            │
│  │Functions    │  │Rules        │  │Events       │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                 Monitoring Layer                                │
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │CloudWatch   │  │SNS          │  │CloudTrail   │            │
│  │Dashboards   │  │Notifications│  │Audit Logs   │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
└─────────────────────────────────────────────────────────────────┘
```

## Components and Interfaces

### Data Models

```python
# Data Source Configuration
@dataclass
class DataSource:
    source_id: str
    source_type: str  # 'database', 'api', 'file', 'stream'
    connection_string: str
    credentials_secret: str
    extraction_query: Optional[str]
    incremental_column: Optional[str]
    schedule: str

# ETL Job Configuration
@dataclass
class ETLJob:
    job_id: str
    job_name: str
    source_config: DataSource
    transformation_script: str
    target_table: str
    schedule: str
    retry_policy: RetryPolicy
    data_quality_rules: List[DataQualityRule]

# Data Quality Rule
@dataclass
class DataQualityRule:
    rule_id: str
    rule_type: str  # 'not_null', 'unique', 'range', 'regex'
    column_name: str
    parameters: Dict[str, Any]
    severity: str  # 'error', 'warning'

# Iceberg Table Configuration
@dataclass
class IcebergTableConfig:
    table_name: str
    database_name: str
    s3_location: str
    partition_spec: List[str]
    sort_order: List[str]
    table_properties: Dict[str, str]
    schema_evolution_mode: str  # 'strict', 'forward', 'backward', 'full'

# Iceberg Snapshot
@dataclass
class IcebergSnapshot:
    snapshot_id: int
    timestamp_ms: int
    sequence_number: int
    schema_id: int
    manifest_list: str
    summary: Dict[str, str]

# Iceberg Table Maintenance
@dataclass
class IcebergMaintenance:
    table_name: str
    operation_type: str  # 'compact', 'expire_snapshots', 'remove_orphan_files'
    target_file_size_mb: int
    max_concurrent_file_group_rewrites: int
    retention_days: int
    dry_run: bool

# Pipeline Execution
@dataclass
class PipelineExecution:
    execution_id: str
    pipeline_id: str
    start_time: datetime
    end_time: Optional[datetime]
    status: str  # 'running', 'success', 'failed'
    records_processed: int
    errors: List[str]
```

### AWS Infrastructure Components

#### S3 Bucket Structure with Iceberg Tables
```
etl-data-lake-bucket/
├── raw-data/
│   ├── source=database1/
│   │   ├── table=users/
│   │   │   ├── year=2024/month=01/day=15/hour=10/
│   │   │   │   └── users_20240115_10.json
│   ├── source=api1/
│   │   ├── endpoint=orders/
│   │   │   ├── year=2024/month=01/day=15/
│   │   │   │   └── orders_20240115.json
├── iceberg-tables/
│   ├── warehouse/
│   │   ├── dim_users/
│   │   │   ├── metadata/
│   │   │   │   ├── version-hint.text
│   │   │   │   ├── v1.metadata.json
│   │   │   │   ├── v2.metadata.json
│   │   │   │   └── snap-123456789.avro
│   │   │   └── data/
│   │   │       ├── year=2024/month=01/
│   │   │       │   ├── 00001-1-data.parquet
│   │   │       │   └── 00002-2-data.parquet
│   │   ├── fact_orders/
│   │   │   ├── metadata/
│   │   │   │   ├── version-hint.text
│   │   │   │   ├── v1.metadata.json
│   │   │   │   └── snap-987654321.avro
│   │   │   └── data/
│   │   │       ├── year=2024/month=01/day=15/
│   │   │       │   ├── 00001-1-data.parquet
│   │   │       │   └── 00002-2-data.parquet
├── processed-data/
│   ├── table=dim_users/
│   │   ├── year=2024/month=01/day=15/
│   │   │   └── dim_users_20240115.parquet
│   ├── table=fact_orders/
│   │   ├── year=2024/month=01/day=15/
│   │   │   └── fact_orders_20240115.parquet
├── failed-data/
│   ├── quarantine/
│   │   ├── year=2024/month=01/day=15/
│   │   │   └── failed_records_20240115.json
└── scripts/
    ├── glue-jobs/
    │   ├── transform_users_iceberg.py
    │   ├── transform_orders_iceberg.py
    │   └── iceberg_maintenance.py
    └── lambda-functions/
        ├── extract_api_data.py
        ├── data_quality_check.py
        └── iceberg_table_manager.py
```

#### Redshift Schema Design
```sql
-- Staging Schema
CREATE SCHEMA staging;

-- Dimension Tables
CREATE TABLE dim_users (
    user_id BIGINT PRIMARY KEY,
    username VARCHAR(100),
    email VARCHAR(255),
    created_date DATE,
    updated_date DATE,
    is_active BOOLEAN
) DISTSTYLE KEY DISTKEY(user_id);

CREATE TABLE dim_products (
    product_id BIGINT PRIMARY KEY,
    product_name VARCHAR(255),
    category VARCHAR(100),
    price DECIMAL(10,2),
    created_date DATE
) DISTSTYLE KEY DISTKEY(product_id);

-- Fact Tables
CREATE TABLE fact_orders (
    order_id BIGINT PRIMARY KEY,
    user_id BIGINT REFERENCES dim_users(user_id),
    product_id BIGINT REFERENCES dim_products(product_id),
    order_date DATE,
    quantity INTEGER,
    total_amount DECIMAL(10,2),
    order_status VARCHAR(50)
) DISTSTYLE KEY DISTKEY(user_id)
SORTKEY(order_date);
```

## Core Components

### 1. Data Extraction Components

#### Lambda Function for API Extraction
```python
import json
import boto3
import requests
from datetime import datetime, timedelta
import os

def lambda_handler(event, context):
    """
    Extract data from REST APIs and store in S3
    """
    s3_client = boto3.client('s3')
    secrets_client = boto3.client('secretsmanager')
    
    # Get API credentials from Secrets Manager
    api_config = get_secret(secrets_client, event['api_secret_name'])
    
    # Extract data from API
    data = extract_api_data(api_config, event.get('incremental_date'))
    
    # Store in S3 with partitioning
    s3_key = generate_s3_key(event['source_name'], datetime.now())
    store_data_s3(s3_client, data, event['bucket_name'], s3_key)
    
    return {
        'statusCode': 200,
        'records_extracted': len(data),
        's3_location': f"s3://{event['bucket_name']}/{s3_key}"
    }

def extract_api_data(api_config, incremental_date=None):
    """Extract data from API with pagination"""
    headers = {'Authorization': f"Bearer {api_config['token']}"}
    all_data = []
    page = 1
    
    while True:
        params = {'page': page, 'limit': 1000}
        if incremental_date:
            params['updated_since'] = incremental_date
            
        response = requests.get(api_config['endpoint'], headers=headers, params=params)
        response.raise_for_status()
        
        data = response.json()
        if not data.get('results'):
            break
            
        all_data.extend(data['results'])
        page += 1
        
        # Rate limiting
        time.sleep(0.1)
    
    return all_data
```

#### Glue Job for Database Extraction
```python
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame
import boto3
from datetime import datetime, timedelta

# Initialize Glue context
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'DATABASE_SECRET', 'S3_BUCKET', 'TABLE_NAME'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

def extract_database_table():
    """Extract data from database with incremental loading"""
    
    # Get database credentials
    secrets_client = boto3.client('secretsmanager')
    db_config = get_secret(secrets_client, args['DATABASE_SECRET'])
    
    # Build JDBC connection
    connection_options = {
        "url": db_config['jdbc_url'],
        "user": db_config['username'],
        "password": db_config['password'],
        "dbtable": args['TABLE_NAME']
    }
    
    # Get last extraction timestamp for incremental load
    last_extraction = get_last_extraction_timestamp(args['TABLE_NAME'])
    
    if last_extraction:
        # Incremental extraction
        query = f"""
        (SELECT * FROM {args['TABLE_NAME']} 
         WHERE updated_at > '{last_extraction}') AS incremental_data
        """
        connection_options["dbtable"] = query
    
    # Read data from database
    datasource = glueContext.create_dynamic_frame.from_options(
        connection_type="postgresql",
        connection_options=connection_options
    )
    
    # Convert to DataFrame for processing
    df = datasource.toDF()
    
    # Add extraction metadata
    df = df.withColumn("extraction_timestamp", lit(datetime.now().isoformat()))
    df = df.withColumn("extraction_date", lit(datetime.now().date()))
    
    # Convert back to DynamicFrame
    dynamic_frame = DynamicFrame.fromDF(df, glueContext, "extracted_data")
    
    # Write to S3 with partitioning
    s3_path = f"s3://{args['S3_BUCKET']}/raw-data/source={args['TABLE_NAME']}/"
    
    glueContext.write_dynamic_frame.from_options(
        frame=dynamic_frame,
        connection_type="s3",
        connection_options={
            "path": s3_path,
            "partitionKeys": ["extraction_date"]
        },
        format="json"
    )
    
    # Update last extraction timestamp
    update_last_extraction_timestamp(args['TABLE_NAME'], datetime.now())
    
    print(f"Extracted {df.count()} records from {args['TABLE_NAME']}")

job.commit()
```

### 2. Data Transformation Components

#### Glue ETL Job for Data Transformation
```python
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import *
from pyspark.sql.types import *
import boto3

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'SOURCE_S3_PATH', 'TARGET_S3_PATH'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

def transform_user_data():
    """Transform raw user data into dimension table format"""
    
    # Read raw data from S3
    raw_users = glueContext.create_dynamic_frame.from_options(
        connection_type="s3",
        connection_options={"paths": [args['SOURCE_S3_PATH']]},
        format="json"
    )
    
    # Convert to DataFrame for transformations
    df = raw_users.toDF()
    
    # Data cleaning and transformations
    df_clean = df.select(
        col("id").alias("user_id"),
        col("username"),
        lower(col("email")).alias("email"),
        to_date(col("created_at")).alias("created_date"),
        to_date(col("updated_at")).alias("updated_date"),
        when(col("status") == "active", True).otherwise(False).alias("is_active"),
        col("profile.first_name").alias("first_name"),
        col("profile.last_name").alias("last_name"),
        concat(col("profile.first_name"), lit(" "), col("profile.last_name")).alias("full_name")
    )
    
    # Data quality checks
    df_quality = apply_data_quality_rules(df_clean)
    
    # Add SCD Type 2 columns for slowly changing dimensions
    df_final = df_quality.withColumn("effective_date", current_date()) \
                        .withColumn("expiry_date", lit("9999-12-31").cast("date")) \
                        .withColumn("is_current", lit(True))
    
    # Convert back to DynamicFrame
    transformed_frame = DynamicFrame.fromDF(df_final, glueContext, "transformed_users")
    
    # Write to S3 in Parquet format
    glueContext.write_dynamic_frame.from_options(
        frame=transformed_frame,
        connection_type="s3",
        connection_options={
            "path": args['TARGET_S3_PATH'],
            "partitionKeys": ["created_date"]
        },
        format="parquet"
    )
    
    print(f"Transformed {df_final.count()} user records")

def apply_data_quality_rules(df):
    """Apply data quality rules and handle bad data"""
    
    # Remove null user_ids
    df_clean = df.filter(col("user_id").isNotNull())
    
    # Validate email format
    email_pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    df_clean = df_clean.filter(col("email").rlike(email_pattern))
    
    # Handle duplicates - keep latest record
    window_spec = Window.partitionBy("user_id").orderBy(desc("updated_date"))
    df_clean = df_clean.withColumn("row_num", row_number().over(window_spec)) \
                      .filter(col("row_num") == 1) \
                      .drop("row_num")
    
    return df_clean

transform_user_data()
job.commit()
```

### 3. Iceberg Table Management Components

#### Glue Job for Iceberg Table Creation and Management
```python
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import *
from pyspark.sql.types import *
import boto3

# Configure Iceberg with Glue
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'ICEBERG_WAREHOUSE_PATH', 'TABLE_NAME'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session

# Configure Spark for Iceberg
spark.conf.set("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
spark.conf.set("spark.sql.catalog.glue_catalog", "org.apache.iceberg.spark.SparkCatalog")
spark.conf.set("spark.sql.catalog.glue_catalog.warehouse", args['ICEBERG_WAREHOUSE_PATH'])
spark.conf.set("spark.sql.catalog.glue_catalog.catalog-impl", "org.apache.iceberg.aws.glue.GlueCatalog")
spark.conf.set("spark.sql.catalog.glue_catalog.io-impl", "org.apache.iceberg.aws.s3.S3FileIO")

job = Job(glueContext)
job.init(args['JOB_NAME'], args)

def create_iceberg_table():
    """Create Iceberg table with proper schema and partitioning"""
    
    # Define table schema
    if args['TABLE_NAME'] == 'dim_users':
        create_sql = f"""
        CREATE TABLE IF NOT EXISTS glue_catalog.etl_warehouse.dim_users (
            user_id BIGINT,
            username STRING,
            email STRING,
            created_date DATE,
            updated_date DATE,
            is_active BOOLEAN,
            first_name STRING,
            last_name STRING,
            full_name STRING,
            effective_date DATE,
            expiry_date DATE,
            is_current BOOLEAN
        ) USING ICEBERG
        PARTITIONED BY (created_date)
        TBLPROPERTIES (
            'write.format.default' = 'parquet',
            'write.parquet.compression-codec' = 'snappy',
            'commit.retry.num-retries' = '3',
            'commit.retry.min-wait-ms' = '100',
            'history.expire.max-snapshot-age-ms' = '604800000'
        )
        """
    elif args['TABLE_NAME'] == 'fact_orders':
        create_sql = f"""
        CREATE TABLE IF NOT EXISTS glue_catalog.etl_warehouse.fact_orders (
            order_id BIGINT,
            user_id BIGINT,
            product_id BIGINT,
            order_date DATE,
            quantity INTEGER,
            total_amount DECIMAL(10,2),
            order_status STRING,
            created_timestamp TIMESTAMP,
            updated_timestamp TIMESTAMP
        ) USING ICEBERG
        PARTITIONED BY (order_date)
        TBLPROPERTIES (
            'write.format.default' = 'parquet',
            'write.parquet.compression-codec' = 'snappy',
            'commit.retry.num-retries' = '3',
            'commit.retry.min-wait-ms' = '100',
            'history.expire.max-snapshot-age-ms' = '604800000'
        )
        """
    
    spark.sql(create_sql)
    print(f"Created Iceberg table: {args['TABLE_NAME']}")

def transform_and_write_to_iceberg():
    """Transform data and write to Iceberg table with ACID guarantees"""
    
    # Read raw data from S3
    raw_data_path = f"s3://etl-data-lake-bucket/raw-data/source={args['TABLE_NAME']}/"
    df = spark.read.option("multiline", "true").json(raw_data_path)
    
    if args['TABLE_NAME'] == 'dim_users':
        # Transform user data
        df_transformed = df.select(
            col("id").alias("user_id"),
            col("username"),
            lower(col("email")).alias("email"),
            to_date(col("created_at")).alias("created_date"),
            to_date(col("updated_at")).alias("updated_date"),
            when(col("status") == "active", True).otherwise(False).alias("is_active"),
            col("profile.first_name").alias("first_name"),
            col("profile.last_name").alias("last_name"),
            concat(col("profile.first_name"), lit(" "), col("profile.last_name")).alias("full_name"),
            current_date().alias("effective_date"),
            lit("9999-12-31").cast("date").alias("expiry_date"),
            lit(True).alias("is_current")
        )
        
        # Write to Iceberg table with merge operation for SCD Type 2
        df_transformed.createOrReplaceTempView("new_users")
        
        merge_sql = """
        MERGE INTO glue_catalog.etl_warehouse.dim_users AS target
        USING new_users AS source
        ON target.user_id = source.user_id AND target.is_current = true
        WHEN MATCHED AND (
            target.email != source.email OR 
            target.full_name != source.full_name
        ) THEN UPDATE SET 
            expiry_date = current_date() - INTERVAL 1 DAY,
            is_current = false
        WHEN NOT MATCHED THEN INSERT *
        """
        
        spark.sql(merge_sql)
        
        # Insert changed records as new current records
        insert_changed_sql = """
        INSERT INTO glue_catalog.etl_warehouse.dim_users
        SELECT source.* FROM new_users source
        INNER JOIN glue_catalog.etl_warehouse.dim_users target
        ON source.user_id = target.user_id
        WHERE target.expiry_date = current_date() - INTERVAL 1 DAY
        """
        
        spark.sql(insert_changed_sql)
        
    elif args['TABLE_NAME'] == 'fact_orders':
        # Transform order data
        df_transformed = df.select(
            col("id").alias("order_id"),
            col("user_id"),
            col("product_id"),
            to_date(col("order_date")).alias("order_date"),
            col("quantity"),
            col("total_amount").cast("decimal(10,2)"),
            col("status").alias("order_status"),
            col("created_at").cast("timestamp").alias("created_timestamp"),
            col("updated_at").cast("timestamp").alias("updated_timestamp")
        )
        
        # Write to Iceberg table with upsert logic
        df_transformed.createOrReplaceTempView("new_orders")
        
        merge_sql = """
        MERGE INTO glue_catalog.etl_warehouse.fact_orders AS target
        USING new_orders AS source
        ON target.order_id = source.order_id
        WHEN MATCHED THEN UPDATE SET *
        WHEN NOT MATCHED THEN INSERT *
        """
        
        spark.sql(merge_sql)
    
    print(f"Successfully wrote data to Iceberg table: {args['TABLE_NAME']}")

def perform_table_maintenance():
    """Perform Iceberg table maintenance operations"""
    
    table_name = f"glue_catalog.etl_warehouse.{args['TABLE_NAME']}"
    
    # Compact small files
    spark.sql(f"""
        CALL glue_catalog.system.rewrite_data_files(
            table => '{table_name}',
            options => map(
                'target-file-size-bytes', '134217728',
                'max-concurrent-file-group-rewrites', '5'
            )
        )
    """)
    
    # Expire old snapshots (older than 7 days)
    spark.sql(f"""
        CALL glue_catalog.system.expire_snapshots(
            table => '{table_name}',
            older_than => TIMESTAMP '{(datetime.now() - timedelta(days=7)).isoformat()}'
        )
    """)
    
    # Remove orphaned files
    spark.sql(f"""
        CALL glue_catalog.system.remove_orphan_files(
            table => '{table_name}',
            older_than => TIMESTAMP '{(datetime.now() - timedelta(days=3)).isoformat()}'
        )
    """)
    
    print(f"Completed maintenance for Iceberg table: {args['TABLE_NAME']}")

# Execute the workflow
create_iceberg_table()
transform_and_write_to_iceberg()
perform_table_maintenance()

job.commit()
```

#### Lambda Function for Iceberg Table Operations
```python
import boto3
import json
from datetime import datetime, timedelta
import os

def lambda_handler(event, context):
    """Manage Iceberg table operations and metadata"""
    
    operation = event.get('operation')
    table_name = event.get('table_name')
    
    if operation == 'get_snapshots':
        return get_table_snapshots(table_name)
    elif operation == 'time_travel_query':
        return execute_time_travel_query(event)
    elif operation == 'table_stats':
        return get_table_statistics(table_name)
    elif operation == 'schema_evolution':
        return evolve_table_schema(event)
    else:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Invalid operation'})
        }

def get_table_snapshots(table_name):
    """Get all snapshots for an Iceberg table"""
    
    glue_client = boto3.client('glue')
    
    try:
        # Get table metadata from Glue Catalog
        response = glue_client.get_table(
            DatabaseName='etl_warehouse',
            Name=table_name
        )
        
        table_location = response['Table']['StorageDescriptor']['Location']
        
        # Read Iceberg metadata to get snapshots
        s3_client = boto3.client('s3')
        bucket = table_location.split('/')[2]
        metadata_prefix = '/'.join(table_location.split('/')[3:]) + '/metadata/'
        
        # List metadata files
        metadata_objects = s3_client.list_objects_v2(
            Bucket=bucket,
            Prefix=metadata_prefix
        )
        
        snapshots = []
        for obj in metadata_objects.get('Contents', []):
            if obj['Key'].endswith('.metadata.json'):
                # Parse metadata file to extract snapshot information
                metadata_content = s3_client.get_object(
                    Bucket=bucket,
                    Key=obj['Key']
                )
                metadata = json.loads(metadata_content['Body'].read())
                
                for snapshot in metadata.get('snapshots', []):
                    snapshots.append({
                        'snapshot_id': snapshot['snapshot-id'],
                        'timestamp_ms': snapshot['timestamp-ms'],
                        'sequence_number': snapshot.get('sequence-number', 0),
                        'schema_id': snapshot.get('schema-id'),
                        'summary': snapshot.get('summary', {})
                    })
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'table_name': table_name,
                'snapshots': sorted(snapshots, key=lambda x: x['timestamp_ms'], reverse=True)
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def execute_time_travel_query(event):
    """Execute time travel query on Iceberg table"""
    
    table_name = event.get('table_name')
    timestamp = event.get('timestamp')  # ISO format timestamp
    snapshot_id = event.get('snapshot_id')
    query = event.get('query')
    
    # This would integrate with Amazon Athena or EMR for query execution
    athena_client = boto3.client('athena')
    
    if timestamp:
        time_travel_query = f"""
        SELECT * FROM glue_catalog.etl_warehouse.{table_name}
        FOR TIMESTAMP AS OF TIMESTAMP '{timestamp}'
        {query.replace('SELECT * FROM ' + table_name, '')}
        """
    elif snapshot_id:
        time_travel_query = f"""
        SELECT * FROM glue_catalog.etl_warehouse.{table_name}
        FOR VERSION AS OF {snapshot_id}
        {query.replace('SELECT * FROM ' + table_name, '')}
        """
    else:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Either timestamp or snapshot_id must be provided'})
        }
    
    try:
        # Execute query via Athena
        response = athena_client.start_query_execution(
            QueryString=time_travel_query,
            ResultConfiguration={
                'OutputLocation': f"s3://{os.environ['ATHENA_RESULTS_BUCKET']}/time-travel-queries/"
            },
            WorkGroup=os.environ.get('ATHENA_WORKGROUP', 'primary')
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'query_execution_id': response['QueryExecutionId'],
                'query': time_travel_query
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def get_table_statistics(table_name):
    """Get Iceberg table statistics and metadata"""
    
    try:
        # This would query Iceberg metadata to get table stats
        # For now, return mock statistics
        stats = {
            'table_name': table_name,
            'total_files': 150,
            'total_size_bytes': 1073741824,  # 1GB
            'record_count': 1000000,
            'partition_count': 30,
            'snapshot_count': 25,
            'last_updated': datetime.now().isoformat(),
            'schema_version': 2,
            'file_format': 'parquet',
            'compression': 'snappy'
        }
        
        return {
            'statusCode': 200,
            'body': json.dumps(stats)
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def evolve_table_schema(event):
    """Handle schema evolution for Iceberg tables"""
    
    table_name = event.get('table_name')
    schema_changes = event.get('schema_changes')  # List of schema change operations
    
    try:
        # This would use Iceberg's schema evolution capabilities
        # For now, return success response
        return {
            'statusCode': 200,
            'body': json.dumps({
                'table_name': table_name,
                'schema_changes_applied': schema_changes,
                'new_schema_version': 3,
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
```

### 3. Data Loading Components

#### Lambda Function for Redshift Loading
```python
import boto3
import psycopg2
import json
from datetime import datetime
import os

def lambda_handler(event, context):
    """Load transformed data from S3 to Redshift"""
    
    # Get Redshift credentials
    secrets_client = boto3.client('secretsmanager')
    redshift_config = get_secret(secrets_client, os.environ['REDSHIFT_SECRET'])
    
    # Connect to Redshift
    conn = psycopg2.connect(
        host=redshift_config['host'],
        port=redshift_config['port'],
        database=redshift_config['database'],
        user=redshift_config['username'],
        password=redshift_config['password']
    )
    
    try:
        with conn.cursor() as cursor:
            # Load dimension tables first
            load_dimension_table(cursor, event['dim_users_s3_path'], 'dim_users')
            load_dimension_table(cursor, event['dim_products_s3_path'], 'dim_products')
            
            # Load fact tables
            load_fact_table(cursor, event['fact_orders_s3_path'], 'fact_orders')
            
            # Update statistics
            cursor.execute("ANALYZE dim_users;")
            cursor.execute("ANALYZE dim_products;")
            cursor.execute("ANALYZE fact_orders;")
            
            conn.commit()
            
        return {
            'statusCode': 200,
            'message': 'Data loaded successfully to Redshift'
        }
        
    except Exception as e:
        conn.rollback()
        raise e
    finally:
        conn.close()

def load_dimension_table(cursor, s3_path, table_name):
    """Load dimension table with SCD Type 2 logic"""
    
    # Create staging table
    staging_table = f"staging.{table_name}_staging"
    
    # Copy data from S3 to staging
    copy_sql = f"""
    COPY {staging_table}
    FROM '{s3_path}'
    IAM_ROLE '{os.environ['REDSHIFT_IAM_ROLE']}'
    FORMAT AS PARQUET;
    """
    cursor.execute(copy_sql)
    
    # Implement SCD Type 2 logic
    if table_name == 'dim_users':
        scd_sql = """
        -- Expire changed records
        UPDATE dim_users 
        SET expiry_date = CURRENT_DATE - 1, is_current = FALSE
        WHERE user_id IN (
            SELECT s.user_id 
            FROM staging.dim_users_staging s
            INNER JOIN dim_users d ON s.user_id = d.user_id
            WHERE d.is_current = TRUE
            AND (s.email != d.email OR s.full_name != d.full_name)
        );
        
        -- Insert new and changed records
        INSERT INTO dim_users
        SELECT * FROM staging.dim_users_staging
        WHERE user_id NOT IN (
            SELECT user_id FROM dim_users WHERE is_current = TRUE
        );
        """
        cursor.execute(scd_sql)

def load_fact_table(cursor, s3_path, table_name):
    """Load fact table with upsert logic"""
    
    staging_table = f"staging.{table_name}_staging"
    
    # Copy data from S3 to staging
    copy_sql = f"""
    COPY {staging_table}
    FROM '{s3_path}'
    IAM_ROLE '{os.environ['REDSHIFT_IAM_ROLE']}'
    FORMAT AS PARQUET;
    """
    cursor.execute(copy_sql)
    
    # Upsert logic for fact table
    upsert_sql = f"""
    -- Delete existing records for the same date
    DELETE FROM {table_name}
    WHERE order_date IN (
        SELECT DISTINCT order_date FROM {staging_table}
    );
    
    -- Insert new records
    INSERT INTO {table_name}
    SELECT * FROM {staging_table};
    """
    cursor.execute(upsert_sql)
```

### 4. Orchestration Components

#### Step Functions State Machine Definition
```json
{
  "Comment": "ETL Pipeline Orchestration",
  "StartAt": "ExtractData",
  "States": {
    "ExtractData": {
      "Type": "Parallel",
      "Branches": [
        {
          "StartAt": "ExtractDatabaseData",
          "States": {
            "ExtractDatabaseData": {
              "Type": "Task",
              "Resource": "arn:aws:states:::glue:startJobRun.sync",
              "Parameters": {
                "JobName": "extract-database-job",
                "Arguments": {
                  "--DATABASE_SECRET": "prod/database/credentials",
                  "--S3_BUCKET": "etl-data-lake-bucket",
                  "--TABLE_NAME": "users"
                }
              },
              "End": true,
              "Retry": [
                {
                  "ErrorEquals": ["States.TaskFailed"],
                  "IntervalSeconds": 30,
                  "MaxAttempts": 3,
                  "BackoffRate": 2.0
                }
              ]
            }
          }
        },
        {
          "StartAt": "ExtractAPIData",
          "States": {
            "ExtractAPIData": {
              "Type": "Task",
              "Resource": "arn:aws:states:::lambda:invoke",
              "Parameters": {
                "FunctionName": "extract-api-data",
                "Payload": {
                  "api_secret_name": "prod/api/credentials",
                  "bucket_name": "etl-data-lake-bucket",
                  "source_name": "orders_api"
                }
              },
              "End": true,
              "Retry": [
                {
                  "ErrorEquals": ["Lambda.ServiceException", "Lambda.AWSLambdaException"],
                  "IntervalSeconds": 10,
                  "MaxAttempts": 3,
                  "BackoffRate": 2.0
                }
              ]
            }
          }
        }
      ],
      "Next": "TransformData"
    },
    "TransformData": {
      "Type": "Parallel",
      "Branches": [
        {
          "StartAt": "TransformUsers",
          "States": {
            "TransformUsers": {
              "Type": "Task",
              "Resource": "arn:aws:states:::glue:startJobRun.sync",
              "Parameters": {
                "JobName": "transform-users-job",
                "Arguments": {
                  "--SOURCE_S3_PATH": "s3://etl-data-lake-bucket/raw-data/source=users/",
                  "--TARGET_S3_PATH": "s3://etl-data-lake-bucket/processed-data/table=dim_users/"
                }
              },
              "End": true
            }
          }
        },
        {
          "StartAt": "TransformOrders",
          "States": {
            "TransformOrders": {
              "Type": "Task",
              "Resource": "arn:aws:states:::glue:startJobRun.sync",
              "Parameters": {
                "JobName": "transform-orders-job",
                "Arguments": {
                  "--SOURCE_S3_PATH": "s3://etl-data-lake-bucket/raw-data/source=orders_api/",
                  "--TARGET_S3_PATH": "s3://etl-data-lake-bucket/processed-data/table=fact_orders/"
                }
              },
              "End": true
            }
          }
        }
      ],
      "Next": "DataQualityCheck"
    },
    "DataQualityCheck": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "data-quality-check",
        "Payload": {
          "s3_paths": [
            "s3://etl-data-lake-bucket/processed-data/table=dim_users/",
            "s3://etl-data-lake-bucket/processed-data/table=fact_orders/"
          ]
        }
      },
      "Next": "LoadToRedshift",
      "Catch": [
        {
          "ErrorEquals": ["States.TaskFailed"],
          "Next": "DataQualityFailure"
        }
      ]
    },
    "LoadToRedshift": {
      "Type": "Task",
      "Resource": "arn:aws:states:::lambda:invoke",
      "Parameters": {
        "FunctionName": "load-to-redshift",
        "Payload": {
          "dim_users_s3_path": "s3://etl-data-lake-bucket/processed-data/table=dim_users/",
          "fact_orders_s3_path": "s3://etl-data-lake-bucket/processed-data/table=fact_orders/"
        }
      },
      "Next": "SendSuccessNotification"
    },
    "SendSuccessNotification": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "TopicArn": "arn:aws:sns:us-east-1:123456789012:etl-notifications",
        "Message": "ETL Pipeline completed successfully",
        "Subject": "ETL Pipeline Success"
      },
      "End": true
    },
    "DataQualityFailure": {
      "Type": "Task",
      "Resource": "arn:aws:states:::sns:publish",
      "Parameters": {
        "TopicArn": "arn:aws:sns:us-east-1:123456789012:etl-notifications",
        "Message": "ETL Pipeline failed at data quality check",
        "Subject": "ETL Pipeline Failure"
      },
      "End": true
    }
  }
}
```

### 5. Streaming Data Components

#### Kinesis Data Processing Lambda
```python
import json
import boto3
import base64
from datetime import datetime

def lambda_handler(event, context):
    """Process streaming data from Kinesis"""
    
    s3_client = boto3.client('s3')
    processed_records = []
    
    for record in event['Records']:
        # Decode Kinesis data
        payload = base64.b64decode(record['kinesis']['data'])
        data = json.loads(payload)
        
        # Transform streaming data
        transformed_data = transform_streaming_record(data)
        
        # Validate data quality
        if validate_streaming_record(transformed_data):
            processed_records.append(transformed_data)
        else:
            # Send to dead letter queue
            send_to_dlq(data, "Data quality validation failed")
    
    # Batch write to S3
    if processed_records:
        write_batch_to_s3(s3_client, processed_records)
    
    return {
        'statusCode': 200,
        'processed_records': len(processed_records)
    }

def transform_streaming_record(data):
    """Transform individual streaming record"""
    return {
        'event_id': data.get('id'),
        'event_type': data.get('type'),
        'user_id': data.get('user_id'),
        'timestamp': datetime.now().isoformat(),
        'properties': data.get('properties', {}),
        'processed_at': datetime.now().isoformat()
    }

def validate_streaming_record(data):
    """Validate streaming record quality"""
    required_fields = ['event_id', 'event_type', 'user_id', 'timestamp']
    return all(field in data and data[field] is not None for field in required_fields)

def write_batch_to_s3(s3_client, records):
    """Write batch of records to S3"""
    timestamp = datetime.now()
    s3_key = f"streaming-data/year={timestamp.year}/month={timestamp.month:02d}/day={timestamp.day:02d}/hour={timestamp.hour:02d}/batch_{timestamp.strftime('%Y%m%d_%H%M%S')}.json"
    
    s3_client.put_object(
        Bucket='etl-data-lake-bucket',
        Key=s3_key,
        Body=json.dumps(records),
        ContentType='application/json'
    )
```

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Data extraction completeness
*For any* scheduled extraction job, all available source records should be extracted without loss.
**Validates: Requirements 1.1, 1.2**

### Property 2: Incremental extraction accuracy
*For any* incremental extraction, only records modified since the last extraction timestamp should be processed.
**Validates: Requirements 1.2**

### Property 3: Transformation data integrity
*For any* transformation operation, the number of input records should equal output records plus quarantined records.
**Validates: Requirements 2.1, 2.4**

### Property 4: Data quality rule enforcement
*For any* data quality rule violation, the record should be quarantined and not loaded to the warehouse.
**Validates: Requirements 7.1, 7.2**

### Property 5: Loading consistency
*For any* successful load operation, all transformed records should be present in the target warehouse table.
**Validates: Requirements 3.1, 3.2**

### Property 6: Workflow dependency ordering
*For any* pipeline execution, extraction must complete before transformation, and transformation before loading.
**Validates: Requirements 4.2**

### Property 7: Retry mechanism reliability
*For any* failed task with retry policy, the system should retry according to configured backoff strategy.
**Validates: Requirements 4.3, 10.1**

### Property 8: Streaming data processing
*For any* streaming event, it should be processed within the configured latency SLA.
**Validates: Requirements 6.1**

### Property 9: Monitoring completeness
*For any* pipeline execution, all activities should be logged with timestamps and status.
**Validates: Requirements 5.1**

### Property 10: Security compliance
*For any* data access operation, proper authentication and encryption should be enforced.
**Validates: Requirements 8.1, 8.2**

### Property 11: Iceberg table format compliance
*For any* processed data write operation, data should be written to Iceberg tables with proper metadata structure and ACID transaction guarantees.
**Validates: Requirements 11.1, 11.2**

### Property 12: Schema evolution backward compatibility
*For any* schema evolution operation, existing queries and data should remain accessible and functional.
**Validates: Requirements 11.3**

### Property 13: Time travel query functionality
*For any* Iceberg table with historical snapshots, queries should be able to access data using both timestamps and snapshot IDs.
**Validates: Requirements 12.1, 12.2**

### Property 14: Snapshot retention policy enforcement
*For any* Iceberg table with configured retention policies, snapshots older than the retention period should be automatically expired.
**Validates: Requirements 12.4**

### Property 15: Automatic table maintenance
*For any* Iceberg table that meets maintenance thresholds, compaction and cleanup operations should be automatically triggered.
**Validates: Requirements 13.1, 13.2, 13.3**

### Property 16: Table statistics accuracy
*For any* Iceberg table operation, table statistics and metadata should be updated to reflect the current state.
**Validates: Requirements 13.4**

### Property 17: Parquet to Iceberg migration integrity
*For any* Parquet to Iceberg migration operation, all source data should be preserved with validated consistency in the target Iceberg table.
**Validates: Requirements 14.1, 14.2, 14.3**

### Property 18: Migration rollback capability
*For any* completed migration, the system should be able to rollback to the original Parquet format while preserving data integrity.
**Validates: Requirements 14.4**

## Testing Strategy

*The testing strategy employs a dual approach combining unit tests for specific scenarios and property-based tests for comprehensive validation of universal properties.*

### Dual Testing Approach

**Unit Tests**: Focus on specific examples, edge cases, and error conditions
- API extraction with various response formats and error conditions
- Data transformation edge cases (null values, malformed data)
- Redshift loading with connection failures and retry scenarios
- Iceberg table creation and schema evolution examples
- Time travel queries with specific timestamps and snapshot IDs

**Property-Based Tests**: Verify universal properties across all inputs (minimum 100 iterations each)
- **Feature: aws-etl-pipeline, Property 1**: Data extraction completeness across all source types
- **Feature: aws-etl-pipeline, Property 2**: Incremental extraction accuracy with various timestamp ranges
- **Feature: aws-etl-pipeline, Property 3**: Transformation data integrity for all data types
- **Feature: aws-etl-pipeline, Property 4**: Data quality rule enforcement across all validation rules
- **Feature: aws-etl-pipeline, Property 5**: Loading consistency for all table types
- **Feature: aws-etl-pipeline, Property 6**: Workflow dependency ordering in all execution scenarios
- **Feature: aws-etl-pipeline, Property 7**: Retry mechanism reliability across all failure types
- **Feature: aws-etl-pipeline, Property 8**: Streaming data processing within SLA bounds
- **Feature: aws-etl-pipeline, Property 9**: Monitoring completeness for all pipeline activities
- **Feature: aws-etl-pipeline, Property 10**: Security compliance for all data operations
- **Feature: aws-etl-pipeline, Property 11**: Iceberg table format compliance for all write operations
- **Feature: aws-etl-pipeline, Property 12**: Schema evolution backward compatibility for all schema changes
- **Feature: aws-etl-pipeline, Property 13**: Time travel query functionality across all historical data
- **Feature: aws-etl-pipeline, Property 14**: Snapshot retention policy enforcement for all tables
- **Feature: aws-etl-pipeline, Property 15**: Automatic table maintenance for all maintenance thresholds
- **Feature: aws-etl-pipeline, Property 16**: Table statistics accuracy for all operations
- **Feature: aws-etl-pipeline, Property 17**: Parquet to Iceberg migration integrity for all data types
- **Feature: aws-etl-pipeline, Property 18**: Migration rollback capability preserving all data

### Iceberg-Specific Testing

**Iceberg Table Operations**:
- Test table creation with various partition schemes and properties
- Validate ACID transaction behavior under concurrent operations
- Test schema evolution scenarios (add columns, change types, rename fields)
- Verify time travel queries across multiple snapshots and time ranges

**Iceberg Maintenance Testing**:
- Test file compaction with various file sizes and counts
- Validate snapshot expiration with different retention policies
- Test orphaned file cleanup after failed operations
- Verify table statistics updates after maintenance operations

**Migration Testing**:
- Test Parquet to Iceberg conversion with various data types and structures
- Validate data consistency before and after migration
- Test rollback scenarios with partial migrations
- Verify query compatibility after migration

### Testing Framework Configuration

**Property-Based Testing Library**: Use Hypothesis (Python) or fast-check (JavaScript/TypeScript)
**Test Execution**: Each property test runs minimum 100 iterations with randomized inputs
**Test Environment**: Isolated test environment with mock AWS services and test data
**Continuous Integration**: All tests run automatically on code changes with failure notifications

## Error Handling

### Pipeline-Level Error Handling
- Implement circuit breaker pattern for external service calls
- Use exponential backoff for transient failures
- Implement dead letter queues for unprocessable messages
- Maintain data lineage for error tracking and recovery

### Data Quality Error Handling
- Quarantine invalid records with detailed error descriptions
- Implement data quality dashboards for monitoring trends
- Send alerts when quality thresholds are breached
- Provide data steward interfaces for manual review

### Infrastructure Error Handling
- Implement multi-AZ deployment for high availability
- Use AWS Auto Scaling for compute resources
- Implement backup and restore procedures
- Monitor resource utilization and costs

## Security Implementation

### Data Encryption
- Encrypt data at rest using AWS KMS
- Encrypt data in transit using TLS/SSL
- Implement field-level encryption for PII data
- Use AWS Secrets Manager for credential management

### Access Control
- Implement least privilege IAM policies
- Use VPC endpoints for secure service communication
- Enable AWS CloudTrail for audit logging
- Implement data masking for non-production environments

## Performance Optimization

### Compute Optimization
- Use appropriate instance types for workloads
- Implement auto-scaling based on queue depth
- Optimize Spark configurations for Glue jobs
- Use columnar storage formats (Parquet) for analytics

### Storage Optimization
- Implement S3 lifecycle policies for cost optimization
- Use S3 Transfer Acceleration for large file uploads
- Partition data by date and other relevant dimensions
- Compress data using appropriate algorithms

## Monitoring and Alerting

### CloudWatch Metrics
- Pipeline execution duration and success rate
- Data volume processed per job
- Error rates and types
- Resource utilization metrics

### Custom Dashboards
- Real-time pipeline status dashboard
- Data quality metrics dashboard
- Cost optimization dashboard
- Performance trending dashboard

### Alert Configuration
- Pipeline failure alerts via SNS
- Data quality threshold breaches
- Resource utilization alerts
- Cost anomaly detection alerts

## Deployment Strategy

### Infrastructure as Code
- Use AWS CloudFormation or Terraform for infrastructure
- Implement CI/CD pipelines for code deployment
- Use AWS CodePipeline for automated deployments
- Implement blue-green deployment for zero downtime

### Environment Management
- Separate development, staging, and production environments
- Use parameter store for environment-specific configurations
- Implement automated testing in staging environment
- Use feature flags for gradual rollouts