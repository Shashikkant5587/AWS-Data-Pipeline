#!/bin/bash

# Test script for AWS ETL Pipeline
# This script tests the deployed pipeline components

set -e

echo "🧪 AWS ETL Pipeline Test Script"
echo "==============================="

# Configuration
PROJECT_NAME="etl-pipeline"
ENVIRONMENT="dev"
AWS_REGION="us-east-1"
STACK_PREFIX="${PROJECT_NAME}-${ENVIRONMENT}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

# Test CloudFormation stacks
test_cloudformation_stacks() {
    print_status "Testing CloudFormation stacks..."
    
    stacks=(
        "${STACK_PREFIX}-foundation"
        "${STACK_PREFIX}-network"
        "${STACK_PREFIX}-redshift"
        "${STACK_PREFIX}-lambda"
    )
    
    for stack in "${stacks[@]}"; do
        if aws cloudformation describe-stacks --stack-name "$stack" --region $AWS_REGION > /dev/null 2>&1; then
            status=$(aws cloudformation describe-stacks --stack-name "$stack" --query 'Stacks[0].StackStatus' --output text --region $AWS_REGION)
            if [[ "$status" == *"COMPLETE"* ]]; then
                print_success "Stack $stack is in $status state"
            else
                print_error "Stack $stack is in $status state"
            fi
        else
            print_error "Stack $stack not found"
        fi
    done
}

# Test S3 buckets
test_s3_buckets() {
    print_status "Testing S3 buckets..."
    
    # Get data lake bucket name
    DATA_LAKE_BUCKET=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_PREFIX}-foundation" \
        --query 'Stacks[0].Outputs[?OutputKey==`DataLakeBucketName`].OutputValue' \
        --output text \
        --region $AWS_REGION 2>/dev/null)
    
    if [ ! -z "$DATA_LAKE_BUCKET" ]; then
        if aws s3 ls "s3://$DATA_LAKE_BUCKET" > /dev/null 2>&1; then
            print_success "Data lake bucket $DATA_LAKE_BUCKET is accessible"
            
            # Check folder structure
            folders=("raw-data" "processed-data" "sample-data")
            for folder in "${folders[@]}"; do
                if aws s3 ls "s3://$DATA_LAKE_BUCKET/$folder/" > /dev/null 2>&1; then
                    print_success "Folder $folder exists"
                else
                    print_warning "Folder $folder not found (may be created during pipeline execution)"
                fi
            done
        else
            print_error "Cannot access data lake bucket $DATA_LAKE_BUCKET"
        fi
    else
        print_error "Could not retrieve data lake bucket name"
    fi
}

# Test Lambda functions
test_lambda_functions() {
    print_status "Testing Lambda functions..."
    
    functions=(
        "${STACK_PREFIX}-extract-database"
        "${STACK_PREFIX}-extract-api"
        "${STACK_PREFIX}-data-quality"
        "${STACK_PREFIX}-load-redshift"
    )
    
    for func in "${functions[@]}"; do
        if aws lambda get-function --function-name "$func" --region $AWS_REGION > /dev/null 2>&1; then
            print_success "Lambda function $func exists"
            
            # Test function configuration
            runtime=$(aws lambda get-function --function-name "$func" --query 'Configuration.Runtime' --output text --region $AWS_REGION)
            if [ "$runtime" = "python3.9" ]; then
                print_success "Function $func has correct runtime: $runtime"
            else
                print_warning "Function $func has runtime: $runtime"
            fi
        else
            print_error "Lambda function $func not found"
        fi
    done
}

# Test Redshift cluster
test_redshift_cluster() {
    print_status "Testing Redshift cluster..."
    
    # Get Redshift cluster identifier
    CLUSTER_ID=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_PREFIX}-redshift" \
        --query 'Stacks[0].Outputs[?OutputKey==`RedshiftClusterEndpoint`].OutputValue' \
        --output text \
        --region $AWS_REGION 2>/dev/null)
    
    if [ ! -z "$CLUSTER_ID" ]; then
        print_success "Redshift cluster endpoint: $CLUSTER_ID"
        
        # Check cluster status
        CLUSTER_NAME="${PROJECT_NAME}-redshift-cluster"
        if aws redshift describe-clusters --cluster-identifier "$CLUSTER_NAME" --region $AWS_REGION > /dev/null 2>&1; then
            status=$(aws redshift describe-clusters --cluster-identifier "$CLUSTER_NAME" --query 'Clusters[0].ClusterStatus' --output text --region $AWS_REGION)
            if [ "$status" = "available" ]; then
                print_success "Redshift cluster is available"
            else
                print_warning "Redshift cluster status: $status"
            fi
        else
            print_error "Redshift cluster not found"
        fi
    else
        print_error "Could not retrieve Redshift cluster endpoint"
    fi
}

# Test IAM roles
test_iam_roles() {
    print_status "Testing IAM roles..."
    
    roles=(
        "${STACK_PREFIX}-glue-service-role"
        "${STACK_PREFIX}-lambda-execution-role"
        "${STACK_PREFIX}-redshift-service-role"
    )
    
    for role in "${roles[@]}"; do
        if aws iam get-role --role-name "$role" > /dev/null 2>&1; then
            print_success "IAM role $role exists"
        else
            print_error "IAM role $role not found"
        fi
    done
}

# Test Secrets Manager
test_secrets_manager() {
    print_status "Testing Secrets Manager..."
    
    # Check if Redshift secret exists
    SECRET_NAME="${PROJECT_NAME}/redshift/credentials"
    if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region $AWS_REGION > /dev/null 2>&1; then
        print_success "Redshift credentials secret exists"
    else
        print_error "Redshift credentials secret not found"
    fi
}

# Test sample data
test_sample_data() {
    print_status "Testing sample data..."
    
    if [ ! -z "$DATA_LAKE_BUCKET" ]; then
        # Check for sample data files
        if aws s3 ls "s3://$DATA_LAKE_BUCKET/sample-data/" > /dev/null 2>&1; then
            print_success "Sample data folder exists"
            
            # Count sample data files
            file_count=$(aws s3 ls "s3://$DATA_LAKE_BUCKET/sample-data/" --recursive | wc -l)
            if [ "$file_count" -gt 0 ]; then
                print_success "Found $file_count sample data files"
            else
                print_warning "No sample data files found"
            fi
        else
            print_warning "Sample data folder not found"
        fi
    fi
}

# Test Lambda function invocation
test_lambda_invocation() {
    print_status "Testing Lambda function invocation..."
    
    # Test data quality function with minimal payload
    FUNCTION_NAME="${STACK_PREFIX}-data-quality"
    TEST_PAYLOAD='{"s3_paths": [], "quality_rules": {}}'
    
    if aws lambda invoke \
        --function-name "$FUNCTION_NAME" \
        --payload "$TEST_PAYLOAD" \
        --region $AWS_REGION \
        /tmp/lambda-response.json > /dev/null 2>&1; then
        
        # Check response
        if grep -q "statusCode" /tmp/lambda-response.json; then
            status_code=$(cat /tmp/lambda-response.json | python3 -c "import sys, json; print(json.load(sys.stdin).get('statusCode', 'unknown'))")
            if [ "$status_code" = "200" ]; then
                print_success "Lambda function invocation successful"
            else
                print_warning "Lambda function returned status code: $status_code"
            fi
        else
            print_warning "Lambda function response format unexpected"
        fi
        
        rm -f /tmp/lambda-response.json
    else
        print_error "Lambda function invocation failed"
    fi
}

# Run comprehensive tests
run_comprehensive_tests() {
    print_status "Running comprehensive pipeline tests..."
    
    # Run integration tests if available
    if [ -f "tests/integration/test_etl_pipeline.py" ]; then
        print_status "Running integration tests..."
        
        if command -v pytest &> /dev/null; then
            export ENVIRONMENT=$ENVIRONMENT
            if pytest tests/integration/test_etl_pipeline.py -v; then
                print_success "Integration tests passed"
            else
                print_error "Integration tests failed"
            fi
        else
            print_warning "pytest not available, skipping integration tests"
        fi
    else
        print_warning "Integration tests not found"
    fi
}

# Generate test report
generate_test_report() {
    print_status "Generating test report..."
    
    REPORT_FILE="test-report-$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "AWS ETL Pipeline Test Report"
        echo "Generated: $(date)"
        echo "Environment: $ENVIRONMENT"
        echo "Region: $AWS_REGION"
        echo ""
        echo "Stack Prefix: $STACK_PREFIX"
        echo "Data Lake Bucket: $DATA_LAKE_BUCKET"
        echo ""
        echo "Test Results:"
        echo "- CloudFormation Stacks: See above output"
        echo "- S3 Buckets: See above output"
        echo "- Lambda Functions: See above output"
        echo "- Redshift Cluster: See above output"
        echo "- IAM Roles: See above output"
        echo "- Secrets Manager: See above output"
        echo ""
        echo "Next Steps:"
        echo "1. Configure data source credentials in Secrets Manager"
        echo "2. Initialize Redshift database schema"
        echo "3. Test end-to-end pipeline execution"
    } > "$REPORT_FILE"
    
    print_success "Test report saved to: $REPORT_FILE"
}

# Main test function
main() {
    print_status "Starting AWS ETL Pipeline tests..."
    echo ""
    
    test_cloudformation_stacks
    echo ""
    
    test_s3_buckets
    echo ""
    
    test_lambda_functions
    echo ""
    
    test_redshift_cluster
    echo ""
    
    test_iam_roles
    echo ""
    
    test_secrets_manager
    echo ""
    
    test_sample_data
    echo ""
    
    test_lambda_invocation
    echo ""
    
    run_comprehensive_tests
    echo ""
    
    generate_test_report
    
    print_success "🎉 Pipeline testing completed!"
    echo ""
    print_status "Summary:"
    echo "- All major components have been tested"
    echo "- Check the output above for any warnings or errors"
    echo "- Review the generated test report for details"
}

# Run main function
main "$@"