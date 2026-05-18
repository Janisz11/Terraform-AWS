#!/bin/bash
set -e

REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_BASE="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
SOURCE_DIR="$HOME/chmury/lista4/order_system"

SERVICES=(api_gateway order_service inventory_service payment_service notification_service)

echo "Account ID: ${ACCOUNT_ID}"
echo "ECR base: ${ECR_BASE}"
echo ""

echo "Logging in to ECR..."
aws ecr get-login-password --region "$REGION" | \
    docker login --username AWS --password-stdin "$ECR_BASE"

cd "$SOURCE_DIR"

for SERVICE in "${SERVICES[@]}"; do
    REPO_NAME="order-system-${SERVICE}"
    IMAGE_URI="${ECR_BASE}/${REPO_NAME}:latest"

    echo ""
    echo "=== Building ${SERVICE} ==="
    docker build --build-arg SERVICE="$SERVICE" -t "$REPO_NAME" .

    echo "Tagging ${SERVICE}..."
    docker tag "$REPO_NAME" "$IMAGE_URI"

    echo "Pushing ${SERVICE}..."
    docker push "$IMAGE_URI"

    echo "Done: ${IMAGE_URI}"
done

echo ""
echo "All images pushed successfully!"
echo ""
echo "Image URIs:"
for SERVICE in "${SERVICES[@]}"; do
    echo "  ${ECR_BASE}/order-system-${SERVICE}:latest"
done
