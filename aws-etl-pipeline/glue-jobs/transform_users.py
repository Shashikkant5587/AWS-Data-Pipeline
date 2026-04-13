import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame
from pyspark.sql import DataFrame
from pyspark.sql.functions import *
from pyspark.sql.types import *
from pyspark.sql.window import Window
import boto3
from datetime import datetime
import logging

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Get job parameters
args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'SOURCE_S3_PATH',
    'TARGET_S3_PATH',
    'DATABASE_NAME',
    'TABLE_NAME'
])

# Initialize Glue context
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Initialize AWS clients
s3_client = boto3.client('s3')
glue_client = boto3.client('glue')

def main():
    """Main ETL function for transforming user data"""
    
    logger.info("Pipeline trigger validation change for CI/CD email flow")
    logger.info(f"Starting user data transformation job: {args['JOB_NAME']}")
    logger.info(f"Source path: {args['SOURCE_S3_PATH']}")
    logger.info(f"Target path: {args['TARGET_S3_PATH']}")
    
    try:
        # Read raw user data from S3
        raw_users_df = read_raw_data()
        
        if raw_users_df.count() == 0:
            logger.warning("No data found in source path")
            return
        
        logger.info(f"Read {raw_users_df.count()} raw user records")
        
        # Transform the data
        transformed_df = transform_user_data(raw_users_df)
        
        # Apply data quality rules
        clean_df, quarantine_df = apply_data_quality_rules(transformed_df)
        
        logger.info(f"Clean records: {clean_df.count()}")
        logger.info(f"Quarantined records: {quarantine_df.count()}")
        
        # Write clean data to target location
        write_clean_data(clean_df)
        
        # Write quarantined data to separate location
        if quarantine_df.count() > 0:
            write_quarantine_data(quarantine_df)
        
        # Update Glue Data Catalog
        update_data_catalog()
        
        logger.info("User data transformation completed successfully")
        
    except Exception as e:
        logger.error(f"Error in user data transformation: {str(e)}")
        raise

def read_raw_data() -> DataFrame:
    """Read raw user data from S3"""
    
    try:
        # Create DynamicFrame from S3
        raw_dynamic_frame = glueContext.create_dynamic_frame.from_options(
            connection_type="s3",
            connection_options={
                "paths": [args['SOURCE_S3_PATH']],
                "recurse": True
            },
            format="json"
        )
        
        # Convert to DataFrame
        raw_df = raw_dynamic_frame.toDF()
        
        # Flatten nested JSON structure if needed
        if 'records' in raw_df.columns:
            # Extract records array and explode it
            records_df = raw_df.select(explode(col('records')).alias('record'))
            flattened_df = records_df.select('record.*')
            return flattened_df
        else:
            return raw_df
            
    except Exception as e:
        logger.error(f"Error reading raw data: {str(e)}")
        raise

def transform_user_data(raw_df: DataFrame) -> DataFrame:
    """Transform raw user data into dimension table format"""
    
    try:
        # Define transformation logic
        transformed_df = raw_df.select(
            # Basic user information
            col("user_id").cast(LongType()).alias("user_id"),
            col("username").alias("username"),
            lower(trim(col("email"))).alias("email"),
            
            # Name fields with null handling
            coalesce(col("first_name"), lit("")).alias("first_name"),
            coalesce(col("last_name"), lit("")).alias("last_name"),
            
            # Concatenate full name
            concat_ws(" ", 
                     coalesce(col("first_name"), lit("")),
                     coalesce(col("last_name"), lit(""))
            ).alias("full_name"),
            
            # Date fields
            to_date(col("created_at")).alias("created_date"),
            to_date(col("updated_at")).alias("updated_date"),
            
            # Status field with standardization
            when(lower(col("status")) == "active", True)
            .when(lower(col("status")) == "inactive", False)
            .otherwise(False).alias("is_active"),
            
            # SCD Type 2 fields
            current_date().alias("effective_date"),
            lit("9999-12-31").cast(DateType()).alias("expiry_date"),
            lit(True).alias("is_current"),
            
            # Audit fields
            current_timestamp().alias("created_timestamp"),
            current_timestamp().alias("updated_timestamp"),
            
            # Keep original extraction timestamp
            col("_extraction_timestamp").alias("extraction_timestamp")
        )
        
        # Handle duplicates - keep the latest record per user_id
        window_spec = Window.partitionBy("user_id").orderBy(desc("updated_date"))
        deduped_df = transformed_df.withColumn("row_num", row_number().over(window_spec)) \
                                  .filter(col("row_num") == 1) \
                                  .drop("row_num")
        
        return deduped_df
        
    except Exception as e:
        logger.error(f"Error transforming user data: {str(e)}")
        raise

def apply_data_quality_rules(df: DataFrame) -> tuple[DataFrame, DataFrame]:
    """Apply data quality rules and separate clean vs quarantined records"""
    
    try:
        # Add data quality flags
        quality_df = df.withColumn(
            "dq_user_id_not_null", 
            when(col("user_id").isNull(), "FAIL").otherwise("PASS")
        ).withColumn(
            "dq_email_format", 
            when(col("email").rlike(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'), "PASS")
            .otherwise("FAIL")
        ).withColumn(
            "dq_username_not_empty", 
            when((col("username").isNull()) | (trim(col("username")) == ""), "FAIL")
            .otherwise("PASS")
        ).withColumn(
            "dq_created_date_valid", 
            when(col("created_date").isNull(), "FAIL").otherwise("PASS")
        )
        
        # Create overall quality flag
        quality_df = quality_df.withColumn(
            "overall_quality",
            when(
                (col("dq_user_id_not_null") == "PASS") &
                (col("dq_email_format") == "PASS") &
                (col("dq_username_not_empty") == "PASS") &
                (col("dq_created_date_valid") == "PASS"),
                "PASS"
            ).otherwise("FAIL")
        )
        
        # Add quality check timestamp
        quality_df = quality_df.withColumn("quality_check_timestamp", current_timestamp())
        
        # Separate clean and quarantined records
        clean_df = quality_df.filter(col("overall_quality") == "PASS") \
                            .drop("dq_user_id_not_null", "dq_email_format", 
                                  "dq_username_not_empty", "dq_created_date_valid", 
                                  "overall_quality", "quality_check_timestamp")
        
        quarantine_df = quality_df.filter(col("overall_quality") == "FAIL")
        
        return clean_df, quarantine_df
        
    except Exception as e:
        logger.error(f"Error applying data quality rules: {str(e)}")
        raise

def write_clean_data(df: DataFrame) -> None:
    """Write clean data to target S3 location"""
    
    try:
        # Convert DataFrame to DynamicFrame
        dynamic_frame = DynamicFrame.fromDF(df, glueContext, "clean_users")
        
        # Write to S3 in Parquet format with partitioning
        glueContext.write_dynamic_frame.from_options(
            frame=dynamic_frame,
            connection_type="s3",
            connection_options={
                "path": args['TARGET_S3_PATH'],
                "partitionKeys": ["created_date"]
            },
            format="parquet",
            format_options={
                "compression": "snappy"
            }
        )
        
        logger.info(f"Clean data written to: {args['TARGET_S3_PATH']}")
        
    except Exception as e:
        logger.error(f"Error writing clean data: {str(e)}")
        raise

def write_quarantine_data(df: DataFrame) -> None:
    """Write quarantined data to separate S3 location"""
    
    try:
        # Determine quarantine path
        quarantine_path = args['TARGET_S3_PATH'].replace('/processed-data/', '/quarantine-data/')
        
        # Convert DataFrame to DynamicFrame
        dynamic_frame = DynamicFrame.fromDF(df, glueContext, "quarantine_users")
        
        # Write to S3 in JSON format for easier inspection
        glueContext.write_dynamic_frame.from_options(
            frame=dynamic_frame,
            connection_type="s3",
            connection_options={
                "path": quarantine_path,
                "partitionKeys": ["quality_check_timestamp"]
            },
            format="json"
        )
        
        logger.info(f"Quarantined data written to: {quarantine_path}")
        
    except Exception as e:
        logger.error(f"Error writing quarantine data: {str(e)}")
        raise

def update_data_catalog() -> None:
    """Update Glue Data Catalog with new table metadata"""
    
    try:
        # Update table in Glue Data Catalog
        table_input = {
            'Name': args['TABLE_NAME'],
            'StorageDescriptor': {
                'Columns': [
                    {'Name': 'user_id', 'Type': 'bigint'},
                    {'Name': 'username', 'Type': 'string'},
                    {'Name': 'email', 'Type': 'string'},
                    {'Name': 'first_name', 'Type': 'string'},
                    {'Name': 'last_name', 'Type': 'string'},
                    {'Name': 'full_name', 'Type': 'string'},
                    {'Name': 'created_date', 'Type': 'date'},
                    {'Name': 'updated_date', 'Type': 'date'},
                    {'Name': 'is_active', 'Type': 'boolean'},
                    {'Name': 'effective_date', 'Type': 'date'},
                    {'Name': 'expiry_date', 'Type': 'date'},
                    {'Name': 'is_current', 'Type': 'boolean'},
                    {'Name': 'created_timestamp', 'Type': 'timestamp'},
                    {'Name': 'updated_timestamp', 'Type': 'timestamp'},
                    {'Name': 'extraction_timestamp', 'Type': 'string'}
                ],
                'Location': args['TARGET_S3_PATH'],
                'InputFormat': 'org.apache.hadoop.mapred.TextInputFormat',
                'OutputFormat': 'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat',
                'SerdeInfo': {
                    'SerializationLibrary': 'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe'
                }
            },
            'PartitionKeys': [
                {'Name': 'created_date', 'Type': 'date'}
            ]
        }
        
        try:
            glue_client.update_table(
                DatabaseName=args['DATABASE_NAME'],
                TableInput=table_input
            )
            logger.info(f"Updated table {args['TABLE_NAME']} in Glue Data Catalog")
        except glue_client.exceptions.EntityNotFoundException:
            glue_client.create_table(
                DatabaseName=args['DATABASE_NAME'],
                TableInput=table_input
            )
            logger.info(f"Created table {args['TABLE_NAME']} in Glue Data Catalog")
            
    except Exception as e:
        logger.error(f"Error updating Glue Data Catalog: {str(e)}")
        # Don't raise exception here as catalog update is not critical for data processing

if __name__ == "__main__":
    main()
    job.commit()