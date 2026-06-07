#!/usr/bin/env bash
set -euo pipefail

# Deploy MacroMerit static site to S3 + invalidate CloudFront cache
# Usage: ./scripts/deploy.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
INFRA_DIR="$PROJECT_DIR/infra"
AWS_PROFILE="macromerit-admin"

# Get outputs from OpenTofu
BUCKET=$(cd "$INFRA_DIR" && tofu output -raw s3_bucket)
DIST_ID=$(cd "$INFRA_DIR" && tofu output -raw cloudfront_distribution_id)

echo "Deploying to s3://$BUCKET ..."

# Upload HTML
aws s3 cp "$PROJECT_DIR/index.html" "s3://$BUCKET/index.html" \
  --content-type "text/html; charset=utf-8" \
  --cache-control "max-age=300" \
  --profile "$AWS_PROFILE"

# Upload CSS
aws s3 cp "$PROJECT_DIR/styles.css" "s3://$BUCKET/styles.css" \
  --content-type "text/css; charset=utf-8" \
  --cache-control "max-age=3600" \
  --profile "$AWS_PROFILE"

# Upload assets (if any exist)
if [ -n "$(ls -A "$PROJECT_DIR/assets/" 2>/dev/null)" ]; then
  aws s3 sync "$PROJECT_DIR/assets/" "s3://$BUCKET/assets/" \
    --cache-control "max-age=86400" \
    --profile "$AWS_PROFILE"
fi

echo "Invalidating CloudFront cache ..."
aws cloudfront create-invalidation \
  --distribution-id "$DIST_ID" \
  --paths "/*" \
  --profile "$AWS_PROFILE" \
  --query 'Invalidation.Id' \
  --output text

DOMAIN=$(cd "$INFRA_DIR" && tofu output -raw cloudfront_domain)
echo ""
echo "Deployed! Site is live at:"
echo "  $DOMAIN"
