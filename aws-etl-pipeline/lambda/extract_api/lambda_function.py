import json
import boto3
import requests
from datetime import datetime, timedelta
import time
import os
import logging
from typing import Dict, List, Any, Optional
from urllib.parse import urljoin, urlparse
import hashlib

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3_client = boto3.client('s3')
secrets_client = boto3.client('secretsmanager')
ssm_client = boto3.client('ssm')

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Extract data from REST API and store in S3
    
    Expected event structure:
    {
        "api_secret": "etl-pipeline/api/credentials",
        "endpoint_name": "orders",
        "s3_bucket": "etl-pipeline-data-lake-123456789012",
        "extraction_type": "full|incremental",
        "incremental_field": "updated_at",
        "page_size": 1000,
        "max_pages": 100
    }
    """
    try:
        # Validate input parameters
        required_params = ['api_secret', 'endpoint_name', 's3_bucket']
        for param in required_params:
            if param not in event:
                raise ValueError(f"Missing required parameter: {param}")
        
        # Get configuration
        api_secret = event['api_secret']
        endpoint_name = event['endpoint_name']
        s3_bucket = event['s3_bucket']
        extraction_type = event.get('extraction_type', 'incremental')
        incremental_field = event.get('incremental_field', 'updated_at')
        page_size = event.get('page_size', 1000)
        max_pages = event.get('max_pages', 100)
        
        logger.info(f"Starting {extraction_type} API extraction for endpoint: {endpoint_name}")
        
        # Get API credentials and configuration
        api_config = get_secret(api_secret)
        
        # Determine last extraction timestamp for incremental loads
        last_extraction_time = None
        if extraction_type == 'incremental':
            last_extraction_time = get_last_extraction_timestamp(endpoint_name)
            logger.info(f"Last extraction timestamp: {last_extraction_time}")
        
        # Extract data from API
        all_records = extract_api_data(
            api_config, endpoint_name, incremental_field, 
            last_extraction_time, page_size, max_pages
        )
        
        # Store data in S3
        if all_records:
            s3_key = generate_s3_key(endpoint_name, datetime.now())
            store_data_s3(all_records, s3_bucket, s3_key)
            
            # Update last extraction timestamp
            if extraction_type == 'incremental':
                update_last_extraction_timestamp(endpoint_name, datetime.now())
            
            logger.info(f"Successfully extracted {len(all_records)} records from {endpoint_name}")
            
            return {
                'statusCode': 200,
                'body': {
                    'message': 'API data extraction completed successfully',
                    'records_extracted': len(all_records),
                    's3_location': f"s3://{s3_bucket}/{s3_key}",
                    'extraction_type': extraction_type,
                    'endpoint_name': endpoint_name
                }
            }
        else:
            logger.info(f"No new records found for endpoint: {endpoint_name}")
            return {
                'statusCode': 200,
                'body': {
                    'message': 'No new records to extract',
                    'records_extracted': 0,
                    'extraction_type': extraction_type,
                    'endpoint_name': endpoint_name
                }
            }
            
    except Exception as e:
        logger.error(f"Error in API data extraction: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'error': str(e),
                'endpoint_name': event.get('endpoint_name', 'unknown')
            }
        }

def get_secret(secret_name: str) -> Dict[str, Any]:
    """Retrieve API credentials from AWS Secrets Manager"""
    try:
        response = secrets_client.get_secret_value(SecretId=secret_name)
        return json.loads(response['SecretString'])
    except Exception as e:
        logger.error(f"Error retrieving secret {secret_name}: {str(e)}")
        raise

def extract_api_data(api_config: Dict[str, Any], endpoint_name: str, 
                    incremental_field: str, last_extraction_time: Optional[datetime],
                    page_size: int, max_pages: int) -> List[Dict[str, Any]]:
    """Extract data from REST API with pagination and rate limiting"""
    
    all_records = []
    page = 1
    total_pages_processed = 0
    
    # Prepare authentication headers
    headers = prepare_auth_headers(api_config)
    
    # Get endpoint configuration
    endpoint_config = api_config['endpoints'].get(endpoint_name)
    if not endpoint_config:
        raise ValueError(f"Endpoint configuration not found for: {endpoint_name}")
    
    base_url = api_config['base_url']
    endpoint_path = endpoint_config['path']
    
    try:
        while total_pages_processed < max_pages:
            # Prepare request parameters
            params = {
                'page': page,
                'limit': page_size
            }
            
            # Add incremental filter if specified
            if last_extraction_time and incremental_field:
                params[f'{incremental_field}_since'] = last_extraction_time.isoformat()
            
            # Add any endpoint-specific parameters
            if 'default_params' in endpoint_config:
                params.update(endpoint_config['default_params'])
            
            # Make API request
            url = urljoin(base_url, endpoint_path)
            logger.info(f"Requesting page {page} from {url}")
            
            response = make_api_request(url, headers, params, api_config.get('timeout', 30))
            
            if response.status_code != 200:
                logger.error(f"API request failed with status {response.status_code}: {response.text}")
                break
            
            data = response.json()
            
            # Extract records based on API response structure
            records = extract_records_from_response(data, endpoint_config)
            
            if not records:
                logger.info("No more records found, stopping pagination")
                break
            
            # Add extraction metadata to each record
            for record in records:
                record['_extraction_timestamp'] = datetime.now().isoformat()
                record['_extraction_page'] = page
                record['_source_endpoint'] = endpoint_name
            
            all_records.extend(records)
            logger.info(f"Extracted {len(records)} records from page {page}")
            
            # Check if we've reached the end of data
            if len(records) < page_size:
                logger.info("Received fewer records than page size, assuming end of data")
                break
            
            page += 1
            total_pages_processed += 1
            
            # Rate limiting - respect API limits
            rate_limit_delay = api_config.get('rate_limit_delay', 0.1)
            time.sleep(rate_limit_delay)
        
        logger.info(f"Total records extracted: {len(all_records)} from {total_pages_processed} pages")
        return all_records
        
    except Exception as e:
        logger.error(f"Error during API data extraction: {str(e)}")
        raise

def prepare_auth_headers(api_config: Dict[str, Any]) -> Dict[str, str]:
    """Prepare authentication headers based on API configuration"""
    headers = {
        'Content-Type': 'application/json',
        'User-Agent': 'ETL-Pipeline/1.0'
    }
    
    auth_type = api_config.get('auth_type', 'none')
    
    if auth_type == 'bearer':
        headers['Authorization'] = f"Bearer {api_config['token']}"
    elif auth_type == 'api_key':
        key_name = api_config.get('api_key_header', 'X-API-Key')
        headers[key_name] = api_config['api_key']
    elif auth_type == 'basic':
        import base64
        credentials = f"{api_config['username']}:{api_config['password']}"
        encoded_credentials = base64.b64encode(credentials.encode()).decode()
        headers['Authorization'] = f"Basic {encoded_credentials}"
    
    # Add any custom headers
    if 'custom_headers' in api_config:
        headers.update(api_config['custom_headers'])
    
    return headers

def make_api_request(url: str, headers: Dict[str, str], params: Dict[str, Any], 
                    timeout: int) -> requests.Response:
    """Make API request with retry logic"""
    max_retries = 3
    retry_delay = 1
    
    for attempt in range(max_retries):
        try:
            response = requests.get(
                url, 
                headers=headers, 
                params=params, 
                timeout=timeout
            )
            
            # Handle rate limiting (HTTP 429)
            if response.status_code == 429:
                retry_after = int(response.headers.get('Retry-After', retry_delay))
                logger.warning(f"Rate limited, waiting {retry_after} seconds")
                time.sleep(retry_after)
                continue
            
            return response
            
        except requests.exceptions.RequestException as e:
            logger.warning(f"Request attempt {attempt + 1} failed: {str(e)}")
            if attempt < max_retries - 1:
                time.sleep(retry_delay * (2 ** attempt))  # Exponential backoff
            else:
                raise
    
    raise Exception(f"Failed to make API request after {max_retries} attempts")

def extract_records_from_response(data: Dict[str, Any], 
                                endpoint_config: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Extract records from API response based on endpoint configuration"""
    
    # Default path to records in response
    records_path = endpoint_config.get('records_path', 'data')
    
    # Navigate to records using dot notation (e.g., 'data.items')
    records = data
    for path_part in records_path.split('.'):
        if isinstance(records, dict) and path_part in records:
            records = records[path_part]
        else:
            logger.warning(f"Could not find records at path: {records_path}")
            return []
    
    # Ensure records is a list
    if not isinstance(records, list):
        logger.warning(f"Records is not a list: {type(records)}")
        return []
    
    return records

def generate_s3_key(endpoint_name: str, extraction_time: datetime) -> str:
    """Generate S3 key with partitioning"""
    return (f"raw-data/source=api/"
            f"endpoint={endpoint_name}/"
            f"year={extraction_time.year}/"
            f"month={extraction_time.month:02d}/"
            f"day={extraction_time.day:02d}/"
            f"hour={extraction_time.hour:02d}/"
            f"{endpoint_name}_{extraction_time.strftime('%Y%m%d_%H%M%S')}.json")

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

def get_last_extraction_timestamp(endpoint_name: str) -> Optional[datetime]:
    """Get last extraction timestamp from SSM Parameter Store"""
    try:
        parameter_name = f"/etl-pipeline/last-extraction/api/{endpoint_name}"
        response = ssm_client.get_parameter(Name=parameter_name)
        return datetime.fromisoformat(response['Parameter']['Value'])
    except ssm_client.exceptions.ParameterNotFound:
        logger.info(f"No previous extraction timestamp found for {endpoint_name}")
        return None
    except Exception as e:
        logger.error(f"Error retrieving last extraction timestamp: {str(e)}")
        return None

def update_last_extraction_timestamp(endpoint_name: str, timestamp: datetime) -> None:
    """Update last extraction timestamp in SSM Parameter Store"""
    try:
        parameter_name = f"/etl-pipeline/last-extraction/api/{endpoint_name}"
        ssm_client.put_parameter(
            Name=parameter_name,
            Value=timestamp.isoformat(),
            Type='String',
            Overwrite=True,
            Description=f'Last extraction timestamp for API endpoint {endpoint_name}'
        )
        logger.info(f"Updated last extraction timestamp for {endpoint_name}: {timestamp}")
    except Exception as e:
        logger.error(f"Error updating last extraction timestamp: {str(e)}")
        raise