#!/bin/bash
set -euo pipefail
export AWS_PAGER=""

STAC_BUCKET="${STAC_BUCKET:-calkoen-stac-phd}"

echo "Syncing STAC catalog to s3://${STAC_BUCKET}/v1/ ..."
aws s3 sync ./release/v1 "s3://${STAC_BUCKET}/v1/" \
    --delete \
    --content-type "application/json" \
    --size-only

echo "Sync complete."