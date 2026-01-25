import json
import boto3
import pandas as pd
from datetime import datetime
import logging
from typing import Dict, List, Any, Optional
import re

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3_client = boto3.client('s3')
sns_client = boto3.client('sns')

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Perform data quality checks on processed data
    
    Expected event structure:
    {
        "s3_paths": [
            "s3://bucket/processed-data/table=dim_users/",
            "s3://bucket/processed-data/table=fact_orders/"
        ],
        "quality_rules": {
            "dim_users": [
                {"rule": "not_null", "column": "user_id"},
                {"rule": "email_format", "column": "email"},
                {"rule": "unique", "column": "user_id"}
            ],
            "fact_orders": [
                {"rule": "not_null", "column": "order_id"},
                {"rule": "positive", "column": "total_amount"}
            ]
        }
    }
    """
    try:
        logger.info("Starting data quality checks")
        
        s3_paths = event.get('s3_paths', [])
        quality_rules = event.get('quality_rules', {})
        
        if not s3_paths:
            raise ValueError("No S3 paths provided for data quality checks")
        
        quality_results = []
        overall_quality_passed = True
        
        for s3_path in s3_paths:
            logger.info(f"Checking data quality for: {s3_path}")
            
            # Extract table name from S3 path
            table_name = extract_table_name_from_path(s3_path)
            
            # Get quality rules for this table
            table_rules = quality_rules.get(table_name, [])
            
            if not table_rules:
                logger.warning(f"No quality rules defined for table: {table_name}")
                continue
            
            # Read data from S3
            try:
                df = read_parquet_from_s3(s3_path)
                if df.empty:
                    logger.warning(f"No data found in {s3_path}")
                    continue
                    
                logger.info(f"Read {len(df)} records from {table_name}")
                
            except Exception as e:
                logger.error(f"Error reading data from {s3_path}: {e}")
                quality_results.append({
                    'table_name': table_name,
                    's3_path': s3_path,
                    'status': 'FAILED',
                    'error': f"Could not read data: {str(e)}"
                })
                overall_quality_passed = False
                continue
            
            # Apply quality rules
            table_quality_result = apply_quality_rules(df, table_name, table_rules)
            quality_results.append(table_quality_result)
            
            if not table_quality_result['passed']:
                overall_quality_passed = False
        
        # Generate quality report
        quality_report = generate_quality_report(quality_results)
        
        # Store quality report in S3
        report_s3_key = store_quality_report(quality_report)
        
        # Send alerts if quality checks failed
        if not overall_quality_passed:
            send_quality_alert(quality_report)
        
        return {
            'statusCode': 200,
            'quality_passed': overall_quality_passed,
            'quality_report': quality_report,
            'report_s3_location': report_s3_key,
            'tables_checked': len(quality_results),
            'timestamp': datetime.now().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Error in data quality checks: {str(e)}")
        return {
            'statusCode': 500,
            'quality_passed': False,
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        }

def extract_table_name_from_path(s3_path: str) -> str:
    """Extract table name from S3 path"""
    # Extract table name from path like s3://bucket/processed-data/table=dim_users/
    import re
    match = re.search(r'table=([^/]+)', s3_path)
    return match.group(1) if match else 'unknown'

def read_parquet_from_s3(s3_path: str) -> pd.DataFrame:
    """Read Parquet files from S3 path"""
    # Parse S3 path
    if not s3_path.startswith('s3://'):
        raise ValueError(f"Invalid S3 path: {s3_path}")
    
    path_parts = s3_path.replace('s3://', '').split('/', 1)
    bucket = path_parts[0]
    prefix = path_parts[1] if len(path_parts) > 1 else ''
    
    # List all Parquet files in the path
    response = s3_client.list_objects_v2(Bucket=bucket, Prefix=prefix)
    
    if 'Contents' not in response:
        return pd.DataFrame()
    
    parquet_files = [obj['Key'] for obj in response['Contents'] 
                    if obj['Key'].endswith('.parquet')]
    
    if not parquet_files:
        return pd.DataFrame()
    
    # Read and combine all Parquet files
    dfs = []
    for file_key in parquet_files[:10]:  # Limit to first 10 files for performance
        try:
            obj = s3_client.get_object(Bucket=bucket, Key=file_key)
            df = pd.read_parquet(obj['Body'])
            dfs.append(df)
        except Exception as e:
            logger.warning(f"Could not read {file_key}: {e}")
    
    return pd.concat(dfs, ignore_index=True) if dfs else pd.DataFrame()

def apply_quality_rules(df: pd.DataFrame, table_name: str, rules: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Apply quality rules to DataFrame"""
    
    rule_results = []
    table_passed = True
    
    for rule in rules:
        rule_type = rule.get('rule')
        column = rule.get('column')
        
        if column not in df.columns:
            rule_results.append({
                'rule': rule_type,
                'column': column,
                'status': 'FAILED',
                'message': f"Column '{column}' not found in data",
                'failed_count': 0,
                'total_count': len(df)
            })
            table_passed = False
            continue
        
        # Apply specific rule
        if rule_type == 'not_null':
            result = check_not_null(df, column)
        elif rule_type == 'unique':
            result = check_unique(df, column)
        elif rule_type == 'email_format':
            result = check_email_format(df, column)
        elif rule_type == 'positive':
            result = check_positive(df, column)
        elif rule_type == 'range':
            min_val = rule.get('min_value')
            max_val = rule.get('max_value')
            result = check_range(df, column, min_val, max_val)
        elif rule_type == 'foreign_key':
            # For foreign key checks, we'd need to load the reference table
            # For now, just check not null
            result = check_not_null(df, column)
        else:
            result = {
                'status': 'FAILED',
                'message': f"Unknown rule type: {rule_type}",
                'failed_count': 0,
                'total_count': len(df)
            }
        
        result['rule'] = rule_type
        result['column'] = column
        rule_results.append(result)
        
        if result['status'] == 'FAILED':
            table_passed = False
    
    return {
        'table_name': table_name,
        'passed': table_passed,
        'total_records': len(df),
        'rules_checked': len(rules),
        'rule_results': rule_results,
        'timestamp': datetime.now().isoformat()
    }

def check_not_null(df: pd.DataFrame, column: str) -> Dict[str, Any]:
    """Check for null values"""
    null_count = df[column].isnull().sum()
    total_count = len(df)
    
    return {
        'status': 'PASSED' if null_count == 0 else 'FAILED',
        'message': f"Found {null_count} null values out of {total_count} records",
        'failed_count': null_count,
        'total_count': total_count,
        'pass_rate': (total_count - null_count) / total_count if total_count > 0 else 0
    }

def check_unique(df: pd.DataFrame, column: str) -> Dict[str, Any]:
    """Check for unique values"""
    total_count = len(df)
    unique_count = df[column].nunique()
    duplicate_count = total_count - unique_count
    
    return {
        'status': 'PASSED' if duplicate_count == 0 else 'FAILED',
        'message': f"Found {duplicate_count} duplicate values out of {total_count} records",
        'failed_count': duplicate_count,
        'total_count': total_count,
        'pass_rate': unique_count / total_count if total_count > 0 else 0
    }

def check_email_format(df: pd.DataFrame, column: str) -> Dict[str, Any]:
    """Check email format"""
    email_pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    
    # Remove null values for this check
    non_null_series = df[column].dropna()
    total_count = len(non_null_series)
    
    if total_count == 0:
        return {
            'status': 'PASSED',
            'message': 'No non-null values to check',
            'failed_count': 0,
            'total_count': 0,
            'pass_rate': 1.0
        }
    
    valid_emails = non_null_series.str.match(email_pattern)
    invalid_count = (~valid_emails).sum()
    
    return {
        'status': 'PASSED' if invalid_count == 0 else 'FAILED',
        'message': f"Found {invalid_count} invalid email formats out of {total_count} records",
        'failed_count': invalid_count,
        'total_count': total_count,
        'pass_rate': (total_count - invalid_count) / total_count
    }

def check_positive(df: pd.DataFrame, column: str) -> Dict[str, Any]:
    """Check for positive values"""
    non_null_series = df[column].dropna()
    total_count = len(non_null_series)
    
    if total_count == 0:
        return {
            'status': 'PASSED',
            'message': 'No non-null values to check',
            'failed_count': 0,
            'total_count': 0,
            'pass_rate': 1.0
        }
    
    negative_count = (non_null_series <= 0).sum()
    
    return {
        'status': 'PASSED' if negative_count == 0 else 'FAILED',
        'message': f"Found {negative_count} non-positive values out of {total_count} records",
        'failed_count': negative_count,
        'total_count': total_count,
        'pass_rate': (total_count - negative_count) / total_count
    }

def check_range(df: pd.DataFrame, column: str, min_val: Optional[float], max_val: Optional[float]) -> Dict[str, Any]:
    """Check value range"""
    non_null_series = df[column].dropna()
    total_count = len(non_null_series)
    
    if total_count == 0:
        return {
            'status': 'PASSED',
            'message': 'No non-null values to check',
            'failed_count': 0,
            'total_count': 0,
            'pass_rate': 1.0
        }
    
    out_of_range = pd.Series([False] * total_count, index=non_null_series.index)
    
    if min_val is not None:
        out_of_range |= (non_null_series < min_val)
    
    if max_val is not None:
        out_of_range |= (non_null_series > max_val)
    
    failed_count = out_of_range.sum()
    
    return {
        'status': 'PASSED' if failed_count == 0 else 'FAILED',
        'message': f"Found {failed_count} values outside range [{min_val}, {max_val}] out of {total_count} records",
        'failed_count': failed_count,
        'total_count': total_count,
        'pass_rate': (total_count - failed_count) / total_count
    }

def generate_quality_report(quality_results: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Generate comprehensive quality report"""
    
    total_tables = len(quality_results)
    passed_tables = sum(1 for result in quality_results if result.get('passed', False))
    
    return {
        'summary': {
            'total_tables_checked': total_tables,
            'tables_passed': passed_tables,
            'tables_failed': total_tables - passed_tables,
            'overall_pass_rate': passed_tables / total_tables if total_tables > 0 else 0,
            'check_timestamp': datetime.now().isoformat()
        },
        'table_results': quality_results,
        'recommendations': generate_recommendations(quality_results)
    }

def generate_recommendations(quality_results: List[Dict[str, Any]]) -> List[str]:
    """Generate recommendations based on quality results"""
    recommendations = []
    
    for result in quality_results:
        if not result.get('passed', True):
            table_name = result.get('table_name', 'unknown')
            
            for rule_result in result.get('rule_results', []):
                if rule_result.get('status') == 'FAILED':
                    rule_type = rule_result.get('rule')
                    column = rule_result.get('column')
                    failed_count = rule_result.get('failed_count', 0)
                    
                    if rule_type == 'not_null':
                        recommendations.append(f"Add null value handling for {table_name}.{column} ({failed_count} null values)")
                    elif rule_type == 'unique':
                        recommendations.append(f"Investigate duplicate values in {table_name}.{column} ({failed_count} duplicates)")
                    elif rule_type == 'email_format':
                        recommendations.append(f"Improve email validation for {table_name}.{column} ({failed_count} invalid formats)")
                    elif rule_type == 'positive':
                        recommendations.append(f"Check negative values in {table_name}.{column} ({failed_count} non-positive values)")
    
    return recommendations

def store_quality_report(quality_report: Dict[str, Any]) -> str:
    """Store quality report in S3"""
    try:
        bucket_name = os.environ.get('DATA_LAKE_BUCKET')
        if not bucket_name:
            logger.warning("DATA_LAKE_BUCKET environment variable not set")
            return ""
        
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        s3_key = f"quality-reports/year={datetime.now().year}/month={datetime.now().month:02d}/day={datetime.now().day:02d}/quality_report_{timestamp}.json"
        
        s3_client.put_object(
            Bucket=bucket_name,
            Key=s3_key,
            Body=json.dumps(quality_report, indent=2),
            ContentType='application/json'
        )
        
        logger.info(f"Quality report stored at s3://{bucket_name}/{s3_key}")
        return f"s3://{bucket_name}/{s3_key}"
        
    except Exception as e:
        logger.error(f"Error storing quality report: {e}")
        return ""

def send_quality_alert(quality_report: Dict[str, Any]) -> None:
    """Send SNS alert for quality failures"""
    try:
        # This would be configured with an SNS topic ARN
        topic_arn = os.environ.get('QUALITY_ALERT_TOPIC_ARN')
        if not topic_arn:
            logger.warning("QUALITY_ALERT_TOPIC_ARN not configured")
            return
        
        summary = quality_report.get('summary', {})
        failed_tables = summary.get('tables_failed', 0)
        
        message = f"""
Data Quality Alert - ETL Pipeline

Summary:
- Tables Checked: {summary.get('total_tables_checked', 0)}
- Tables Failed: {failed_tables}
- Overall Pass Rate: {summary.get('overall_pass_rate', 0):.2%}

Recommendations:
{chr(10).join(quality_report.get('recommendations', []))}

Timestamp: {summary.get('check_timestamp')}
        """
        
        sns_client.publish(
            TopicArn=topic_arn,
            Subject=f"Data Quality Alert - {failed_tables} Tables Failed",
            Message=message
        )
        
        logger.info("Quality alert sent via SNS")
        
    except Exception as e:
        logger.error(f"Error sending quality alert: {e}")