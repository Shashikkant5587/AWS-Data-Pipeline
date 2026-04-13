# Jenkins DevOps CI/CD Pipeline (Dev and Prod)

This project now includes an end-to-end Jenkins pipeline with:

- Source checkout and quality checks
- SonarQube static analysis and quality gate
- Build artifact creation
- Artifact publish to JFrog Artifactory
- Automatic deployment to `dev`
- Manual approval gate
- Deployment to `prod`

## Pipeline Flow

1. `Checkout`
2. `Quality And Security`
   - Unit tests
   - SonarQube scan
3. `Sonar Quality Gate`
4. `Build Artifact`
5. `Publish Artifact To JFrog`
6. `Deploy To Dev`
7. `Approval Gate For Prod`
8. `Deploy To Prod`

## Files Added

- `Jenkinsfile`
- `sonar-project.properties`
- `scripts/ci/package_artifacts.sh`
- `scripts/ci/publish_to_jfrog.sh`
- `scripts/ci/deploy_environment.sh`

## Jenkins Prerequisites

Install Jenkins plugins:

- Pipeline
- Credentials Binding
- AWS Credentials
- SonarQube Scanner for Jenkins
- JUnit
- Workspace Cleanup
- Email Extension

Configure Jenkins global tools and integrations:

- SonarQube server name: `sonarqube-server`
- SonarScanner tool name: `sonar-scanner`

Create Jenkins credentials:

- `aws-dev-credentials` (AWS access for Dev account/environment)
- `aws-prod-credentials` (AWS access for Prod account/environment)
- `jfrog-credentials` (username/password or token for JFrog)

## Job Setup

1. Create a Pipeline job in Jenkins.
2. Point SCM to this repository.
3. Set script path to: `Jenkinsfile`
4. Build with parameters and provide:
   - `REDSHIFT_PASSWORD`
   - `EMAIL_RECIPIENTS` (default is `kantshashi250516@gmail.com`)
   - Optional custom credentials IDs
   - Optional `AUTO_APPROVE_PROD=true` for non-interactive promotion

## JFrog Notes

The pipeline uploads artifact to:

`https://your-company.jfrog.io/artifactory/etl-generic-local/<artifact-name>`

Update in `Jenkinsfile` if your JFrog URL or repository differs:

- `JFROG_PLATFORM_URL`
- `JFROG_REPO`

## SonarQube Notes

`sonar-project.properties` is preconfigured for `lambda`, `glue-jobs`, and `scripts`.
Adjust include/exclude rules based on your repository standards.
