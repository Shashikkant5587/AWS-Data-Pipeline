#!/usr/bin/env bash
set -euo pipefail

ARTIFACT_NAME="${1:-etl-pipeline-artifact.tar.gz}"

mkdir -p dist
rm -f "dist/${ARTIFACT_NAME}"

tar -czf "dist/${ARTIFACT_NAME}" \
  infrastructure \
  lambda \
  glue-jobs \
  sql \
  scripts/deploy.sh

echo "Created artifact: dist/${ARTIFACT_NAME}"
