import json
import boto3
import psycopg2
import pymysql
from datetime import datetime, timedelta
import os
import logging
from typing import Dict, List, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3_client = boto3.client('s3')
secrets_client = boto3.client('secretsmanager')
ssm_client = boto3.client('ssm')

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Extract data from database and store in S3
    
    Expected event structure:
    {
        "database_secret": "etl-pipeline/source-db/credentials",
        "table_name": "users",
        "s3_bucket": "etl-pipeline-data-lake-123456789012",
        "extraction_type": "full|incremental",
        "incremental_column": "updated_at",
        "batch_size": 10000
    }
    """
    try:
        # Validate input parameters
        required_params = ['database_secret', 'table_name', 's3_bucket']
        for param in required_params:
            if param not in event:
                raise ValueError(f"Missing required parameter: {param}")
        
        # Get configuration
        database_secret = event['database_secret']
        table_name = event['table_name']
        s3_bucket = event['s3_bucket']
        extraction_type = event.get('extraction_type', 'incremental')
        incremental_column = event.get('incremental_column', 'updated_at')
        batch_size = event.get('batch_size', 10000)
        
        logger.info(f"Starting {extraction_type} extraction for table: {table_name}")
        
        # Get database credentials
        db_config = get_secret(database_secret)
        
        # Determine last extraction timestamp for incremental loads
        last_extraction_time = None
        if extraction_type == 'incremental':
            last_extraction_time = get_last_extraction_timestamp(table_name)
            logger.info(f"Last extraction timestamp: {last_extraction_time}")
        
        # Connect to database and extract data
        if db_config['engine'] == 'postgresql':
            records = extract_postgresql_data(db_config, table_name, incremental_column, 
                                            last_extraction_time, batch_size)
        elif db_config['engine'] == 'mysql':
            records = extract_mysql_data(db_config, table_name, incremental_column, 
                                       last_extraction_time, batch_size)
        else:
            raise ValueError(f"Unsupported database engine: {db_config['engine']}")
        
        # Store data in S3
        if records:
            s3_key = generate_s3_key(table_name, datetime.now())
            store_data_s3(records, s3_bucket, s3_key)
            
            # Update last extraction timestamp
            if extraction_type == 'incremental':
                update_last_extraction_timestamp(table_name, datetime.now())
            
            logger.info(f"Successfully extracted {len(records)} records from {table_name}")
            
            return {
                'statusCode': 200,
                'body': {
                    'message': 'Data extraction completed successfully',
                    'records_extracted': len(records),
                    's3_location': f"s3://{s3_bucket}/{s3_key}",
                    'extraction_type': extraction_type,
                    'table_name': table_name
                }
            }
        else:
            logger.info(f"No new records found for table: {table_name}")
            return {
                'statusCode': 200,
                'body': {
                    'message': 'No new records to extract',
                    'records_extracted': 0,
                    'extraction_type': extraction_type,
                    'table_name': table_name
                }
            }
            
    except Exception as e:
        logger.error(f"Error in data extraction: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'error': str(e),
                'table_name': event.get('table_name', 'unknown')
            }
        }

def get_secret(secret_name: str) -> Dict[str, Any]:
    """Retrieve database credentials from AWS Secrets Manager"""
    try:
        response = secrets_client.get_secret_value(SecretId=secret_name)
        return json.loads(response['SecretString'])
    except Exception as e:
        logger.error(f"Error retrieving secret {secret_name}: {str(e)}")
        raise

def extract_postgresql_data(db_config: Dict[str, Any], table_name: str, 
                          incremental_column: str, last_extraction_time: Optional[datetime],
                          batch_size: int) -> List[Dict[str, Any]]:
    """Extract data from PostgreSQL database"""
    connection = None
    try:
        # Connect to PostgreSQL
        connection = psycopg2.connect(
            host=db_config['host'],
            port=db_config['port'],
            database=db_config['database'],
            user=db_config['username'],
            password=db_config['password']
        )
        
        cursor = connection.cursor()
        
        # Build query based on extraction type
        if last_extraction_time:
            query = f"""
                SELECT * FROM {table_name} 
                WHERE {incremental_column} > %s 
                ORDER BY {incremental_column}
                LIMIT %s
            """
            cursor.execute(query, (last_extraction_time, batch_size))
        else:
            query = f"SELECT * FROM {table_name} LIMIT %s"
            cursor.execute(query, (batch_size,))
        
        # Get column names
        columns = [desc[0] for desc in cursor.description]
        
        # Fetch all records
        records = []
        for row in cursor.fetchall():
            record = dict(zip(columns, row))
            # Convert datetime objects to ISO format strings
            for key, value in record.items():
                if isinstance(value, datetime):
                    record[key] = value.isoformat()
            records.append(record)
        
        return records
        
    except Exception as e:
        logger.error(f"Error extracting PostgreSQL data: {str(e)}")
        raise
    finally:
        if connection:
            connection.close()

def extract_mysql_data(db_config: Dict[str, Any], table_name: str, 
                      incremental_column: str, last_extraction_time: Optional[datetime],
                      batch_size: int) -> List[Dict[str, Any]]:
    """Extract data from MySQL database"""
    connection = None
    try:
        # Connect to MySQL
        connection = pymysql.connect(
            host=db_config['host'],
            port=db_config['port'],
            database=db_config['database'],
            user=db_config['username'],
            password=db_config['password'],
            cursorclass=pymysql.cursors.DictCursor
        )
        
        with connection.cursor() as cursor:
            # Build query based on extraction type
            if last_extraction_time:
                query = f"""
                    SELECT * FROM {table_name} 
                    WHERE {incremental_column} > %s 
                    ORDER BY {incremental_column}
                    LIMIT %s
                """
                cursor.execute(query, (last_extraction_time, batch_size))
            else:
                query = f"SELECT * FROM {table_name} LIMIT %s"
                cursor.execute(query, (batch_size,))
            
            records = cursor.fetchall()
            
            # Convert datetime objects to ISO format strings
            for record in records:
                for key, value in record.items():
                    if isinstance(value, datetime):
                        record[key] = value.isoformat()
            
            return records
        
    except Exception as e:
        logger.error(f"Error extracting MySQL data: {str(e)}")
        raise
    finally:
        if connection:
            connection.close()

def generate_s3_key(table_name: str, extraction_time: datetime) -> str:
    """Generate S3 key with partitioning"""
    return (f"raw-data/source=database/"
            f"table={table_name}/"
            f"year={extraction_time.year}/"
            f"month={extraction_time.month:02d}/"
            f"day={extraction_time.day:02d}/"
            f"hour={extraction_time.hour:02d}/"
            f"{table_name}_{extraction_time.strftime('%Y%m%d_%H%M%S')}.json")

def store_data_s3(records: List[Dict[str, Any]], bucket: str, key: str) -> None:
    """Store extracted data in S3"""
    try:
        # Add extraction metadata
        data_with_metadata = {
            'extraction_timestamp': datetime.now().isoformat(),
            'record_count': len(records),
            'records': records
        }
        
        # Upload to S3
        s3_client.put_object(
            Bucket=bucket,
            Key=key,
            Body=json.dumps(data_with_metadata, default=str),
            ContentType='application/json',
            ServerSideEncryption='AES256'
        )
        
        logger.info(f"Data stored in S3: s3://{bucket}/{key}")
        
    except Exception as e:
        logger.error(f"Error storing data in S3: {str(e)}")
        raise

def get_last_extraction_timestamp(table_name: str) -> Optional[datetime]:
    """Get last extraction timestamp from SSM Parameter Store"""
    try:
        parameter_name = f"/etl-pipeline/last-extraction/{table_name}"
        response = ssm_client.get_parameter(Name=parameter_name)
        return datetime.fromisoformat(response['Parameter']['Value'])
    except ssm_client.exceptions.ParameterNotFound:
        logger.info(f"No previous extraction timestamp found for {table_name}")
        return None
    except Exception as e:
        logger.error(f"Error retrieving last extraction timestamp: {str(e)}")
        return None

def update_last_extraction_timestamp(table_name: str, timestamp: datetime) -> None:
    """Update last extraction timestamp in SSM Parameter Store"""
    try:
        parameter_name = f"/etl-pipeline/last-extraction/{table_name}"
        ssm_client.put_parameter(
            Name=parameter_name,
            Value=timestamp.isoformat(),
            Type='String',
            Overwrite=True,
            Description=f'Last extraction timestamp for {table_name}'
        )
        logger.info(f"Updated last extraction timestamp for {table_name}: {timestamp}")
    except Exception as e:
        logger.error(f"Error updating last extraction timestamp: {str(e)}")
        raise