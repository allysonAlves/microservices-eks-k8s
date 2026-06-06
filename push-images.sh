#!/bin/bash
# Builds and pushes all Docker images to ECR.
# Run AFTER: terraform apply (to create the ECR repos) and ./setup.sh (to clone source code)
set -e

AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_BASE="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/togglemaster"
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "==> Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

build_and_push() {
  local service=$1
  local context="${PROJECT_ROOT}/services/${service}"
  local image="${ECR_BASE}/${service}:latest"

  echo ""
  echo "==> Building ${service}..."
  docker build --platform linux/amd64 -t "$image" "$context"

  echo "==> Pushing ${service}..."
  docker push "$image"
}

build_and_push auth-service
build_and_push flag-service
build_and_push targeting-service
build_and_push evaluation-service
build_and_push analytics-service

echo ""
echo "All images pushed. Run: kubectl rollout restart deployment -n togglemaster"
