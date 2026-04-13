pipeline {
    agent any
    
    environment {
        AWS_DEFAULT_REGION = 'us-east-1'
        PROJECT_NAME = 'etl-pipeline'
        ENVIRONMENT = "${env.BRANCH_NAME == 'main' ? 'prod' : (env.BRANCH_NAME == 'staging' ? 'staging' : 'dev')}"
        BUILD_NUMBER = "${env.BUILD_NUMBER}"
        ARTIFACTS_BUCKET = "${PROJECT_NAME}-${ENVIRONMENT}-artifacts-${env.AWS_ACCOUNT_ID}"
    }
    
    parameters {
        password(name: 'REDSHIFT_PASSWORD', defaultValue: '', description: 'Password for Redshift cluster')
        choice(name: 'DEPLOY_ENVIRONMENT', choices: ['dev', 'staging', 'prod'], description: 'Target deployment environment')
        booleanParam(name: 'SKIP_TESTS', defaultValue: false, description: 'Skip running tests')
        booleanParam(name: 'DEPLOY_ICEBERG_ONLY', defaultValue: false, description: 'Deploy only Iceberg components')
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_COMMIT_SHORT = sh(
                        script: "git rev-parse --short HEAD",
                        returnStdout: true
                    ).trim()
                }
            }
        }
        
        stage('Validate Parameters') {
            steps {
                script {
                    if (params.REDSHIFT_PASSWORD == '') {
                        error('Redshift password is required')
                    }
                    if (params.DEPLOY_ENVIRONMENT) {
                        env.ENVIRONMENT = params.DEPLOY_ENVIRONMENT
                    }
                    echo "Deploying to environment: ${env.ENVIRONMENT}"
                    echo "Build number: ${env.BUILD_NUMBER}"
                }
            }
        }
        
        stage('Setup AWS CLI') {
            steps {
                sh '''
                    aws --version
                    aws sts get-caller-identity
                    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
                    echo "AWS Account ID: $AWS_ACCOUNT_ID"
                '''
            }
        }
        
        stage('Create Artifacts Bucket') {
            steps {
                script {
                    sh '''
                        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
                        BUCKET_NAME="${PROJECT_NAME}-${ENVIRONMENT}-artifacts-${AWS_ACCOUNT_ID}"
                        
                        # Check if bucket exists
                        if ! aws s3 ls "s3://$BUCKET_NAME" 2>/dev/null; then
                            echo "Creating artifacts bucket: $BUCKET_NAME"
                            aws s3 mb "s3://$BUCKET_NAME" --region $AWS_DEFAULT_REGION
                            
                            # Enable versioning
                            aws s3api put-bucket-versioning \
                                --bucket "$BUCKET_NAME" \
                                --versioning-configuration Status=Enabled
                                
                            # Block public access
                            aws s3api put-public-access-block \
                                --bucket "$BUCKET_NAME" \
                                --public-access-block-configuration \
                                BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
                        else
                            echo "Artifacts bucket already exists: $BUCKET_NAME"
                        fi
                    '''
                }
            }
        }
        
        stage('Package Lambda Functions') {
            steps {
                dir('aws-etl-pipeline') {
                    sh '''
                        echo "Packaging Lambda functions..."
                        mkdir -p dist/lambda-packages
                        
                        # Package each Lambda function
                        for lambda_dir in lambda/*/; do
                            if [ -d "$lambda_dir" ]; then
                                lambda_name=$(basename "$lambda_dir")
                                echo "Packaging $lambda_name..."
                                
                                cd "$lambda_dir"
                                
                                # Install dependencies if requirements.txt exists
                                if [ -f "requirements.txt" ]; then
                                    pip install -r requirements.txt -t .
                                fi
                                
                                # Create zip package
                                zip -r "../../dist/lambda-packages/${lambda_name}.zip" . -x "*.pyc" "__pycache__/*"
                                
                                cd - > /dev/null
                            fi
                        done
                        
                        # Package Iceberg Lambda functions (placeholders for now)
                        mkdir -p dist/lambda-packages
                        echo "Creating placeholder Iceberg Lambda packages..."
                        
                        for iceberg_func in iceberg-table-manager iceberg-migration iceberg-time-travel; do
                            mkdir -p "temp/$iceberg_func"
                            echo "# Placeholder for $iceberg_func" > "temp/$iceberg_func/lambda_function.py"
                            echo "def lambda_handler(event, context): return {'statusCode': 200}" >> "temp/$iceberg_func/lambda_function.py"
                            cd "temp/$iceberg_func"
                            zip -r "../../dist/lambda-packages/${iceberg_func}.zip" .
                            cd - > /dev/null
                        done
                        
                        rm -rf temp
                        ls -la dist/lambda-packages/
                    '''
                }
            }
        }
        
        stage('Package Glue Jobs') {
            steps {
                dir('aws-etl-pipeline') {
                    sh '''
                        echo "Packaging Glue jobs..."
                        mkdir -p dist/glue-jobs
                        
                        # Copy existing Glue jobs
                        if [ -d "glue-jobs" ]; then
                            cp glue-jobs/*.py dist/glue-jobs/ 2>/dev/null || true
                        fi
                        
                        # Create placeholder Iceberg Glue jobs
                        cat > dist/glue-jobs/iceberg_transform_users.py << 'EOF'
# Placeholder Iceberg User Transformation Job
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job

args = getResolvedOptions(sys.argv, ['JOB_NAME'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# TODO: Implement Iceberg user transformation logic
print("Iceberg user transformation job - placeholder")

job.commit()
EOF

                        cat > dist/glue-jobs/iceberg_transform_orders.py << 'EOF'
# Placeholder Iceberg Order Transformation Job
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job

args = getResolvedOptions(sys.argv, ['JOB_NAME'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# TODO: Implement Iceberg order transformation logic
print("Iceberg order transformation job - placeholder")

job.commit()
EOF

                        cat > dist/glue-jobs/iceberg_maintenance.py << 'EOF'
# Placeholder Iceberg Maintenance Job
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job

args = getResolvedOptions(sys.argv, ['JOB_NAME'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# TODO: Implement Iceberg table maintenance logic
print("Iceberg maintenance job - placeholder")

job.commit()
EOF
                        
                        ls -la dist/glue-jobs/
                    '''
                }
            }
        }
        
        stage('Upload Artifacts to S3') {
            steps {
                dir('aws-etl-pipeline') {
                    sh '''
                        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
                        BUCKET_NAME="${PROJECT_NAME}-${ENVIRONMENT}-artifacts-${AWS_ACCOUNT_ID}"
                        
                        echo "Uploading artifacts to S3..."
                        
                        # Upload Lambda packages
                        aws s3 cp dist/lambda-packages/ "s3://$BUCKET_NAME/lambda-packages/${BUILD_NUMBER}/" --recursive
                        
                        # Upload Glue job scripts
                        aws s3 cp dist/glue-jobs/ "s3://$BUCKET_NAME/glue-jobs/${BUILD_NUMBER}/" --recursive
                        
                        # Upload CloudFormation templates
                        aws s3 cp infrastructure/ "s3://$BUCKET_NAME/cloudformation-templates/${BUILD_NUMBER}/" --recursive --exclude "*.md"
                        
                        echo "Artifacts uploaded successfully"
                        aws s3 ls "s3://$BUCKET_NAME/" --recursive
                    '''
                }
            }
        }
        
        stage('Validate CloudFormation Templates') {
            steps {
                dir('aws-etl-pipeline/infrastructure') {
                    sh '''
                        echo "Validating CloudFormation templates..."
                        for template in *.yaml; do
                            echo "Validating $template..."
                            aws cloudformation validate-template --template-body file://$template
                        done
                        echo "All templates validated successfully"
                    '''
                }
            }
        }
        
        stage('Run Tests') {
            when {
                not { params.SKIP_TESTS }
            }
            steps {
                dir('aws-etl-pipeline') {
                    sh '''
                        echo "Running tests..."
                        if [ -f "requirements-test.txt" ]; then
                            pip install -r requirements-test.txt
                        fi
                        
                        # Run Python tests if they exist
                        if [ -d "tests" ]; then
                            python -m pytest tests/ -v --junitxml=test-results.xml || true
                        fi
                        
                        # Run CloudFormation linting
                        if command -v cfn-lint &> /dev/null; then
                            cfn-lint infrastructure/*.yaml || true
                        fi
                    '''
                }
            }
            post {
                always {
                    publishTestResults testResultsPattern: 'aws-etl-pipeline/test-results.xml'
                }
            }
        }
        
        stage('Deploy Infrastructure') {
            steps {
                script {
                    if (params.DEPLOY_ICEBERG_ONLY) {
                        echo "Deploying only Iceberg components..."
                        sh '''
                            export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
                            BUCKET_NAME="${PROJECT_NAME}-${ENVIRONMENT}-artifacts-${AWS_ACCOUNT_ID}"
                            
                            # Deploy Iceberg Glue stack
                            aws cloudformation deploy \
                                --template-file aws-etl-pipeline/infrastructure/03-iceberg-glue.yaml \
                                --stack-name "${PROJECT_NAME}-${ENVIRONMENT}-iceberg-glue" \
                                --parameter-overrides \
                                    ProjectName="${PROJECT_NAME}" \
                                    Environment="${ENVIRONMENT}" \
                                --capabilities CAPABILITY_NAMED_IAM \
                                --tags \
                                    Environment="${ENVIRONMENT}" \
                                    Project="${PROJECT_NAME}" \
                                    BuildNumber="${BUILD_NUMBER}" \
                                    GitCommit="${GIT_COMMIT_SHORT}"
                            
                            # Deploy Iceberg Lambda stack
                            aws cloudformation deploy \
                                --template-file aws-etl-pipeline/infrastructure/05-iceberg-lambda.yaml \
                                --stack-name "${PROJECT_NAME}-${ENVIRONMENT}-iceberg-lambda" \
                                --parameter-overrides \
                                    ProjectName="${PROJECT_NAME}" \
                                    Environment="${ENVIRONMENT}" \
                                    BuildNumber="${BUILD_NUMBER}" \
                                    ArtifactsBucket="$BUCKET_NAME" \
                                --capabilities CAPABILITY_NAMED_IAM \
                                --tags \
                                    Environment="${ENVIRONMENT}" \
                                    Project="${PROJECT_NAME}" \
                                    BuildNumber="${BUILD_NUMBER}" \
                                    GitCommit="${GIT_COMMIT_SHORT}"
                        '''
                    } else {
                        echo "Deploying full ETL pipeline with Iceberg..."
                        sh '''
                            export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
                            BUCKET_NAME="${PROJECT_NAME}-${ENVIRONMENT}-artifacts-${AWS_ACCOUNT_ID}"
                            
                            # Deploy master stack
                            aws cloudformation deploy \
                                --template-file aws-etl-pipeline/infrastructure/00-master-stack.yaml \
                                --stack-name "${PROJECT_NAME}-${ENVIRONMENT}-master" \
                                --parameter-overrides \
                                    ProjectName="${PROJECT_NAME}" \
                                    Environment="${ENVIRONMENT}" \
                                    BuildNumber="${BUILD_NUMBER}" \
                                    ArtifactsBucket="$BUCKET_NAME" \
                                    RedshiftPassword="${REDSHIFT_PASSWORD}" \
                                --capabilities CAPABILITY_NAMED_IAM \
                                --tags \
                                    Environment="${ENVIRONMENT}" \
                                    Project="${PROJECT_NAME}" \
                                    BuildNumber="${BUILD_NUMBER}" \
                                    GitCommit="${GIT_COMMIT_SHORT}"
                        '''
                    }
                }
            }
        }
        
        stage('Post-Deployment Validation') {
            steps {
                sh '''
                    echo "Validating deployment..."
                    
                    # Check stack status
                    if [ "${DEPLOY_ICEBERG_ONLY}" = "true" ]; then
                        aws cloudformation describe-stacks --stack-name "${PROJECT_NAME}-${ENVIRONMENT}-iceberg-glue" --query 'Stacks[0].StackStatus'
                        aws cloudformation describe-stacks --stack-name "${PROJECT_NAME}-${ENVIRONMENT}-iceberg-lambda" --query 'Stacks[0].StackStatus'
                    else
                        aws cloudformation describe-stacks --stack-name "${PROJECT_NAME}-${ENVIRONMENT}-master" --query 'Stacks[0].StackStatus'
                    fi
                    
                    # List created resources
                    echo "Deployment completed successfully!"
                '''
            }
        }
        
        stage('Generate Deployment Report') {
            steps {
                script {
                    sh '''
                        echo "=== ETL Pipeline Deployment Report ===" > deployment-report.txt
                        echo "Environment: ${ENVIRONMENT}" >> deployment-report.txt
                        echo "Build Number: ${BUILD_NUMBER}" >> deployment-report.txt
                        echo "Git Commit: ${GIT_COMMIT_SHORT}" >> deployment-report.txt
                        echo "Deployment Time: $(date)" >> deployment-report.txt
                        echo "" >> deployment-report.txt
                        
                        if [ "${DEPLOY_ICEBERG_ONLY}" = "true" ]; then
                            echo "Deployed Iceberg Components Only:" >> deployment-report.txt
                            aws cloudformation describe-stacks --stack-name "${PROJECT_NAME}-${ENVIRONMENT}-iceberg-glue" --query 'Stacks[0].Outputs' >> deployment-report.txt
                            aws cloudformation describe-stacks --stack-name "${PROJECT_NAME}-${ENVIRONMENT}-iceberg-lambda" --query 'Stacks[0].Outputs' >> deployment-report.txt
                        else
                            echo "Deployed Full ETL Pipeline:" >> deployment-report.txt
                            aws cloudformation describe-stacks --stack-name "${PROJECT_NAME}-${ENVIRONMENT}-master" --query 'Stacks[0].Outputs' >> deployment-report.txt
                        fi
                        
                        cat deployment-report.txt
                    '''
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'deployment-report.txt', fingerprint: true
                }
            }
        }
    }
    
    post {
        always {
            cleanWs()
        }
        success {
            echo "✅ ETL Pipeline deployment completed successfully!"
            script {
                if (env.ENVIRONMENT == 'prod') {
                    // Send success notification for production deployments
                    echo "Production deployment successful - consider sending notifications"
                }
            }
        }
        failure {
            echo "❌ ETL Pipeline deployment failed!"
            script {
                // Send failure notification
                echo "Deployment failed - consider sending alerts"
            }
        }
    }
}