#!/bin/bash

# This script cleans up unwanted item directories created by the default
# pystac layout strategy. It loops through each collection in the release
# directory and removes any subdirectory that is NOT named 'items'.

# Set the target directory where your collections are located.
RELEASE_DIR="release/v1"

# Check if the target directory exists to prevent errors.
if [ ! -d "$RELEASE_DIR" ]; then
  echo "Error: Directory '$RELEASE_DIR' not found."
  echo "Please run this script from the root of your 'stac-phd' project."
  exit 1
fi

echo "Starting cleanup of unwanted item directories in '$RELEASE_DIR'..."

# Loop through each collection directory (e.g., release/v1/coastal-grid/).
for collection_dir in "$RELEASE_DIR"/*/; do
    if [ -d "$collection_dir" ]; then
        echo "Processing collection: $(basename "$collection_dir")"
        
        # Loop through all subdirectories within the collection directory.
        for item_dir in "$collection_dir"*/; do
            # Check if it's a directory AND its name is not 'items'.
            if [ -d "$item_dir" ] && [ "$(basename "$item_dir")" != "items" ]; then
                echo "  - Removing unwanted directory: $item_dir"
                rm -rf "$item_dir"
            fi
        done
    fi
done

echo "Cleanup complete."