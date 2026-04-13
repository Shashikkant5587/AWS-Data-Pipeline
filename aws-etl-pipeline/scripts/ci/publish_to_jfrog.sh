#!/usr/bin/env bash
set -euo pipefail

ARTIFACT_NAME="${1:?Artifact name is required}"
JFROG_URL="${2:?JFrog URL is required}"
JFROG_REPO="${3:?JFrog repository is required}"
JFROG_USER="${4:?JFrog user is required}"
JFROG_PASS="${5:?JFrog password/token is required}"

ARTIFACT_PATH="dist/${ARTIFACT_NAME}"

if [ ! -f "${ARTIFACT_PATH}" ]; then
  echo "Artifact not found: ${ARTIFACT_PATH}"
  exit 1
fi

UPLOAD_URL="${JFROG_URL}/artifactory/${JFROG_REPO}/${ARTIFACT_NAME}"

curl -f -u "${JFROG_USER}:${JFROG_PASS}" \
  -T "${ARTIFACT_PATH}" \
  "${UPLOAD_URL}"

echo "Published ${ARTIFACT_NAME} to ${UPLOAD_URL}"
