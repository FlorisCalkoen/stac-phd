#!/bin/bash
set -euo pipefail

# Disable AWS CLI v2 pager. By default it pipes all command output through 
# less, which blocks and waits for you to press q.
export AWS_PAGER=""

# ---------------------------------------------------------------------------
# setup-aws-buckets.sh
#
# Creates two S3 buckets for hosting a static STAC catalog on AWS:
#   1. A public STAC metadata bucket (JSON files)
#   2. A public + requester-pays data bucket (Parquet, COG, etc.)
#
# Prerequisites:
#   - AWS CLI v2 installed and configured (`aws configure`)
#   - Sufficient IAM permissions (s3, s3api, budgets)
#
# Usage:
#   export ALERT_EMAIL="you@example.com"
#   bash scripts/bash/setup-aws-buckets.sh
# ---------------------------------------------------------------------------

# --- Configuration (override via environment variables) --------------------
AWS_REGION="${AWS_REGION:-eu-central-1}"
STAC_BUCKET="${STAC_BUCKET:-calkoen-stac-phd}"
DATA_BUCKET="${DATA_BUCKET:-calkoen-data-phd}"
ALERT_EMAIL="${ALERT_EMAIL:?Error: set ALERT_EMAIL env var (e.g. export ALERT_EMAIL=you@example.com)}"
BUDGET_LIMIT="${BUDGET_LIMIT:-10}"  # Monthly budget in USD

echo "============================================================"
echo " AWS S3 Bucket Setup for Static STAC Catalog"
echo "============================================================"
echo " Region:       ${AWS_REGION}"
echo " STAC bucket:  ${STAC_BUCKET}"
echo " Data bucket:  ${DATA_BUCKET}"
echo " Alert email:  ${ALERT_EMAIL}"
echo " Budget limit: \$${BUDGET_LIMIT}/month"
echo "============================================================"
echo ""

# --- Helper ----------------------------------------------------------------
create_bucket() {
    local bucket="$1"
    if aws s3api head-bucket --bucket "${bucket}" 2>/dev/null; then
        echo "Bucket '${bucket}' already exists — skipping creation."
    else
        echo "Creating bucket '${bucket}' in ${AWS_REGION}..."
        aws s3api create-bucket \
            --bucket "${bucket}" \
            --region "${AWS_REGION}" \
            --create-bucket-configuration LocationConstraint="${AWS_REGION}"
    fi
}

# ===========================================================================
# 1. STAC metadata bucket (public-read, standard pricing)
# ===========================================================================
echo "--- [1/7] Creating STAC metadata bucket ---"
create_bucket "${STAC_BUCKET}"

echo "--- [2/7] Configuring STAC bucket public access ---"
aws s3api put-public-access-block \
    --bucket "${STAC_BUCKET}" \
    --public-access-block-configuration \
        BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false

aws s3api put-bucket-policy \
    --bucket "${STAC_BUCKET}" \
    --policy "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [
    {
      \"Sid\": \"PublicReadSTAC\",
      \"Effect\": \"Allow\",
      \"Principal\": \"*\",
      \"Action\": \"s3:GetObject\",
      \"Resource\": \"arn:aws:s3:::${STAC_BUCKET}/*\"
    }
  ]
}"

echo "--- [3/7] Enabling CORS on STAC bucket (for browser-based STAC clients) ---"
aws s3api put-bucket-cors \
    --bucket "${STAC_BUCKET}" \
    --cors-configuration '{
  "CORSRules": [
    {
      "AllowedHeaders": ["*"],
      "AllowedMethods": ["GET", "HEAD"],
      "AllowedOrigins": ["*"],
      "ExposeHeaders": ["ETag", "Content-Length", "Content-Type"],
      "MaxAgeSeconds": 3600
    }
  ]
}'

# ===========================================================================
# 2. Data bucket (public-read + requester pays)
# ===========================================================================
echo "--- [4/7] Creating data bucket ---"
create_bucket "${DATA_BUCKET}"

echo "--- [5/7] Configuring data bucket public access + requester pays ---"
aws s3api put-public-access-block \
    --bucket "${DATA_BUCKET}" \
    --public-access-block-configuration \
        BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false

aws s3api put-bucket-policy \
    --bucket "${DATA_BUCKET}" \
    --policy "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [
    {
      \"Sid\": \"PublicReadData\",
      \"Effect\": \"Allow\",
      \"Principal\": \"*\",
      \"Action\": \"s3:GetObject\",
      \"Resource\": \"arn:aws:s3:::${DATA_BUCKET}/*\"
    }
  ]
}"

aws s3api put-bucket-request-payment \
    --bucket "${DATA_BUCKET}" \
    --request-payment-configuration Payer=Requester

echo "--- [6/7] Enabling CORS on data bucket ---"
aws s3api put-bucket-cors \
    --bucket "${DATA_BUCKET}" \
    --cors-configuration '{
  "CORSRules": [
    {
      "AllowedHeaders": ["Range"],
      "AllowedMethods": ["GET", "HEAD"],
      "AllowedOrigins": ["*"],
      "ExposeHeaders": ["ETag", "Content-Length", "Content-Range", "Content-Type"],
      "MaxAgeSeconds": 86400
    }
  ]
}'

# ===========================================================================
# 3. Budget alarm
# ===========================================================================
echo "--- [7/7] Creating monthly budget alarm (\$${BUDGET_LIMIT}) ---"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws budgets create-budget \
    --account-id "${AWS_ACCOUNT_ID}" \
    --budget "{
  \"BudgetName\": \"stac-s3-monthly\",
  \"BudgetLimit\": {
    \"Amount\": \"${BUDGET_LIMIT}\",
    \"Unit\": \"USD\"
  },
  \"TimeUnit\": \"MONTHLY\",
  \"BudgetType\": \"COST\"
}" \
    --notifications-with-subscribers "[
  {
    \"Notification\": {
      \"NotificationType\": \"ACTUAL\",
      \"ComparisonOperator\": \"GREATER_THAN\",
      \"Threshold\": 50,
      \"ThresholdType\": \"PERCENTAGE\"
    },
    \"Subscribers\": [{
      \"SubscriptionType\": \"EMAIL\",
      \"Address\": \"${ALERT_EMAIL}\"
    }]
  },
  {
    \"Notification\": {
      \"NotificationType\": \"ACTUAL\",
      \"ComparisonOperator\": \"GREATER_THAN\",
      \"Threshold\": 80,
      \"ThresholdType\": \"PERCENTAGE\"
    },
    \"Subscribers\": [{
      \"SubscriptionType\": \"EMAIL\",
      \"Address\": \"${ALERT_EMAIL}\"
    }]
  },
  {
    \"Notification\": {
      \"NotificationType\": \"FORECASTED\",
      \"ComparisonOperator\": \"GREATER_THAN\",
      \"Threshold\": 100,
      \"ThresholdType\": \"PERCENTAGE\"
    },
    \"Subscribers\": [{
      \"SubscriptionType\": \"EMAIL\",
      \"Address\": \"${ALERT_EMAIL}\"
    }]
  }
]" 2>/dev/null && echo "Budget alarm created." || echo "Budget alarm already exists or could not be created (check AWS console)."

# ===========================================================================
# Summary
# ===========================================================================
STAC_URL="https://${STAC_BUCKET}.s3.${AWS_REGION}.amazonaws.com"
DATA_URL="https://${DATA_BUCKET}.s3.${AWS_REGION}.amazonaws.com"

echo ""
echo "============================================================"
echo " Setup complete!"
echo "============================================================"
echo ""
echo " STAC catalog URL (use as CATALOG_PUBLISHED_URL):"
echo "   ${STAC_URL}/v1/catalog.json"
echo ""
echo " Data bucket URL:"
echo "   ${DATA_URL}/"
echo ""
echo " Next steps:"
echo "   1. Update CATALOG_PUBLISHED_URL in make_catalog.py"
echo "   2. Update asset hrefs from az:// to s3://${DATA_BUCKET}/..."
echo "   3. Sync STAC JSON:  aws s3 sync ./release/v1 s3://${STAC_BUCKET}/v1/"
echo "   4. Sync data files: aws s3 sync <data-dir> s3://${DATA_BUCKET}/"
echo "============================================================"