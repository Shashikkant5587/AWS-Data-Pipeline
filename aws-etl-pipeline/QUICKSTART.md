# 🚀 Quick Start Guide - AWS ETL Pipeline

This guide will help you deploy and run the AWS ETL Pipeline in under 30 minutes.

## Prerequisites ✅

1. **AWS Account** with appropriate permissions
2. **AWS CLI** installed and configured
3. **Python 3.9+** installed
4. **Basic command line knowledge**

## Step 1: Setup AWS Credentials 🔑

```bash
# Configure AWS CLI (if not already done)
aws configure

# Verify credentials
aws sts get-caller-identity
```

## Step 2: Clone and Deploy 📦

```bash
# Clone the repository (or download the files)
# Navigate to the aws-etl-pipeline directory
cd aws-etl-pipeline

# Make deployment script executable
chmod +x deploy-local.sh

# Run the deployment (takes 15-20 minutes)
./deploy-local.sh
```

**What this does:**
- ✅ Creates S3 buckets for data lake and artifacts
- ✅ Deploys IAM roles and security policies
- ✅ Sets up VPC and networking
- ✅ Creates Redshift data warehouse
- ✅ Deploys Lambda functions for ETL processing
- ✅ Generates sample data for testing

## Step 3: Initialize Database 🗄️

After deployment completes, you'll see a command like this:

```bash
# Initialize Redshift database schema
psql -h your-redshift-endpoint -p 5439 -U etladmin -d etldb -f sql/create_redshift_schema.sql
```

**If you don't have psql installed:**

```bash
# On macOS
brew install postgresql

# On Ubuntu/Debian
sudo apt-get install postgresql-client

# On Windows
# Download from: https://www.postgresql.org/download/windows/
```

## Step 4: Test the Pipeline 🧪

```bash
# Make test script executable
chmod +x test-pipeline.sh

# Run comprehensive tests
./test-pipeline.sh
```

## Step 5: Configure Data Sources (Optional) 📊

### Add Database Credentials

```bash
# Example: PostgreSQL source
aws secretsmanager create-secret \
    --name "etl-pipeline/dev/source-db/credentials" \
    --description "Source database credentials" \
    --secret-string '{
        "engine": "postgresql",
        "host": "your-db-host.com",
        "port": 5432,
        "database": "your_database",
        "username": "your_username",
        "password": "your_password"
    }'
```

### Add API Credentials

```bash
# Example: REST API credentials
aws secretsmanager create-secret \
    --name "etl-pipeline/dev/api/credentials" \
    --description "API credentials" \
    --secret-string '{
        "base_url": "https://api.example.com/v1",
        "auth_type": "bearer",
        "token": "your-api-token",
        "endpoints": {
            "orders": {
                "path": "/orders",
                "records_path": "data"
            }
        }
    }'
```

## Step 6: Run Your First ETL Job 🎯

### Option A: Manual Execution

```bash
# Test individual Lambda function
aws lambda invoke \
    --function-name etl-pipeline-dev-extract-database \
    --payload '{
        "database_secret": "etl-pipeline/dev/source-db/credentials",
        "table_name": "users",
        "s3_bucket": "your-data-lake-bucket",
        "extraction_type": "full"
    }' \
    response.json

# Check the response
cat response.json
```

### Option B: Step Functions Execution

```bash
# Get Step Functions ARN
STATE_MACHINE_ARN=$(aws cloudformation describe-stacks \
    --stack-name etl-pipeline-dev-stepfunctions \
    --query 'Stacks[0].Outputs[?OutputKey==`StateMachineArn`].OutputValue' \
    --output text)

# Start execution
aws stepfunctions start-execution \
    --state-machine-arn $STATE_MACHINE_ARN \
    --name "test-execution-$(date +%s)" \
    --input '{
        "execution_type": "manual",
        "test_mode": true
    }'
```

## Step 7: Monitor and Explore 📈

### CloudWatch Dashboards
```bash
# Open CloudWatch console
echo "https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:"
```

### S3 Data Lake
```bash
# List data in your data lake
aws s3 ls s3://your-data-lake-bucket/ --recursive
```

### Redshift Query Editor
```bash
# Open Redshift Query Editor
echo "https://console.aws.amazon.com/redshiftv2/home?region=us-east-1#query-editor"
```

**Sample Queries:**
```sql
-- Check loaded data
SELECT COUNT(*) FROM dimensions.dim_users;
SELECT COUNT(*) FROM facts.fact_orders;

-- View sample data
SELECT * FROM facts.v_order_summary LIMIT 10;
```

## Troubleshooting 🔧

### Common Issues

**1. Permission Errors**
```bash
# Check your AWS permissions
aws iam get-user
aws sts get-caller-identity
```

**2. Stack Creation Failures**
```bash
# Check CloudFormation events
aws cloudformation describe-stack-events --stack-name etl-pipeline-dev-foundation
```

**3. Lambda Function Errors**
```bash
# Check Lambda logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/etl-pipeline-dev"
aws logs filter-log-events --log-group-name "/aws/lambda/etl-pipeline-dev-extract-database"
```

**4. Redshift Connection Issues**
```bash
# Check security group rules
aws ec2 describe-security-groups --filters "Name=group-name,Values=*redshift*"
```

### Getting Help

1. **Check the logs** in CloudWatch
2. **Review the test output** from `test-pipeline.sh`
3. **Verify AWS permissions** and service limits
4. **Check the README.md** for detailed documentation

## Next Steps 🎯

1. **Customize the pipeline** for your data sources
2. **Add more transformation logic** in Glue jobs
3. **Set up monitoring alerts** for production use
4. **Implement data quality rules** for your specific data
5. **Schedule regular ETL runs** using EventBridge

## Cost Optimization 💰

**Estimated Monthly Costs (Development):**
- Redshift dc2.large: ~$180/month
- Lambda executions: ~$5/month
- S3 storage: ~$10/month
- Other services: ~$15/month
- **Total: ~$210/month**

**To minimize costs:**
```bash
# Pause Redshift cluster when not in use
aws redshift pause-cluster --cluster-identifier etl-pipeline-redshift-cluster

# Resume when needed
aws redshift resume-cluster --cluster-identifier etl-pipeline-redshift-cluster
```

## Success! 🎉

You now have a fully functional AWS ETL Pipeline! 

**What you've built:**
- ✅ Scalable data extraction from multiple sources
- ✅ Automated data transformation and quality checks
- ✅ Data warehouse with dimensional modeling
- ✅ Monitoring and alerting system
- ✅ Infrastructure as Code for easy management

**Ready for production?** Check out the full README.md for advanced configuration, security hardening, and production deployment strategies.