#!/bin/bash

set -e

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Read mod info from info.json
MOD_NAME=$(grep -o '"name": *"[^"]*"' info.json | cut -d'"' -f4)
MOD_VERSION=$(grep -o '"version": *"[^"]*"' info.json | cut -d'"' -f4)

# Output filename follows Factorio convention: modname_version.zip
OUTPUT_NAME="${MOD_NAME}_${MOD_VERSION}"
OUTPUT_FILE="${OUTPUT_NAME}.zip"

echo "Building ${OUTPUT_FILE}..."

# Clean up any existing build
rm -f "$OUTPUT_FILE"

# Create a temporary directory with the correct structure
# Factorio expects mods to be in a folder named modname_version inside the zip
TEMP_DIR=$(mktemp -d)
MOD_DIR="${TEMP_DIR}/${OUTPUT_NAME}"
mkdir -p "$MOD_DIR"

# Copy mod files
cp info.json "$MOD_DIR/"
cp changelog.txt "$MOD_DIR/"
cp thumbnail.png "$MOD_DIR/"
cp control.lua "$MOD_DIR/"
cp settings.lua "$MOD_DIR/"
cp -r sanitize "$MOD_DIR/"
cp -r blueprint "$MOD_DIR/"
cp -r locale "$MOD_DIR/"

# Create the zip file
cd "$TEMP_DIR"
zip -r "$SCRIPT_DIR/$OUTPUT_FILE" "$OUTPUT_NAME"

# Clean up
rm -rf "$TEMP_DIR"

echo ""
echo "Built: $OUTPUT_FILE"
echo ""
