#!/bin/bash

set -e

# Script to deploy Glue ETL jobs
# Usage: ./deploy-glue-jobs.sh <environment> <build_number>

ENVIRONMENT=$1
BUILD_NUMBER=$2
PROJECT_NAME="etl-pipeline"
AWS_REGION=${AWS_DEFAULT_REGION:-us-east-1}

if [ -z "$ENVIRONMENT" ]; then
    echo "Error: Environment parameter is required"
    echo "Usage: ./deploy-glue-jobs.sh <environment> <build_number>"
    exit 1
fi

if [ -z "$BUILD_NUMBER" ]; then
    echo "Error: Build number parameter is required"
    echo "Usage: ./deploy-glue-jobs.sh <environment> <build_number>"
    exit 1
fi

echo "=========================================="
echo "Deploying Glue ETL Jobs to $ENVIRONMENT"
echo "Build Number: $BUILD_NUMBER"
echo "AWS Region: $AWS_REGION"
echo "=========================================="

# Set environment-specific parameters
case $ENVIRONMENT in
    "dev"|"development")
        STACK_PREFIX="${PROJECT_NAME}-dev"
        ;;
    "staging")
        STACK_PREFIX="${PROJECT_NAME}-staging"
        ;;
    "prod"|"production")
        STACK_PREFIX="${PROJECT_NAME}-prod"
        ;;
    *)
        echo "Error: Invalid environment. Use dev, staging, or prod"
        exit 1
        ;;
esac

# Get IAM role ARN for Glue
GLUE_ROLE_ARN=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_PREFIX}-foundation" \
    --query 'Stacks[0].Outputs[?OutputKey==`GlueServiceRoleArn`].OutputValue' \
    --output text \
    --region $AWS_REGION)

if [ -z "$GLUE_ROLE_ARN" ]; then
    echo "Error: Could not retrieve Glue service role ARN"
    exit 1
fi

echo "Using Glue Role: $GLUE_ROLE_ARN"

# Function to create or update Glue job
deploy_glue_job() {
    local job_name=$1
    local script_location=$2
    local description=$3
    local max_capacity=${4:-2}
    
    echo "Deploying Glue job: $job_name"
    
    # Check if job exists
    if aws glue get-job --job-name "$job_name" --region $AWS_REGION > /dev/null 2>&1; then
        echo "Updating existing Glue job: $job_name"
        aws glue update-job \
            --job-name "$job_name" \
            --job-update '{
                "Role": "'$GLUE_ROLE_ARN'",
                "Command": {
                    "Name": "glueetl",
                    "ScriptLocation": "'$script_location'",
                    "PythonVersion": "3"
                },
                "DefaultArguments": {
                    "--TempDir": "s3://'$ARTIFACTS_BUCKET'/glue-temp/",
                    "--job-bookmark-option": "job-bookmark-enable",
                    "--enable-metrics": "",
                    "--enable-continuous-cloudwatch-log": "true"
                },
                "MaxCapacity": '$max_capacity',
                "GlueVersion": "3.0",
                "Timeout": 2880,
                "MaxRetries": 1
            }' \
            --region $AWS_REGION
    else
        echo "Creating new Glue job: $job_name"
        aws glue create-job \
            --name "$job_name" \
            --role "$GLUE_ROLE_ARN" \
            --command '{
                "Name": "glueetl",
                "ScriptLocation": "'$script_location'",
                "PythonVersion": "3"
            }' \
            --default-arguments '{
                "--TempDir": "s3://'$ARTIFACTS_BUCKET'/glue-temp/",
                "--job-bookmark-option": "job-bookmark-enable",
                "--enable-metrics": "",
                "--enable-continuous-cloudwatch-log": "true"
            }' \
            --max-capacity $max_capacity \
            --glue-version "3.0" \
            --timeout 2880 \
            --max-retries 1 \
            --description "$description" \
            --region $AWS_REGION
    fi
    
    echo "Successfully deployed Glue job: $job_name"
}

# Deploy User Transformation Job
deploy_glue_job \
    "${STACK_PREFIX}-transform-users" \
    "s3://${ARTIFACTS_BUCKET}/glue-scripts/${BUILD_NUMBER}/transform_users.py" \
    "Transform raw user data into dimension table format" \
    2

# Deploy Orders Transformation Job
deploy_glue_job \
    "${STACK_PREFIX}-transform-orders" \
    "s3://${ARTIFACTS_BUCKET}/glue-scripts/${BUILD_NUMBER}/transform_orders.py" \
    "Transform raw order data into fact table format" \
    4

# Deploy Products Transformation Job
deploy_glue_job \
    "${STACK_PREFIX}-transform-products" \
    "s3://${ARTIFACTS_BUCKET}/glue-scripts/${BUILD_NUMBER}/transform_products.py" \
    "Transform raw product data into dimension table format" \
    2

# Deploy Data Quality Job
deploy_glue_job \
    "${STACK_PREFIX}-data-quality-check" \
    "s3://${ARTIFACTS_BUCKET}/glue-scripts/${BUILD_NUMBER}/data_quality_check.py" \
    "Perform comprehensive data quality checks" \
    2

# Deploy Database Extraction Job
deploy_glue_job \
    "${STACK_PREFIX}-extract-database" \
    "s3://${ARTIFACTS_BUCKET}/glue-scripts/${BUILD_NUMBER}/extract_database.py" \
    "Extract data from source databases" \
    4

# Create Glue Crawlers for automatic schema discovery
echo "Creating Glue crawlers..."

# Crawler for raw data
CRAWLER_NAME="${STACK_PREFIX}-raw-data-crawler"
if aws glue get-crawler --name "$CRAWLER_NAME" --region $AWS_REGION > /dev/null 2>&1; then
    echo "Updating crawler: $CRAWLER_NAME"
    aws glue update-crawler \
        --name "$CRAWLER_NAME" \
        --role "$GLUE_ROLE_ARN" \
        --database-name "${STACK_PREFIX}-catalog" \
        --targets '{
            "S3Targets": [
                {
                    "Path": "s3://'$(aws cloudformation describe-stacks --stack-name "${STACK_PREFIX}-foundation" --query 'Stacks[0].Outputs[?OutputKey==`DataLakeBucketName`].OutputValue' --output text --region $AWS_REGION)'/raw-data/"
                }
            ]
        }' \
        --region $AWS_REGION
else
    echo "Creating crawler: $CRAWLER_NAME"
    aws glue create-crawler \
        --name "$CRAWLER_NAME" \
        --role "$GLUE_ROLE_ARN" \
        --database-name "${STACK_PREFIX}-catalog" \
        --targets '{
            "S3Targets": [
                {
                    "Path": "s3://'$(aws cloudformation describe-stacks --stack-name "${STACK_PREFIX}-foundation" --query 'Stacks[0].Outputs[?OutputKey==`DataLakeBucketName`].OutputValue' --output text --region $AWS_REGION)'/raw-data/"
                }
            ]
        }' \
        --description "Crawler for raw data in S3 data lake" \
        --region $AWS_REGION
fi

# Crawler for processed data
CRAWLER_NAME="${STACK_PREFIX}-processed-data-crawler"
if aws glue get-crawler --name "$CRAWLER_NAME" --region $AWS_REGION > /dev/null 2>&1; then
    echo "Updating crawler: $CRAWLER_NAME"
    aws glue update-crawler \
        --name "$CRAWLER_NAME" \
        --role "$GLUE_ROLE_ARN" \
        --database-name "${STACK_PREFIX}-catalog" \
        --targets '{
            "S3Targets": [
                {
                    "Path": "s3://'$(aws cloudformation describe-stacks --stack-name "${STACK_PREFIX}-foundation" --query 'Stacks[0].Outputs[?OutputKey==`DataLakeBucketName`].OutputValue' --output text --region $AWS_REGION)'/processed-data/"
                }
            ]
        }' \
        --region $AWS_REGION
else
    echo "Creating crawler: $CRAWLER_NAME"
    aws glue create-crawler \
        --name "$CRAWLER_NAME" \
        --role "$GLUE_ROLE_ARN" \
        --database-name "${STACK_PREFIX}-catalog" \
        --targets '{
            "S3Targets": [
                {
                    "Path": "s3://'$(aws cloudformation describe-stacks --stack-name "${STACK_PREFIX}-foundation" --query 'Stacks[0].Outputs[?OutputKey==`DataLakeBucketName`].OutputValue' --output text --region $AWS_REGION)'/processed-data/"
                }
            ]
        }' \
        --description "Crawler for processed data in S3 data lake" \
        --region $AWS_REGION
fi

# Create Glue Database if it doesn't exist
DATABASE_NAME="${STACK_PREFIX}-catalog"
if ! aws glue get-database --name "$DATABASE_NAME" --region $AWS_REGION > /dev/null 2>&1; then
    echo "Creating Glue database: $DATABASE_NAME"
    aws glue create-database \
        --database-input '{
            "Name": "'$DATABASE_NAME'",
            "Description": "Data catalog for ETL pipeline"
        }' \
        --region $AWS_REGION
fi

echo "=========================================="
echo "Glue Jobs Deployment Completed!"
echo "Environment: $ENVIRONMENT"
echo "Build Number: $BUILD_NUMBER"
echo "=========================================="

echo "Deployed Glue Jobs:"
echo "- ${STACK_PREFIX}-transform-users"
echo "- ${STACK_PREFIX}-transform-orders"
echo "- ${STACK_PREFIX}-transform-products"
echo "- ${STACK_PREFIX}-data-quality-check"
echo "- ${STACK_PREFIX}-extract-database"

echo ""
echo "Deployed Glue Crawlers:"
echo "- ${STACK_PREFIX}-raw-data-crawler"
echo "- ${STACK_PREFIX}-processed-data-crawler"

echo ""
echo "You can monitor the jobs in the AWS Glue console:"
echo "https://console.aws.amazon.com/glue/home?region=${AWS_REGION}#etl:tab=jobs"