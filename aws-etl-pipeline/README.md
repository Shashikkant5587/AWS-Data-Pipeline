# AWS ETL Pipeline with Bitbucket CI/CD

A comprehensive, production-ready ETL (Extract, Transform, Load) pipeline built on AWS using Infrastructure as Code (CloudFormation) and automated deployment through Bitbucket Pipelines.

## 🏗️ Architecture Overview

This ETL pipeline provides:

- **Data Extraction**: From databases (PostgreSQL/MySQL) and REST APIs
- **Data Transformation**: Using AWS Glue with PySpark
- **Data Loading**: Into Amazon Redshift data warehouse
- **Stream Processing**: Real-time data processing with Kinesis
- **Orchestration**: Workflow management with Step Functions
- **Monitoring**: CloudWatch dashboards and SNS alerts
- **CI/CD**: Automated deployment with Bitbucket Pipelines

### AWS Services Used

- **Storage**: Amazon S3 (Data Lake), Amazon Redshift (Data Warehouse)
- **Compute**: AWS Lambda, AWS Glue, Amazon EMR
- **Orchestration**: AWS Step Functions, Amazon EventBridge
- **Streaming**: Amazon Kinesis Data Streams, Kinesis Data Firehose
- **Monitoring**: Amazon CloudWatch, AWS SNS, AWS X-Ray
- **Security**: AWS IAM, AWS KMS, AWS Secrets Manager
- **Networking**: Amazon VPC, VPC Endpoints

## 📋 Prerequisites

### AWS Account Setup
1. AWS Account with appropriate permissions
2. AWS CLI configured with credentials
3. Sufficient service limits for:
   - Lambda functions (10+)
   - Glue jobs (5+)
   - Redshift cluster
   - S3 buckets

### Bitbucket Repository Setup
1. Bitbucket repository with this code
2. Bitbucket Pipelines enabled
3. Repository variables configured (see Configuration section)

### Local Development
```bash
# Required tools
aws-cli >= 2.0
python >= 3.9
cfn-lint
pytest
```

## 🚀 Quick Start

### 1. Fork and Clone Repository
```bash
git clone https://your-username@bitbucket.org/your-username/aws-etl-pipeline.git
cd aws-etl-pipeline
```

### 2. Configure Bitbucket Repository Variables

In your Bitbucket repository, go to **Repository Settings > Pipelines > Repository variables** and add:

#### Required Variables
```bash
# AWS Credentials for Development
AWS_ACCESS_KEY_ID_DEV=your-dev-access-key
AWS_SECRET_ACCESS_KEY_DEV=your-dev-secret-key

# AWS Credentials for Staging  
AWS_ACCESS_KEY_ID_STAGING=your-staging-access-key
AWS_SECRET_ACCESS_KEY_STAGING=your-staging-secret-key

# AWS Credentials for Production
AWS_ACCESS_KEY_ID_PROD=your-prod-access-key
AWS_SECRET_ACCESS_KEY_PROD=your-prod-secret-key

# Deployment Configuration
AWS_DEFAULT_REGION=us-east-1
ARTIFACTS_BUCKET=your-artifacts-bucket-name
ALERT_EMAIL=your-email@example.com

# Optional: Redshift Password (will be generated if not provided)
REDSHIFT_PASSWORD=your-secure-password
```

#### Secured Variables (mark as secured)
- All AWS credentials
- REDSHIFT_PASSWORD

### 3. Create Artifacts Bucket

Create an S3 bucket for storing deployment artifacts:

```bash
aws s3 mb s3://your-artifacts-bucket-name --region us-east-1
```

### 4. Deploy Infrastructure

#### Option A: Automatic Deployment via Bitbucket Pipelines

1. **Development Deployment**:
   - Push to `develop` branch
   - Go to Bitbucket Pipelines
   - Manually trigger "deploy-dev" step

2. **Staging Deployment**:
   - Push to `main` branch  
   - Manually trigger "deploy-staging" step

3. **Production Deployment**:
   - Create a tag: `git tag v1.0.0 && git push origin v1.0.0`
   - Manually trigger "deploy-prod" step

#### Option B: Manual Deployment

```bash
# Set environment variables
export ENVIRONMENT=dev
export BUILD_NUMBER=$(date +%Y%m%d_%H%M%S)
export ARTIFACTS_BUCKET=your-artifacts-bucket-name

# Upload artifacts
aws s3 cp infrastructure/ s3://$ARTIFACTS_BUCKET/cloudformation/$BUILD_NUMBER/ --recursive
aws s3 cp glue-jobs/ s3://$ARTIFACTS_BUCKET/glue-scripts/$BUILD_NUMBER/ --recursive

# Deploy infrastructure
chmod +x scripts/deploy.sh
./scripts/deploy.sh $ENVIRONMENT $BUILD_NUMBER

# Deploy Glue jobs
chmod +x scripts/deploy-glue-jobs.sh
./scripts/deploy-glue-jobs.sh $ENVIRONMENT $BUILD_NUMBER
```

## 📊 Data Flow

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Data Sources  │    │   Extraction    │    │   Data Lake     │
│                 │    │                 │    │     (S3)        │
│ • PostgreSQL    │───▶│ • Lambda Funcs  │───▶│                 │
│ • MySQL         │    │ • Glue Jobs     │    │ • Raw Data      │
│ • REST APIs     │    │ • Schedulers    │    │ • Processed     │
│ • Streaming     │    │                 │    │ • Quarantine    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                       │
┌─────────────────┐    ┌─────────────────┐           │
│  Data Warehouse │    │ Transformation  │           │
│   (Redshift)    │    │                 │           │
│                 │◀───│ • Glue ETL Jobs │◀──────────┘
│ • Dimensions    │    │ • Data Quality  │
│ • Facts         │    │ • Business Logic│
│ • Aggregates    │    │                 │
└─────────────────┘    └─────────────────┘
```

## 🔧 Configuration

### Environment-Specific Settings

The pipeline supports three environments with different configurations:

| Setting | Development | Staging | Production |
|---------|-------------|---------|------------|
| Redshift Node Type | dc2.large | dc2.large | dc2.large |
| Redshift Cluster | single-node | single-node | multi-node |
| Log Retention | 7 days | 14 days | 30 days |
| Monitoring | Basic | Enhanced | Full |

### Database Credentials

Store database credentials in AWS Secrets Manager:

```bash
# Example: PostgreSQL credentials
aws secretsmanager create-secret \
    --name "etl-pipeline/dev/source-db/credentials" \
    --description "Source database credentials for ETL pipeline" \
    --secret-string '{
        "engine": "postgresql",
        "host": "your-db-host.amazonaws.com",
        "port": 5432,
        "database": "your_database",
        "username": "your_username",
        "password": "your_password"
    }'
```

### API Credentials

Store API credentials in AWS Secrets Manager:

```bash
# Example: REST API credentials
aws secretsmanager create-secret \
    --name "etl-pipeline/dev/api/credentials" \
    --description "API credentials for ETL pipeline" \
    --secret-string '{
        "base_url": "https://api.example.com/v1",
        "auth_type": "bearer",
        "token": "your-api-token",
        "endpoints": {
            "orders": {
                "path": "/orders",
                "records_path": "data"
            },
            "users": {
                "path": "/users", 
                "records_path": "results"
            }
        }
    }'
```

## 🧪 Testing

### Local Testing

```bash
# Install dependencies
pip install -r requirements-dev.txt

# Run unit tests
pytest lambda/*/tests/ -v

# Run CloudFormation validation
cfn-lint infrastructure/*.yaml

# Run integration tests (requires deployed infrastructure)
pytest tests/integration/ -v --environment=dev
```

### Generate Sample Data

```bash
# Generate sample data for testing
python scripts/generate-sample-data.py --environment dev --users 1000 --orders 5000

# Upload to specific bucket
python scripts/generate-sample-data.py --bucket your-bucket-name --users 500
```

## 📈 Monitoring and Alerting

### CloudWatch Dashboards

The pipeline creates several CloudWatch dashboards:

- **ETL Pipeline Overview**: High-level metrics and status
- **Data Quality Dashboard**: Data quality metrics and trends
- **Performance Dashboard**: Processing times and throughput
- **Error Dashboard**: Error rates and failure analysis

### SNS Alerts

Alerts are sent for:

- Pipeline execution failures
- Data quality threshold breaches
- Resource utilization anomalies
- Cost threshold exceeded

### Accessing Dashboards

```bash
# Get dashboard URLs
aws cloudwatch list-dashboards --region us-east-1

# View Step Functions executions
aws stepfunctions list-executions --state-machine-arn <state-machine-arn>
```

## 🔍 Troubleshooting

### Common Issues

#### 1. Pipeline Execution Failures

```bash
# Check Step Functions execution
aws stepfunctions describe-execution --execution-arn <execution-arn>

# Check Lambda function logs
aws logs describe-log-streams --log-group-name /aws/lambda/etl-pipeline-dev-extract-database
```

#### 2. Glue Job Failures

```bash
# Check Glue job runs
aws glue get-job-runs --job-name etl-pipeline-dev-transform-users

# View Glue job logs in CloudWatch
aws logs filter-log-events --log-group-name /aws-glue/jobs/logs-v2
```

#### 3. Redshift Connection Issues

```bash
# Test Redshift connectivity
psql -h <redshift-endpoint> -p 5439 -U etladmin -d etldb -c "SELECT 1;"

# Check security group rules
aws ec2 describe-security-groups --group-ids <security-group-id>
```

#### 4. S3 Access Issues

```bash
# Check bucket permissions
aws s3api get-bucket-policy --bucket <bucket-name>

# Test S3 access
aws s3 ls s3://<bucket-name>/raw-data/
```

### Debug Mode

Enable debug logging by setting environment variables:

```bash
# For Lambda functions
LOG_LEVEL=DEBUG

# For Glue jobs
--enable-continuous-cloudwatch-log=true
```

## 🔒 Security Best Practices

### IAM Roles and Policies

- **Principle of Least Privilege**: Each service has minimal required permissions
- **Cross-Service Access**: Uses IAM roles instead of access keys
- **Resource-Based Policies**: S3 buckets and KMS keys have resource policies

### Data Encryption

- **At Rest**: S3 (AES-256), Redshift (KMS), RDS (KMS)
- **In Transit**: TLS 1.2+ for all communications
- **Key Management**: AWS KMS with customer-managed keys

### Network Security

- **VPC Isolation**: Redshift and Lambda functions in private subnets
- **VPC Endpoints**: Secure communication with AWS services
- **Security Groups**: Restrictive inbound/outbound rules

### Secrets Management

- **AWS Secrets Manager**: All credentials stored securely
- **Automatic Rotation**: Database passwords rotated automatically
- **Access Logging**: All secret access logged via CloudTrail

## 💰 Cost Optimization

### Resource Right-Sizing

- **Redshift**: Start with dc2.large, scale based on usage
- **Lambda**: Optimize memory allocation based on execution time
- **Glue**: Use job bookmarks to avoid reprocessing data

### Storage Optimization

- **S3 Lifecycle Policies**: Automatic transition to cheaper storage classes
- **Data Compression**: Parquet format with Snappy compression
- **Partitioning**: Efficient data organization for query performance

### Monitoring Costs

```bash
# Set up cost alerts
aws budgets create-budget --account-id <account-id> --budget file://budget.json

# Monitor daily costs
aws ce get-cost-and-usage --time-period Start=2024-01-01,End=2024-01-31 --granularity DAILY
```

## 🚀 Scaling and Performance

### Horizontal Scaling

- **Lambda Concurrency**: Adjust reserved concurrency based on load
- **Glue DPUs**: Increase for larger datasets
- **Redshift**: Add nodes or upgrade node types

### Performance Tuning

- **Redshift**: 
  - Use appropriate distribution and sort keys
  - Regular VACUUM and ANALYZE operations
  - Workload Management (WLM) configuration

- **Glue**:
  - Optimize Spark configurations
  - Use pushdown predicates
  - Enable job bookmarks

### Monitoring Performance

```bash
# Redshift query performance
SELECT query, elapsed, rows 
FROM stl_query_metrics 
WHERE userid > 1 
ORDER BY elapsed DESC 
LIMIT 10;

# Glue job metrics
aws glue get-job-runs --job-name <job-name> --max-results 10
```

## 📚 Additional Resources

### Documentation

- [AWS Glue Developer Guide](https://docs.aws.amazon.com/glue/)
- [Amazon Redshift Database Developer Guide](https://docs.aws.amazon.com/redshift/)
- [AWS Step Functions Developer Guide](https://docs.aws.amazon.com/step-functions/)

### Best Practices

- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [Data Lake Best Practices](https://aws.amazon.com/big-data/datalakes-and-analytics/)
- [ETL Best Practices](https://docs.aws.amazon.com/prescriptive-guidance/latest/patterns/etl-best-practices.html)

### Community

- [AWS Big Data Blog](https://aws.amazon.com/blogs/big-data/)
- [AWS Analytics Community](https://aws.amazon.com/developer/community/analytics/)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

For support and questions:

1. Check the [Troubleshooting](#troubleshooting) section
2. Review [AWS Documentation](https://docs.aws.amazon.com/)
3. Open an issue in this repository
4. Contact your AWS support team

---

**Built with ❤️ for scalable data processing on AWS**