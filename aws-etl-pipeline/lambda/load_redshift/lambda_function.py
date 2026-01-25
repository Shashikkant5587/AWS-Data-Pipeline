import json
import boto3
import psycopg2
from datetime import datetime
import os
import logging
from typing import Dict, List, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3_client = boto3.client('s3')
secrets_client = boto3.client('secretsmanager')

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Load transformed data from S3 to Redshift
    
    Expected event structure:
    {
        "tables_to_load": [
            {
                "table_name": "dim_users",
                "s3_path": "s3://bucket/processed-data/table=dim_users/",
                "load_type": "scd2"
            },
            {
                "table_name": "fact_orders",
                "s3_path": "s3://bucket/processed-data/table=fact_orders/",
                "load_type": "upsert"
            }
        ]
    }
    """
    try:
        logger.info("Starting Redshift data loading")
        
        tables_to_load = event.get('tables_to_load', [])
        
        if not tables_to_load:
            raise ValueError("No tables specified for loading")
        
        # Get Redshift credentials
        redshift_config = get_redshift_credentials()
        
        # Connect to Redshift
        connection = connect_to_redshift(redshift_config)
        
        load_results = []
        
        try:
            with connection.cursor() as cursor:
                for table_config in tables_to_load:
                    table_name = table_config['table_name']
                    s3_path = table_config['s3_path']
                    load_type = table_config.get('load_type', 'replace')
                    
                    logger.info(f"Loading {table_name} from {s3_path} using {load_type} strategy")
                    
                    try:
                        if load_type == 'scd2':
                            result = load_dimension_table_scd2(cursor, table_name, s3_path, redshift_config)
                        elif load_type == 'upsert':
                            result = load_fact_table_upsert(cursor, table_name, s3_path, redshift_config)
                        elif load_type == 'replace':
                            result = load_table_replace(cursor, table_name, s3_path, redshift_config)
                        else:
                            raise ValueError(f"Unknown load type: {load_type}")
                        
                        load_results.append({
                            'table_name': table_name,
                            'status': 'SUCCESS',
                            'records_loaded': result.get('records_loaded', 0),
                            'load_type': load_type
                        })
                        
                        logger.info(f"Successfully loaded {table_name}")
                        
                    except Exception as e:
                        logger.error(f"Error loading {table_name}: {e}")
                        load_results.append({
                            'table_name': table_name,
                            'status': 'FAILED',
                            'error': str(e),
                            'load_type': load_type
                        })
                        # Continue with other tables
                
                # Update table statistics
                update_table_statistics(cursor, [r['table_name'] for r in load_results if r['status'] == 'SUCCESS'])
                
                connection.commit()
                
        except Exception as e:
            connection.rollback()
            raise e
        finally:
            connection.close()
        
        # Check if any loads failed
        failed_loads = [r for r in load_results if r['status'] == 'FAILED']
        success_loads = [r for r in load_results if r['status'] == 'SUCCESS']
        
        return {
            'statusCode': 200 if not failed_loads else 500,
            'message': f"Loaded {len(success_loads)} tables successfully, {len(failed_loads)} failed",
            'load_results': load_results,
            'total_tables': len(tables_to_load),
            'successful_loads': len(success_loads),
            'failed_loads': len(failed_loads),
            'timestamp': datetime.now().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Error in Redshift loading: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        }

def get_redshift_credentials() -> Dict[str, str]:
    """Get Redshift credentials from Secrets Manager"""
    try:
        secret_name = os.environ.get('REDSHIFT_SECRET')
        if not secret_name:
            raise ValueError("REDSHIFT_SECRET environment variable not set")
        
        response = secrets_client.get_secret_value(SecretId=secret_name)
        return json.loads(response['SecretString'])
        
    except Exception as e:
        logger.error(f"Error retrieving Redshift credentials: {e}")
        raise

def connect_to_redshift(config: Dict[str, str]) -> psycopg2.extensions.connection:
    """Connect to Redshift cluster"""
    try:
        connection = psycopg2.connect(
            host=config['host'],
            port=config['port'],
            database=config['database'],
            user=config['username'],
            password=config['password'],
            sslmode='require'
        )
        
        logger.info("Successfully connected to Redshift")
        return connection
        
    except Exception as e:
        logger.error(f"Error connecting to Redshift: {e}")
        raise

def load_dimension_table_scd2(cursor, table_name: str, s3_path: str, redshift_config: Dict[str, str]) -> Dict[str, Any]:
    """Load dimension table using SCD Type 2 logic"""
    
    staging_table = f"staging.{table_name}_staging"
    target_table = f"dimensions.{table_name}"
    
    try:
        # Create staging table
        create_staging_table_sql = f"""
        CREATE TABLE IF NOT EXISTS {staging_table} (LIKE {target_table});
        TRUNCATE {staging_table};
        """
        cursor.execute(create_staging_table_sql)
        
        # Copy data from S3 to staging
        copy_sql = f"""
        COPY {staging_table}
        FROM '{s3_path}'
        IAM_ROLE '{os.environ.get('REDSHIFT_IAM_ROLE')}'
        FORMAT AS PARQUET
        TIMEFORMAT 'auto'
        DATEFORMAT 'auto';
        """
        cursor.execute(copy_sql)
        
        # Get count of staged records
        cursor.execute(f"SELECT COUNT(*) FROM {staging_table}")
        staged_count = cursor.fetchone()[0]
        
        if staged_count == 0:
            logger.warning(f"No data found in staging table {staging_table}")
            return {'records_loaded': 0}
        
        # Implement SCD Type 2 logic
        if table_name == 'dim_users':
            scd2_sql = f"""
            -- Step 1: Expire changed records
            UPDATE {target_table} 
            SET expiry_date = CURRENT_DATE - 1, 
                is_current = FALSE,
                updated_timestamp = CURRENT_TIMESTAMP
            WHERE user_id IN (
                SELECT s.user_id 
                FROM {staging_table} s
                INNER JOIN {target_table} d ON s.user_id = d.user_id
                WHERE d.is_current = TRUE
                AND (s.email != d.email 
                     OR s.full_name != d.full_name 
                     OR s.is_active != d.is_active)
            );
            
            -- Step 2: Insert new and changed records
            INSERT INTO {target_table} (
                user_id, username, email, first_name, last_name, full_name,
                created_date, updated_date, is_active, effective_date, 
                expiry_date, is_current, created_timestamp, updated_timestamp
            )
            SELECT 
                s.user_id, s.username, s.email, s.first_name, s.last_name, s.full_name,
                s.created_date, s.updated_date, s.is_active, s.effective_date,
                s.expiry_date, s.is_current, s.created_timestamp, s.updated_timestamp
            FROM {staging_table} s
            WHERE NOT EXISTS (
                SELECT 1 FROM {target_table} d 
                WHERE d.user_id = s.user_id AND d.is_current = TRUE
            );
            """
            cursor.execute(scd2_sql)
            
        elif table_name == 'dim_products':
            scd2_sql = f"""
            -- Step 1: Expire changed records
            UPDATE {target_table} 
            SET expiry_date = CURRENT_DATE - 1, 
                is_current = FALSE,
                updated_timestamp = CURRENT_TIMESTAMP
            WHERE product_id IN (
                SELECT s.product_id 
                FROM {staging_table} s
                INNER JOIN {target_table} d ON s.product_id = d.product_id
                WHERE d.is_current = TRUE
                AND (s.product_name != d.product_name 
                     OR s.price != d.price 
                     OR s.category != d.category)
            );
            
            -- Step 2: Insert new and changed records
            INSERT INTO {target_table} (
                product_id, product_name, category, price, description,
                created_date, effective_date, expiry_date, is_current,
                created_timestamp, updated_timestamp
            )
            SELECT 
                s.product_id, s.product_name, s.category, s.price, s.description,
                s.created_date, s.effective_date, s.expiry_date, s.is_current,
                s.created_timestamp, s.updated_timestamp
            FROM {staging_table} s
            WHERE NOT EXISTS (
                SELECT 1 FROM {target_table} d 
                WHERE d.product_id = s.product_id AND d.is_current = TRUE
            );
            """
            cursor.execute(scd2_sql)
        
        # Get final count
        cursor.execute(f"SELECT COUNT(*) FROM {target_table} WHERE is_current = TRUE")
        final_count = cursor.fetchone()[0]
        
        logger.info(f"SCD2 load completed for {table_name}: {staged_count} staged, {final_count} current records")
        
        return {'records_loaded': staged_count}
        
    except Exception as e:
        logger.error(f"Error in SCD2 load for {table_name}: {e}")
        raise

def load_fact_table_upsert(cursor, table_name: str, s3_path: str, redshift_config: Dict[str, str]) -> Dict[str, Any]:
    """Load fact table using upsert logic"""
    
    staging_table = f"staging.{table_name}_staging"
    target_table = f"facts.{table_name}"
    
    try:
        # Create staging table
        create_staging_table_sql = f"""
        CREATE TABLE IF NOT EXISTS {staging_table} (LIKE {target_table});
        TRUNCATE {staging_table};
        """
        cursor.execute(create_staging_table_sql)
        
        # Copy data from S3 to staging
        copy_sql = f"""
        COPY {staging_table}
        FROM '{s3_path}'
        IAM_ROLE '{os.environ.get('REDSHIFT_IAM_ROLE')}'
        FORMAT AS PARQUET
        TIMEFORMAT 'auto'
        DATEFORMAT 'auto';
        """
        cursor.execute(copy_sql)
        
        # Get count of staged records
        cursor.execute(f"SELECT COUNT(*) FROM {staging_table}")
        staged_count = cursor.fetchone()[0]
        
        if staged_count == 0:
            logger.warning(f"No data found in staging table {staging_table}")
            return {'records_loaded': 0}
        
        # Implement upsert logic for fact tables
        if table_name == 'fact_orders':
            upsert_sql = f"""
            -- Delete existing records for the same date range
            DELETE FROM {target_table}
            WHERE order_date IN (
                SELECT DISTINCT order_date FROM {staging_table}
            );
            
            -- Insert all records from staging
            INSERT INTO {target_table} (
                order_id, user_key, product_key, order_date_key, order_date,
                quantity, unit_price, total_amount, order_status,
                created_timestamp, updated_timestamp
            )
            SELECT 
                s.order_id,
                COALESCE(u.user_key, -1) as user_key,
                COALESCE(p.product_key, -1) as product_key,
                COALESCE(d.date_key, -1) as order_date_key,
                s.order_date,
                s.quantity,
                s.unit_price,
                s.total_amount,
                s.order_status,
                s.created_timestamp,
                s.updated_timestamp
            FROM {staging_table} s
            LEFT JOIN dimensions.dim_users u ON s.user_id = u.user_id AND u.is_current = TRUE
            LEFT JOIN dimensions.dim_products p ON s.product_id = p.product_id AND p.is_current = TRUE
            LEFT JOIN dimensions.dim_date d ON s.order_date = d.full_date;
            """
            cursor.execute(upsert_sql)
        
        # Get final count
        cursor.execute(f"SELECT COUNT(*) FROM {target_table}")
        final_count = cursor.fetchone()[0]
        
        logger.info(f"Upsert load completed for {table_name}: {staged_count} staged, {final_count} total records")
        
        return {'records_loaded': staged_count}
        
    except Exception as e:
        logger.error(f"Error in upsert load for {table_name}: {e}")
        raise

def load_table_replace(cursor, table_name: str, s3_path: str, redshift_config: Dict[str, str]) -> Dict[str, Any]:
    """Load table using replace strategy"""
    
    target_table = f"staging.{table_name}"
    
    try:
        # Truncate target table
        cursor.execute(f"TRUNCATE {target_table}")
        
        # Copy data from S3
        copy_sql = f"""
        COPY {target_table}
        FROM '{s3_path}'
        IAM_ROLE '{os.environ.get('REDSHIFT_IAM_ROLE')}'
        FORMAT AS PARQUET
        TIMEFORMAT 'auto'
        DATEFORMAT 'auto';
        """
        cursor.execute(copy_sql)
        
        # Get count of loaded records
        cursor.execute(f"SELECT COUNT(*) FROM {target_table}")
        loaded_count = cursor.fetchone()[0]
        
        logger.info(f"Replace load completed for {table_name}: {loaded_count} records")
        
        return {'records_loaded': loaded_count}
        
    except Exception as e:
        logger.error(f"Error in replace load for {table_name}: {e}")
        raise

def update_table_statistics(cursor, table_names: List[str]) -> None:
    """Update table statistics for query optimization"""
    
    try:
        for table_name in table_names:
            # Determine schema based on table name
            if table_name.startswith('dim_'):
                full_table_name = f"dimensions.{table_name}"
            elif table_name.startswith('fact_'):
                full_table_name = f"facts.{table_name}"
            else:
                full_table_name = f"staging.{table_name}"
            
            analyze_sql = f"ANALYZE {full_table_name};"
            cursor.execute(analyze_sql)
            logger.info(f"Updated statistics for {full_table_name}")
            
    except Exception as e:
        logger.error(f"Error updating table statistics: {e}")
        # Don't raise exception as this is not critical