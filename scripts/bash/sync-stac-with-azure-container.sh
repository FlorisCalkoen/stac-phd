#!/bin/bash

echo "Checking for and stopping any lingering azcopy processes..."
pkill -f azcopy || true

export AZCOPY_CONCURRENCY_VALUE=16
echo "AzCopy concurrency set to $AZCOPY_CONCURRENCY_VALUE"

echo "Starting sync with Azure Blob Storage..."
az storage blob sync \
    --account-name coclico \
    --source ./release/v1 \
    --container stac/v1 \
    --delete-destination true

echo "Sync complete."
