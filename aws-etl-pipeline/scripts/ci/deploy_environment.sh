#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:?Environment is required (dev|prod)}"
ARTIFACT_NAME="${2:?Artifact name is required}"
REDSHIFT_PASSWORD="${3:?Redshift password is required}"

if [[ ! "${ENVIRONMENT}" =~ ^(dev|prod)$ ]]; then
  echo "Invalid environment: ${ENVIRONMENT}. Allowed values: dev, prod"
  exit 1
fi

if [ ! -f "dist/${ARTIFACT_NAME}" ]; then
  echo "Artifact not found: dist/${ARTIFACT_NAME}"
  exit 1
fi

export REDSHIFT_PASSWORD
export BUILD_NUMBER="${BUILD_NUMBER:-${ARTIFACT_NAME%.tar.gz}}"

echo "Deploying environment: ${ENVIRONMENT}"
echo "Using build number: ${BUILD_NUMBER}"

bash scripts/deploy.sh "${ENVIRONMENT}" "${BUILD_NUMBER}"
