pipeline {
    agent any
    environment {
        AWS_DEFAULT_REGION = 'us-east-1'
    }
    stages {
        stage('Clone Repository') {
            steps {
                git 'https://github.com/Shashikkant5587/AWS-Data-Pipeline.git'
            }
        }
        stage('Deploy CloudFormation Stack') {
            steps {
                sh 'aws cloudformation deploy --stack-name MyDataPipelineStack --template-file template.yml --capabilities CAPABILITY_NAMED_IAM'
            }
        }
    }
}