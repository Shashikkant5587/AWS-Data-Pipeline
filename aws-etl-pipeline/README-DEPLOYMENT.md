# AWS ETL Pipeline with Apache Iceberg - Deployment Guide

This guide explains how to deploy the AWS ETL Pipeline with Apache Iceberg integration using Jenkins and CloudFormation.

## 🏗️ Architecture Overview

The pipeline includes:
- **Data Lake**: S3 buckets for raw and processed data
- **Apache Iceberg**: Modern table format with ACID transactions, schema evolution, and time travel
- **AWS Glue**: ETL jobs with Iceberg support
- **Lambda Functions**: Data extraction, quality checks, and Iceberg operations
- **Amazon Redshift**: Data warehouse for analytics
- **Step Functions**: Workflow orchestration
- **CloudWatch**: Monitoring and alerting

## 📋 Prerequisites

### AWS Requirements
- AWS CLI configured with appropriate permissions
- AWS account with sufficient service limits
- IAM permissions for CloudFormation, S3, Glue, Lambda, Redshift, etc.

### Jenkins Requirements
- Jenkins server with AWS CLI plugin
- Jenkins credentials for AWS access
- Git plugin for source code management

### Local Development
- AWS CLI v2.x
- Python 3.9+
- Git

## 🚀 Quick Start

### 1. Using Jenkins (Recommended)

The easiest way to deploy is using the provided Jenkins pipeline:

```bash
# Make the deployment script executable
chmod +x aws-etl-pipeline/deploy-jenkins.sh

# Deploy to development environment
./aws-etl-pipeline/deploy-jenkins.sh \
  --environment dev \
  --password "YourRedshiftPassword123"

# Deploy only Iceberg components
./aws-etl-pipeline/deploy-jenkins.sh \
  --environment dev \
  --password "YourRedshiftPassword123" \
  --iceberg-only

# Deploy to production
./aws-etl-pipeline/deploy-jenkins.sh \
  --environment prod \
  --password "YourRedshiftPassword123" \
  --jenkins-url "https://jenkins.company.com" \
  --username "admin" \
  --token "your-api-token"
```

### 2. Manual Jenkins Trigger

1. Open Jenkins web interface
2. Navigate to the `aws-etl-pipeline` job
3. Click "Build with Parameters"
4. Set the following parameters:
   - **DEPLOY_ENVIRONMENT**: `dev`, `staging`, or `prod`
   - **REDSHIFT_PASSWORD**: Your Redshift cluster password
   - **SKIP_TESTS**: `false` (recommended)
   - **DEPLOY_ICEBERG_ONLY**: `false` for full deployment
5. Click "Build"

### 3. Direct CloudFormation Deployment

For advanced users who want to deploy directly:

```bash
# Set environment variables
export PROJECT_NAME="etl-pipeline"
export ENVIRONMENT="dev"
export BUILD_NUMBER="$(date +%Y%m%d%H%M%S)"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export ARTIFACTS_BUCKET="${PROJECT_NAME}-${ENVIRONMENT}-artifacts-${AWS_ACCOUNT_ID}"

# Create artifacts bucket
aws s3 mb "s3://$ARTIFACTS_BUCKET" --region us-east-1

# Upload CloudFormation templates
aws s3 cp aws-etl-pipeline/infrastructure/ "s3://$ARTIFACTS_BUCKET/cloudformation-templates/$BUILD_NUMBER/" --recursive

# Deploy master stack
aws cloudformation deploy \
  --template-file aws-etl-pipeline/infrastructure/00-master-stack.yaml \
  --stack-name "${PROJECT_NAME}-${ENVIRONMENT}-master" \
  --parameter-overrides \
    ProjectName="$PROJECT_NAME" \
    Environment="$ENVIRONMENT" \
    BuildNumber="$BUILD_NUMBER" \
    ArtifactsBucket="$ARTIFACTS_BUCKET" \
    RedshiftPassword="YourPassword123" \
  --capabilities CAPABILITY_NAMED_IAM
```

## 📁 Infrastructure Components

### CloudFormation Stacks

| Stack | Description | Dependencies |
|-------|-------------|--------------|
| `00-master-stack.yaml` | Master stack that deploys all components | None |
| `01-iam-roles.yaml` | IAM roles, S3 buckets, KMS keys | None |
| `02-vpc-network.yaml` | VPC, subnets, security groups | None |
| `02-redshift.yaml` | Redshift cluster and configuration | IAM roles, VPC |
| `03-iceberg-glue.yaml` | Iceberg warehouse, Glue database, ETL jobs | IAM roles |
| `04-lambda-functions.yaml` | Standard Lambda functions | IAM roles, VPC |
| `05-iceberg-lambda.yaml` | Iceberg-specific Lambda functions | IAM roles, Iceberg Glue |
| `06-step-functions.yaml` | Workflow orchestration | Lambda functions |

### Key Resources Created

#### S3 Buckets
- **Data Lake Bucket**: Raw and processed data storage
- **Iceberg Warehouse Bucket**: Iceberg table metadata and data
- **Artifacts Bucket**: Deployment artifacts and scripts
- **Athena Results Bucket**: Query results storage

#### Glue Resources
- **Iceberg Database**: Glue catalog database for Iceberg tables
- **ETL Jobs**: User transformation, order transformation, maintenance
- **Crawlers**: Automatic schema discovery

#### Lambda Functions
- **extract-database**: Database data extraction
- **extract-api**: REST API data extraction
- **data-quality**: Data validation and quality checks
- **load-redshift**: Redshift data loading
- **stream-processor**: Real-time stream processing
- **iceberg-table-manager**: Iceberg table operations
- **iceberg-migration**: Parquet to Iceberg migration
- **iceberg-time-travel**: Historical data queries

#### Other Resources
- **Redshift Cluster**: Data warehouse
- **Step Functions**: ETL workflow orchestration
- **EventBridge Rules**: Scheduled executions
- **CloudWatch**: Monitoring and logging
- **Athena Workgroup**: Iceberg query execution

## 🔧 Configuration Options

### Environment-Specific Settings

The pipeline supports three environments with different configurations:

#### Development (`dev`)
- Single-node Redshift cluster
- Minimal resource allocation
- Shorter data retention periods
- Relaxed security settings for testing

#### Staging (`staging`)
- Production-like configuration
- Full resource allocation
- Production data retention
- Production security settings
- Used for integration testing

#### Production (`prod`)
- Multi-node Redshift cluster
- Maximum resource allocation
- Long-term data retention
- Strict security settings
- High availability configuration

### Customization Parameters

You can customize the deployment by modifying parameters in the CloudFormation templates:

```yaml
# Example parameter overrides
Parameters:
  ProjectName: "my-etl-pipeline"
  Environment: "prod"
  RedshiftNodeType: "ra3.4xlarge"
  RedshiftClusterType: "multi-node"
  RedshiftNumberOfNodes: 3
  DataRetentionDays: 2555  # 7 years
```

## 🔍 Monitoring and Validation

### Post-Deployment Checks

After deployment, verify the following:

1. **CloudFormation Stacks**
   ```bash
   aws cloudformation describe-stacks --stack-name etl-pipeline-dev-master
   ```

2. **S3 Buckets**
   ```bash
   aws s3 ls | grep etl-pipeline
   ```

3. **Glue Jobs**
   ```bash
   aws glue get-jobs --query 'Jobs[?contains(Name, `etl-pipeline`)]'
   ```

4. **Lambda Functions**
   ```bash
   aws lambda list-functions --query 'Functions[?contains(FunctionName, `etl-pipeline`)]'
   ```

5. **Redshift Cluster**
   ```bash
   aws redshift describe-clusters --cluster-identifier etl-pipeline-dev-redshift-cluster
   ```

### Monitoring Dashboards

The deployment creates CloudWatch dashboards for monitoring:

- **ETL Pipeline Overview**: High-level metrics and status
- **Data Quality Dashboard**: Data validation results
- **Iceberg Tables Dashboard**: Table statistics and maintenance
- **Cost Optimization Dashboard**: Resource utilization and costs

Access dashboards at: https://console.aws.amazon.com/cloudwatch/home#dashboards:

## 🧪 Testing the Pipeline

### 1. Manual Test Execution

Trigger the Step Functions workflow manually:

```bash
aws stepfunctions start-execution \
  --state-machine-arn "arn:aws:states:us-east-1:123456789012:stateMachine:etl-pipeline-dev-etl-pipeline" \
  --input '{"execution_type": "manual", "test_mode": true}'
```

### 2. Sample Data Generation

Use the provided script to generate test data:

```bash
python aws-etl-pipeline/scripts/generate-sample-data.py \
  --environment dev \
  --records 10000
```

### 3. Iceberg Time Travel Testing

Test time travel functionality:

```bash
# Invoke time travel Lambda function
aws lambda invoke \
  --function-name etl-pipeline-dev-iceberg-time-travel \
  --payload '{"table_name": "dim_users", "timestamp": "2024-01-15T10:00:00Z", "query": "SELECT COUNT(*) FROM dim_users"}' \
  response.json
```

## 🚨 Troubleshooting

### Common Issues

#### 1. CloudFormation Stack Failures

**Issue**: Stack creation fails with permission errors
**Solution**: 
```bash
# Check IAM permissions
aws iam simulate-principal-policy \
  --policy-source-arn "arn:aws:iam::123456789012:user/your-user" \
  --action-names "cloudformation:CreateStack" \
  --resource-arns "*"
```

#### 2. Lambda Function Timeouts

**Issue**: Lambda functions timeout during execution
**Solution**: Increase timeout and memory in CloudFormation template:
```yaml
Timeout: 900  # 15 minutes
MemorySize: 1024  # 1GB
```

#### 3. Glue Job Failures

**Issue**: Glue jobs fail with Iceberg dependencies
**Solution**: Verify Glue version and Iceberg configuration:
```yaml
GlueVersion: '4.0'  # Required for Iceberg support
DefaultArguments:
  '--additional-python-modules': 'pyiceberg'
```

#### 4. Redshift Connection Issues

**Issue**: Cannot connect to Redshift cluster
**Solution**: Check security group and VPC configuration:
```bash
# Test connectivity
aws redshift describe-clusters --cluster-identifier your-cluster-id
```

### Log Analysis

Check CloudWatch logs for detailed error information:

```bash
# Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/etl-pipeline"

# Glue job logs
aws logs describe-log-groups --log-group-name-prefix "/aws-glue/jobs"

# Step Functions logs
aws logs describe-log-groups --log-group-name-prefix "/aws/stepfunctions"
```

## 🔒 Security Best Practices

### 1. IAM Permissions
- Use least privilege principle
- Separate roles for different components
- Regular permission audits

### 2. Data Encryption
- KMS encryption for all S3 buckets
- Encrypted Redshift cluster
- Encrypted Lambda environment variables

### 3. Network Security
- VPC isolation for sensitive components
- Private subnets for databases
- Security groups with minimal access

### 4. Secrets Management
- AWS Secrets Manager for credentials
- No hardcoded passwords
- Automatic secret rotation

## 💰 Cost Optimization

### Resource Right-Sizing

Monitor and optimize resource usage:

1. **Glue Jobs**: Use appropriate DPU allocation
2. **Lambda Functions**: Optimize memory and timeout
3. **Redshift**: Use reserved instances for production
4. **S3**: Implement lifecycle policies

### Cost Monitoring

Set up cost alerts:

```bash
aws budgets create-budget \
  --account-id 123456789012 \
  --budget file://budget-config.json
```

## 📚 Additional Resources

- [AWS Glue with Apache Iceberg](https://docs.aws.amazon.com/glue/latest/dg/aws-glue-programming-etl-format-iceberg.html)
- [Apache Iceberg Documentation](https://iceberg.apache.org/docs/latest/)
- [AWS Step Functions Best Practices](https://docs.aws.amazon.com/step-functions/latest/dg/bp-lambda-serviceexception.html)
- [CloudFormation Best Practices](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/best-practices.html)

## 🆘 Support

For issues and questions:

1. Check the troubleshooting section above
2. Review CloudWatch logs
3. Consult AWS documentation
4. Open an issue in the project repository

---

**Happy Data Engineering! 🚀**