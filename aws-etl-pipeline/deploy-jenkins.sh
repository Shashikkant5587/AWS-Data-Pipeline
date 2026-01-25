#!/bin/bash

# AWS ETL Pipeline with Apache Iceberg - Jenkins Deployment Script
# This script provides a convenient way to trigger Jenkins deployments

set -e

# Configuration
PROJECT_NAME="etl-pipeline"
JENKINS_URL="${JENKINS_URL:-http://localhost:8080}"
JENKINS_JOB="${JENKINS_JOB:-aws-etl-pipeline}"

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

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy AWS ETL Pipeline with Apache Iceberg using Jenkins

OPTIONS:
    -e, --environment ENV       Target environment (dev|staging|prod) [default: dev]
    -p, --password PASSWORD     Redshift password (required)
    -b, --build-number BUILD    Build number [default: auto-generated]
    -i, --iceberg-only         Deploy only Iceberg components
    -s, --skip-tests           Skip running tests
    -j, --jenkins-url URL      Jenkins URL [default: http://localhost:8080]
    -n, --job-name NAME        Jenkins job name [default: aws-etl-pipeline]
    -t, --token TOKEN          Jenkins API token
    -u, --username USER        Jenkins username
    -h, --help                 Show this help message

EXAMPLES:
    # Deploy to dev environment
    $0 --environment dev --password mypassword123

    # Deploy only Iceberg components to staging
    $0 --environment staging --password mypassword123 --iceberg-only

    # Deploy to production with custom Jenkins settings
    $0 --environment prod --password mypassword123 \\
       --jenkins-url https://jenkins.company.com \\
       --username admin --token abc123

ENVIRONMENT VARIABLES:
    JENKINS_URL         Jenkins server URL
    JENKINS_USERNAME    Jenkins username
    JENKINS_TOKEN       Jenkins API token
    REDSHIFT_PASSWORD   Redshift cluster password

EOF
}

# Parse command line arguments
ENVIRONMENT="dev"
REDSHIFT_PASSWORD=""
BUILD_NUMBER=""
ICEBERG_ONLY="false"
SKIP_TESTS="false"
JENKINS_USERNAME="${JENKINS_USERNAME:-}"
JENKINS_TOKEN="${JENKINS_TOKEN:-}"

while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -p|--password)
            REDSHIFT_PASSWORD="$2"
            shift 2
            ;;
        -b|--build-number)
            BUILD_NUMBER="$2"
            shift 2
            ;;
        -i|--iceberg-only)
            ICEBERG_ONLY="true"
            shift
            ;;
        -s|--skip-tests)
            SKIP_TESTS="true"
            shift
            ;;
        -j|--jenkins-url)
            JENKINS_URL="$2"
            shift 2
            ;;
        -n|--job-name)
            JENKINS_JOB="$2"
            shift 2
            ;;
        -t|--token)
            JENKINS_TOKEN="$2"
            shift 2
            ;;
        -u|--username)
            JENKINS_USERNAME="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validation
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
    print_error "Invalid environment: $ENVIRONMENT. Must be dev, staging, or prod."
    exit 1
fi

if [[ -z "$REDSHIFT_PASSWORD" ]]; then
    if [[ -n "$REDSHIFT_PASSWORD" ]]; then
        REDSHIFT_PASSWORD="$REDSHIFT_PASSWORD"
    else
        print_error "Redshift password is required. Use --password or set REDSHIFT_PASSWORD environment variable."
        exit 1
    fi
fi

if [[ ${#REDSHIFT_PASSWORD} -lt 8 || ${#REDSHIFT_PASSWORD} -gt 64 ]]; then
    print_error "Redshift password must be between 8 and 64 characters."
    exit 1
fi

# Generate build number if not provided
if [[ -z "$BUILD_NUMBER" ]]; then
    BUILD_NUMBER="$(date +%Y%m%d%H%M%S)-$(git rev-parse --short HEAD 2>/dev/null || echo 'manual')"
fi

# Check Jenkins connectivity
print_status "Checking Jenkins connectivity..."
if ! curl -s --connect-timeout 10 "$JENKINS_URL" > /dev/null; then
    print_error "Cannot connect to Jenkins at $JENKINS_URL"
    print_warning "Make sure Jenkins is running and accessible"
    exit 1
fi

print_success "Connected to Jenkins at $JENKINS_URL"

# Prepare Jenkins job parameters
JENKINS_PARAMS="DEPLOY_ENVIRONMENT=$ENVIRONMENT"
JENKINS_PARAMS="$JENKINS_PARAMS&REDSHIFT_PASSWORD=$REDSHIFT_PASSWORD"
JENKINS_PARAMS="$JENKINS_PARAMS&SKIP_TESTS=$SKIP_TESTS"
JENKINS_PARAMS="$JENKINS_PARAMS&DEPLOY_ICEBERG_ONLY=$ICEBERG_ONLY"

# Prepare authentication
AUTH_HEADER=""
if [[ -n "$JENKINS_USERNAME" && -n "$JENKINS_TOKEN" ]]; then
    AUTH_HEADER="-u $JENKINS_USERNAME:$JENKINS_TOKEN"
    print_status "Using Jenkins authentication for user: $JENKINS_USERNAME"
elif [[ -n "$JENKINS_USERNAME" ]]; then
    print_warning "Jenkins username provided but no token. You may be prompted for password."
    AUTH_HEADER="-u $JENKINS_USERNAME"
fi

# Display deployment summary
print_status "=== Deployment Summary ==="
echo "Environment: $ENVIRONMENT"
echo "Build Number: $BUILD_NUMBER"
echo "Iceberg Only: $ICEBERG_ONLY"
echo "Skip Tests: $SKIP_TESTS"
echo "Jenkins URL: $JENKINS_URL"
echo "Jenkins Job: $JENKINS_JOB"
echo ""

# Confirm deployment
if [[ "$ENVIRONMENT" == "prod" ]]; then
    print_warning "You are about to deploy to PRODUCTION environment!"
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_status "Deployment cancelled."
        exit 0
    fi
fi

# Trigger Jenkins job
print_status "Triggering Jenkins job: $JENKINS_JOB"

JENKINS_BUILD_URL="$JENKINS_URL/job/$JENKINS_JOB/buildWithParameters"

# Make the Jenkins API call
HTTP_STATUS=$(curl -s -o /tmp/jenkins_response.txt -w "%{http_code}" \
    $AUTH_HEADER \
    -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "$JENKINS_PARAMS" \
    "$JENKINS_BUILD_URL")

if [[ "$HTTP_STATUS" -eq 201 || "$HTTP_STATUS" -eq 200 ]]; then
    print_success "Jenkins job triggered successfully!"
    
    # Extract queue item URL from Location header if available
    QUEUE_URL=$(curl -s -I $AUTH_HEADER -X POST -d "$JENKINS_PARAMS" "$JENKINS_BUILD_URL" | grep -i "location:" | cut -d' ' -f2 | tr -d '\r')
    
    if [[ -n "$QUEUE_URL" ]]; then
        print_status "Build queued at: $QUEUE_URL"
        
        # Wait for build to start and get build number
        print_status "Waiting for build to start..."
        for i in {1..30}; do
            sleep 2
            BUILD_INFO=$(curl -s $AUTH_HEADER "${QUEUE_URL}api/json" 2>/dev/null || echo "{}")
            BUILD_URL=$(echo "$BUILD_INFO" | grep -o '"executable":{"_class":"[^"]*","number":[0-9]*,"url":"[^"]*"' | grep -o 'url":"[^"]*"' | cut -d'"' -f3)
            
            if [[ -n "$BUILD_URL" ]]; then
                print_success "Build started: $BUILD_URL"
                print_status "You can monitor the build progress at: ${BUILD_URL}console"
                break
            fi
            
            if [[ $i -eq 30 ]]; then
                print_warning "Build may still be queued. Check Jenkins manually: $JENKINS_URL/job/$JENKINS_JOB"
            fi
        done
    fi
    
    # Provide useful links
    print_status "=== Useful Links ==="
    echo "Jenkins Job: $JENKINS_URL/job/$JENKINS_JOB"
    echo "Build History: $JENKINS_URL/job/$JENKINS_JOB/builds"
    echo "AWS Console: https://console.aws.amazon.com/cloudformation"
    echo ""
    
    print_status "=== Next Steps ==="
    echo "1. Monitor the build progress in Jenkins"
    echo "2. Check CloudFormation stacks in AWS Console"
    echo "3. Verify deployed resources are working correctly"
    echo "4. Run integration tests if needed"
    
    if [[ "$ENVIRONMENT" == "prod" ]]; then
        echo "5. Monitor production metrics and alerts"
        echo "6. Notify stakeholders of successful deployment"
    fi
    
else
    print_error "Failed to trigger Jenkins job. HTTP Status: $HTTP_STATUS"
    if [[ -f /tmp/jenkins_response.txt ]]; then
        print_error "Response: $(cat /tmp/jenkins_response.txt)"
    fi
    
    print_status "Troubleshooting tips:"
    echo "1. Check if Jenkins job '$JENKINS_JOB' exists"
    echo "2. Verify Jenkins authentication credentials"
    echo "3. Ensure Jenkins user has job execution permissions"
    echo "4. Check Jenkins logs for more details"
    
    exit 1
fi

# Cleanup
rm -f /tmp/jenkins_response.txt

print_success "Deployment script completed successfully!"