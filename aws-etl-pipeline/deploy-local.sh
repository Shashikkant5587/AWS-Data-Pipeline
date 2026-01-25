#!/bin/bash

# Local deployment script for AWS ETL Pipeline
# This script deploys the ETL pipeline to your AWS account

set -e

echo "🚀 AWS ETL Pipeline Local Deployment Script"
echo "=========================================="

# Configuration
PROJECT_NAME="etl-pipeline"
ENVIRONMENT="dev"
AWS_REGION="us-east-1"
BUILD_NUMBER=$(date +%Y%m%d_%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is not installed."
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Create artifacts bucket
create_artifacts_bucket() {
    ARTIFACTS_BUCKET="${PROJECT_NAME}-artifacts-$(aws sts get-caller-identity --query Account --output text)"
    
    print_status "Creating artifacts bucket: $ARTIFACTS_BUCKET"
    
    if aws s3 ls "s3://$ARTIFACTS_BUCKET" 2>&1 | grep -q 'NoSuchBucket'; then
        aws s3 mb "s3://$ARTIFACTS_BUCKET" --region $AWS_REGION
        print_success "Created artifacts bucket"
    else
        print_warning "Artifacts bucket already exists"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket $ARTIFACTS_BUCKET \
        --versioning-configuration Status=Enabled
}

# Build Lambda packages
build_lambda_packages() {
    print_status "Building Lambda deployment packages..."
    
    mkdir -p build/lambda
    
    # Build each Lambda function
    for lambda_dir in lambda/*/; do
        if [ -d "$lambda_dir" ]; then
            lambda_name=$(basename "$lambda_dir")
            print_status "Building $lambda_name..."
            
            cd "$lambda_dir"
            
            # Install dependencies
            if [ -f "requirements.txt" ]; then
                pip install -r requirements.txt -t . --quiet
            fi
            
            # Create zip package
            zip -r "../../build/lambda/${lambda_name}.zip" . \
                -x "tests/*" "*.pyc" "__pycache__/*" "*.git*" > /dev/null
            
            cd - > /dev/null
            print_success "Built $lambda_name package"
        fi
    done
}

# Upload artifacts to S3
upload_artifacts() {
    print_status "Uploading artifacts to S3..."
    
    # Upload Lambda packages
    aws s3 cp build/lambda/ "s3://$ARTIFACTS_BUCKET/lambda-packages/$BUILD_NUMBER/" --recursive
    
    # Upload CloudFormation templates
    aws s3 cp infrastructure/ "s3://$ARTIFACTS_BUCKET/cloudformation/$BUILD_NUMBER/" --recursive
    
    # Upload Glue scripts
    aws s3 cp glue-jobs/ "s3://$ARTIFACTS_BUCKET/glue-scripts/$BUILD_NUMBER/" --recursive
    
    print_success "Artifacts uploaded successfully"
}

# Deploy CloudFormation stacks
deploy_infrastructure() {
    print_status "Deploying infrastructure..."
    
    STACK_PREFIX="${PROJECT_NAME}-${ENVIRONMENT}"
    
    # Function to check if stack exists
    stack_exists() {
        aws cloudformation describe-stacks --stack-name $1 --region $AWS_REGION > /dev/null 2>&1
    }
    
    # Function to wait for stack operation
    wait_for_stack() {
        local stack_name=$1
        local operation=$2
        
        print_status "Waiting for stack $operation to complete..."
        aws cloudformation wait stack-${operation}-complete --stack-name $stack_name --region $AWS_REGION
        
        if [ $? -eq 0 ]; then
            print_success "Stack $operation completed successfully"
        else
            print_error "Stack $operation failed"
            exit 1
        fi
    }
    
    # Generate random Redshift password
    REDSHIFT_PASSWORD=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-12)
    print_warning "Generated Redshift password: $REDSHIFT_PASSWORD (save this securely!)"
    
    # Deploy Foundation Stack (IAM roles, S3, KMS)
    print_status "Deploying foundation stack..."
    FOUNDATION_STACK="${STACK_PREFIX}-foundation"
    
    if stack_exists $FOUNDATION_STACK; then
        aws cloudformation update-stack \
            --stack-name $FOUNDATION_STACK \
            --template-url "https://${ARTIFACTS_BUCKET}.s3.amazonaws.com/cloudformation/${BUILD_NUMBER}/01-iam-roles.yaml" \
            --parameters ParameterKey=ProjectName,ParameterValue=$STACK_PREFIX \
                        ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
            --capabilities CAPABILITY_NAMED_IAM \
            --region $AWS_REGION
        wait_for_stack $FOUNDATION_STACK "update"
    else
        aws cloudformation create-stack \
            --stack-name $FOUNDATION_STACK \
            --template-url "https://${ARTIFACTS_BUCKET}.s3.amazonaws.com/cloudformation/${BUILD_NUMBER}/01-iam-roles.yaml" \
            --parameters ParameterKey=ProjectName,ParameterValue=$STACK_PREFIX \
                        ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
            --capabilities CAPABILITY_NAMED_IAM \
            --region $AWS_REGION
        wait_for_stack $FOUNDATION_STACK "create"
    fi
    
    # Deploy Network Stack
    print_status "Deploying network stack..."
    NETWORK_STACK="${STACK_PREFIX}-network"
    
    if stack_exists $NETWORK_STACK; then
        aws cloudformation update-stack \
            --stack-name $NETWORK_STACK \
            --template-url "https://${ARTIFACTS_BUCKET}.s3.amazonaws.com/cloudformation/${BUILD_NUMBER}/02-vpc-network.yaml" \
            --parameters ParameterKey=ProjectName,ParameterValue=$STACK_PREFIX \
                        ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
            --region $AWS_REGION
        wait_for_stack $NETWORK_STACK "update"
    else
        aws cloudformation create-stack \
            --stack-name $NETWORK_STACK \
            --template-url "https://${ARTIFACTS_BUCKET}.s3.amazonaws.com/cloudformation/${BUILD_NUMBER}/02-vpc-network.yaml" \
            --parameters ParameterKey=ProjectName,ParameterValue=$STACK_PREFIX \
                        ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
            --region $AWS_REGION
        wait_for_stack $NETWORK_STACK "create"
    fi
    
    # Deploy Redshift Stack
    print_status "Deploying Redshift stack..."
    REDSHIFT_STACK="${STACK_PREFIX}-redshift"
    
    if stack_exists $REDSHIFT_STACK; then
        aws cloudformation update-stack \
            --stack-name $REDSHIFT_STACK \
            --template-url "https://${ARTIFACTS_BUCKET}.s3.amazonaws.com/cloudformation/${BUILD_NUMBER}/02-redshift.yaml" \
            --parameters ParameterKey=ProjectName,ParameterValue=$STACK_PREFIX \
                        ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
                        ParameterKey=RedshiftUsername,ParameterValue=etladmin \
                        ParameterKey=RedshiftPassword,ParameterValue=$REDSHIFT_PASSWORD \
                        ParameterKey=NodeType,ParameterValue=dc2.large \
                        ParameterKey=ClusterType,ParameterValue=single-node \
            --region $AWS_REGION
        wait_for_stack $REDSHIFT_STACK "update"
    else
        aws cloudformation create-stack \
            --stack-name $REDSHIFT_STACK \
            --template-url "https://${ARTIFACTS_BUCKET}.s3.amazonaws.com/cloudformation/${BUILD_NUMBER}/02-redshift.yaml" \
            --parameters ParameterKey=ProjectName,ParameterValue=$STACK_PREFIX \
                        ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
                        ParameterKey=RedshiftUsername,ParameterValue=etladmin \
                        ParameterKey=RedshiftPassword,ParameterValue=$REDSHIFT_PASSWORD \
                        ParameterKey=NodeType,ParameterValue=dc2.large \
                        ParameterKey=ClusterType,ParameterValue=single-node \
            --region $AWS_REGION
        wait_for_stack $REDSHIFT_STACK "create"
    fi
    
    # Deploy Lambda Functions Stack
    print_status "Deploying Lambda functions stack..."
    LAMBDA_STACK="${STACK_PREFIX}-lambda"
    
    if stack_exists $LAMBDA_STACK; then
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
}

# Generate sample data
generate_sample_data() {
    print_status "Generating sample data..."
    
    # Get the data lake bucket name
    DATA_LAKE_BUCKET=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_PREFIX}-foundation" \
        --query 'Stacks[0].Outputs[?OutputKey==`DataLakeBucketName`].OutputValue' \
        --output text \
        --region $AWS_REGION)
    
    if [ ! -z "$DATA_LAKE_BUCKET" ]; then
        print_status "Data lake bucket: $DATA_LAKE_BUCKET"
        
        # Install required Python packages
        pip install faker boto3 --quiet
        
        # Generate sample data
        python3 scripts/generate-sample-data.py \
            --environment $ENVIRONMENT \
            --bucket $DATA_LAKE_BUCKET \
            --users 100 \
            --products 50 \
            --orders 500
        
        print_success "Sample data generated"
    else
        print_warning "Could not find data lake bucket name"
    fi
}

# Initialize Redshift database
initialize_redshift() {
    print_status "Initializing Redshift database..."
    
    # Get Redshift endpoint
    REDSHIFT_ENDPOINT=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_PREFIX}-redshift" \
        --query 'Stacks[0].Outputs[?OutputKey==`RedshiftClusterEndpoint`].OutputValue' \
        --output text \
        --region $AWS_REGION)
    
    if [ ! -z "$REDSHIFT_ENDPOINT" ]; then
        print_status "Redshift endpoint: $REDSHIFT_ENDPOINT"
        print_warning "To initialize the database schema, run:"
        print_warning "psql -h $REDSHIFT_ENDPOINT -p 5439 -U etladmin -d etldb -f sql/create_redshift_schema.sql"
        print_warning "Password: $REDSHIFT_PASSWORD"
    else
        print_warning "Could not find Redshift endpoint"
    fi
}

# Main deployment function
main() {
    print_status "Starting AWS ETL Pipeline deployment..."
    
    check_prerequisites
    create_artifacts_bucket
    build_lambda_packages
    upload_artifacts
    deploy_infrastructure
    generate_sample_data
    initialize_redshift
    
    print_success "🎉 Deployment completed successfully!"
    echo ""
    print_status "Next steps:"
    echo "1. Initialize Redshift database schema (see command above)"
    echo "2. Configure data source credentials in AWS Secrets Manager"
    echo "3. Test the pipeline by running a Step Functions execution"
    echo ""
    print_status "Important information:"
    echo "- Artifacts bucket: $ARTIFACTS_BUCKET"
    echo "- Data lake bucket: $DATA_LAKE_BUCKET"
    echo "- Redshift endpoint: $REDSHIFT_ENDPOINT"
    echo "- Redshift password: $REDSHIFT_PASSWORD (save this securely!)"
}

# Run main function
main "$@"