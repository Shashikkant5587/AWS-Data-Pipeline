#!/bin/bash

set -e

# Script to deploy ETL Pipeline infrastructure using CloudFormation
# Usage: ./deploy.sh <environment> <build_number>

ENVIRONMENT=$1
BUILD_NUMBER=$2
PROJECT_NAME="etl-pipeline"
AWS_REGION=${AWS_DEFAULT_REGION:-us-east-1}

if [ -z "$ENVIRONMENT" ]; then
    echo "Error: Environment parameter is required"
    echo "Usage: ./deploy.sh <environment> <build_number>"
    exit 1
fi

if [ -z "$BUILD_NUMBER" ]; then
    echo "Error: Build number parameter is required"
    echo "Usage: ./deploy.sh <environment> <build_number>"
    exit 1
fi

echo "=========================================="
echo "Deploying ETL Pipeline to $ENVIRONMENT"
echo "Build Number: $BUILD_NUMBER"
echo "AWS Region: $AWS_REGION"
echo "=========================================="

# Set environment-specific parameters
case $ENVIRONMENT in
    "dev"|"development")
        STACK_PREFIX="${PROJECT_NAME}-dev"
        REDSHIFT_NODE_TYPE="dc2.large"
        REDSHIFT_CLUSTER_TYPE="single-node"
        ENABLE_LOGGING="false"
        ;;
    "staging")
        STACK_PREFIX="${PROJECT_NAME}-staging"
        REDSHIFT_NODE_TYPE="dc2.large"
        REDSHIFT_CLUSTER_TYPE="single-node"
        ENABLE_LOGGING="true"
        ;;
    "prod"|"production")
        STACK_PREFIX="${PROJECT_NAME}-prod"
        REDSHIFT_NODE_TYPE="dc2.large"
        REDSHIFT_CLUSTER_TYPE="multi-node"
        ENABLE_LOGGING="true"
        ;;
    *)
        echo "Error: Invalid environment. Use dev, staging, or prod"
        exit 1
        ;;
esac

# Function to check if stack exists
stack_exists() {
    aws cloudformation describe-stacks --stack-name $1 --region $AWS_REGION > /dev/null 2>&1
}

# Function to wait for stack operation to complete
wait_for_stack() {
    local stack_name=$1
    local operation=$2
    
    echo "Waiting for stack $operation to complete..."
    aws cloudformation wait stack-${operation}-complete --stack-name $stack_name --region $AWS_REGION
    
    if [ $? -eq 0 ]; then
        echo "Stack $operation completed successfully"
    else
        echo "Stack $operation failed"
        aws cloudformation describe-stack-events --stack-name $stack_name --region $AWS_REGION --max-items 10
        exit 1
    fi
}

# Deploy IAM roles and S3 bucket (Foundation stack)
echo "Deploying foundation infrastructure..."
FOUNDATION_STACK="${STACK_PREFIX}-foundation"

if stack_exists $FOUNDATION_STACK; then
    echo "Updating foundation stack..."
    aws cloudformation update-stack \
        --stack-name $FOUNDATION_STACK \
        --template-url "https://${ARTIFACTS_BUCKET}.s3.amazonaws.com/cloudformation/${BUILD_NUMBER}/01-iam-roles.yaml" \
        --parameters ParameterKey=ProjectName,ParameterValue=$STACK_PREFIX \
                    ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
        --capabilities CAPABILITY_NAMED_IAM \
        --region $AWS_REGION
    
    wait_for_stack $FOUNDATION_STACK "update"
else
    echo "Creating foundation stack..."
    aws cloudformation create-stack \
        --stack-name $FOUNDATION_STACK \
        --template-url "https://${ARTIFACTS_BUCKET}.s3.amazonaws.com/cloudformation/${BUILD_NUMBER}/01-iam-roles.yaml" \
        --parameters ParameterKey=ProjectName,ParameterValue=$STACK_PREFIX \
                    ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
        --capabilities CAPABILITY_NAMED_IAM \
        --region $AWS_REGION
    
    wait_for_stack $FOUNDATION_STACK "create"
fi

# Deploy VPC and Networking (if needed)
echo "Deploying networking infrastructure..."
NETWORK_STACK="${STACK_PREFIX}-network"

if stack_exists $NETWORK_STACK; then
    echo "Updating network stack..."
    aws cloudformation update-stack \
        --stack-name $NETWORK_STACK \
        --template-url "https://${ARTIFACTS_BUCKET}.s3.amazonaws.com/cloudformation/${BUILD_NUMBER}/02-vpc-network.yaml" \
        --parameters ParameterKey=ProjectName,ParameterValue=$STACK_PREFIX \
                    ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
        --region $AWS_REGION
    
    wait_for_stack $NETWORK_STACK "update"
else
    echo "Creating network stack..."
    aws cloudformation create-stack \
        --stack-name $NETWORK_STACK \
        --template-url "https://${ARTIFACTS_BUCKET}.s3.amazonaws.com/cloudformation/${BUILD_NUMBER}/02-vpc-network.yaml" \
        --parameters ParameterKey=ProjectName,ParameterValue=$STACK_PREFIX \
                    ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
        --region $AWS_REGION
    
    wait_for_stack $NETWORK_STACK "create"
fi

# Deploy Redshift Data Warehouse
echo "Deploying Redshift data warehouse..."
REDSHIFT_STACK="${STACK_PREFIX}-redshift"

# Generate random password for Redshift if not provided
if [ -z "$REDSHIFT_PASSWORD" ]; then
    REDSHIFT_PASSWORD=$(openssl rand -base64 12)
    echo "Generated Redshift password (store securely): $REDSHIFT_PASSWORD"
fi

if stack_exists $REDSHIFT_STACK; then
    echo "Updating Redshift stack..."
    aws cloudformation update-stack \
        --stack-name $REDSHIFT_STACK \
        --template-url "https://${ARTIFACTS_BUCKET}.s3.amazonaws.com/cloudformation/${BUILD_NUMBER}/03-redshift.yaml" \
        --parameters ParameterKey=ProjectName,ParameterValue=$STACK_PREFIX \
                    ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
                    ParameterKey=RedshiftUsername,ParameterValue=etladmin \
                    ParameterKey=RedshiftPassword,ParameterValue=$REDSHIFT_PASSWORD \
                    ParameterKey=NodeType,ParameterValue=$REDSHIFT_NODE_TYPE \
                    ParameterKey=ClusterType,ParameterValue=$REDSHIFT_CLUSTER_TYPE \
        --region $AWS_REGION
    
    wait_for_stack $REDSHIFT_STACK "update"
else
    echo "Creating Redshift stack..."
    aws cloudformation create-stack \
        --stack-name $REDSHIFT_STACK \
        --template-url "https://${ARTIFACTS_BUCKET}.s3.amazonaws.com/cloudformation/${BUILD_NUMBER}/03-redshift.yaml" \
        --parameters ParameterKey=ProjectName,ParameterValue=$STACK_PREFIX \
                    ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
                    ParameterKey=RedshiftUsername,ParameterValue=etladmin \
                    ParameterKey=RedshiftPassword,ParameterValue=$REDSHIFT_PASSWORD \
                    ParameterKey=NodeType,ParameterValue=$REDSHIFT_NODE_TYPE \
                    ParameterKey=ClusterType,ParameterValue=$REDSHIFT_CLUSTER_TYPE \
        --region $AWS_REGION
    
    wait_for_stack $REDSHIFT_STACK "create"
fi

# Deploy Lambda Functions
echo "Deploying Lambda functions..."
LAMBDA_STACK="${STACK_PREFIX}-lambda"

if stack_exists $LAMBDA_STACK; then
    echo "Updating Lambda stack..."
    aws cloudformation update-stack \
        --stack-name $LAMBDA_STACK \
        --template-url "https://${ARTIFACTS_BUCKET}.s3.amazonaws.com/cloudformation/${BUILD_NUMBER}/04-lambda-functions.yaml" \
        --parameters ParameterKey=ProjectName,ParameterValue=$STACK_PREFIX \
                    ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
                    ParameterKey=BuildNumber,ParameterValue=$BUILD_NUMBER \
                    ParameterKey=ArtifactsBucket,ParameterValue=$ARTIFACTS_BUCKET \
        --capabilities CAPABILITY_IAM \
        --region $AWS_REGION
    
    wait_for_stack $LAMBDA_STACK "update"
else
    echo "Creating Lambda stack..."
    aws cloudformation create-stack \
        --stack-name $LAMBDA_STACK \
        --template-url "https://${ARTIFACTS_BUCKET}.s3.amazonaws.com/cloudformation/${BUILD_NUMBER}/04-lambda-functions.yaml" \
        --parameters ParameterKey=ProjectName,ParameterValue=$STACK_PREFIX \
                    ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
                    ParameterKey=BuildNumber,ParameterValue=$BUILD_NUMBER \
                    ParameterKey=ArtifactsBucket,ParameterValue=$ARTIFACTS_BUCKET \
        --capabilities CAPABILITY_IAM \
        --region $AWS_REGION
    
    wait_for_stack $LAMBDA_STACK "create"
fi

# Deploy Kinesis Streaming
echo "Deploying Kinesis streaming infrastructure..."
KINESIS_STACK="${STACK_PREFIX}-kinesis"

if stack_exists $KINESIS_STACK; then
    echo "Updating Kinesis stack..."
    aws cloudformation update-stack \
        --stack-name $KINESIS_STACK \
        --template-url "https://${ARTIFACTS_BUCKET}.s3.amazonaws.com/cloudformation/${BUILD_NUMBER}/05-kinesis-streaming.yaml" \
        --parameters ParameterKey=ProjectName,ParameterValue=$STACK_PREFIX \
                    ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
        --region $AWS_REGION
    
    wait_for_stack $KINESIS_STACK "update"
else
    echo "Creating Kinesis stack..."
    aws cloudformation create-stack \
        --stack-name $KINESIS_STACK \
        --template-url "https://${ARTIFACTS_BUCKET}.s3.amazonaws.com/cloudformation/${BUILD_NUMBER}/05-kinesis-streaming.yaml" \
        --parameters ParameterKey=ProjectName,ParameterValue=$STACK_PREFIX \
                    ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
        --region $AWS_REGION
    
    wait_for_stack $KINESIS_STACK "create"
fi

# Deploy Step Functions Orchestration
echo "Deploying Step Functions orchestration..."
STEPFUNCTIONS_STACK="${STACK_PREFIX}-stepfunctions"

if stack_exists $STEPFUNCTIONS_STACK; then
    echo "Updating Step Functions stack..."
    aws cloudformation update-stack \
        --stack-name $STEPFUNCTIONS_STACK \
        --template-url "https://${ARTIFACTS_BUCKET}.s3.amazonaws.com/cloudformation/${BUILD_NUMBER}/06-step-functions.yaml" \
        --parameters ParameterKey=ProjectName,ParameterValue=$STACK_PREFIX \
                    ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
        --capabilities CAPABILITY_IAM \
        --region $AWS_REGION
    
    wait_for_stack $STEPFUNCTIONS_STACK "update"
else
    echo "Creating Step Functions stack..."
    aws cloudformation create-stack \
        --stack-name $STEPFUNCTIONS_STACK \
        --template-url "https://${ARTIFACTS_BUCKET}.s3.amazonaws.com/cloudformation/${BUILD_NUMBER}/06-step-functions.yaml" \
        --parameters ParameterKey=ProjectName,ParameterValue=$STACK_PREFIX \
                    ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
        --capabilities CAPABILITY_IAM \
        --region $AWS_REGION
    
    wait_for_stack $STEPFUNCTIONS_STACK "create"
fi

# Deploy Monitoring and Alerting
echo "Deploying monitoring and alerting..."
MONITORING_STACK="${STACK_PREFIX}-monitoring"

if stack_exists $MONITORING_STACK; then
    echo "Updating monitoring stack..."
    aws cloudformation update-stack \
        --stack-name $MONITORING_STACK \
        --template-url "https://${ARTIFACTS_BUCKET}.s3.amazonaws.com/cloudformation/${BUILD_NUMBER}/07-monitoring.yaml" \
        --parameters ParameterKey=ProjectName,ParameterValue=$STACK_PREFIX \
                    ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
                    ParameterKey=AlertEmail,ParameterValue=${ALERT_EMAIL:-admin@example.com} \
        --region $AWS_REGION
    
    wait_for_stack $MONITORING_STACK "update"
else
    echo "Creating monitoring stack..."
    aws cloudformation create-stack \
        --stack-name $MONITORING_STACK \
        --template-url "https://${ARTIFACTS_BUCKET}.s3.amazonaws.com/cloudformation/${BUILD_NUMBER}/07-monitoring.yaml" \
        --parameters ParameterKey=ProjectName,ParameterValue=$STACK_PREFIX \
                    ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
                    ParameterKey=AlertEmail,ParameterValue=${ALERT_EMAIL:-admin@example.com} \
        --region $AWS_REGION
    
    wait_for_stack $MONITORING_STACK "create"
fi

# Initialize Redshift database schema
echo "Initializing Redshift database schema..."
REDSHIFT_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name $REDSHIFT_STACK \
    --query 'Stacks[0].Outputs[?OutputKey==`RedshiftClusterEndpoint`].OutputValue' \
    --output text \
    --region $AWS_REGION)

if [ ! -z "$REDSHIFT_ENDPOINT" ]; then
    echo "Redshift endpoint: $REDSHIFT_ENDPOINT"
    # Note: In production, you would run the SQL script here
    # For now, we'll just output the command
    echo "Run the following command to initialize the database:"
    echo "psql -h $REDSHIFT_ENDPOINT -p 5439 -U etladmin -d etldb -f sql/create_redshift_schema.sql"
fi

echo "=========================================="
echo "Deployment completed successfully!"
echo "Environment: $ENVIRONMENT"
echo "Build Number: $BUILD_NUMBER"
echo "=========================================="

# Output important endpoints and information
echo "Important Information:"
echo "- S3 Data Lake Bucket: $(aws cloudformation describe-stacks --stack-name $FOUNDATION_STACK --query 'Stacks[0].Outputs[?OutputKey==`DataLakeBucketName`].OutputValue' --output text --region $AWS_REGION)"
echo "- Redshift Endpoint: $REDSHIFT_ENDPOINT"
echo "- Step Functions State Machine: $(aws cloudformation describe-stacks --stack-name $STEPFUNCTIONS_STACK --query 'Stacks[0].Outputs[?OutputKey==`StateMachineArn`].OutputValue' --output text --region $AWS_REGION 2>/dev/null || echo 'Not available')"

echo "Deployment logs and details are available in the AWS CloudFormation console."