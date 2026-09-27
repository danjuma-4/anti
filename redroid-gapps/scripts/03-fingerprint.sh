#!/bin/bash
# Usage: ./03-fingerprint.sh [10|11|12]
VERSION=$1
JSON_FILE="/root/anti/configs/fingerprints.json"

# Extract values using jq
FP=$(jq -r ".[\"$VERSION\"].fingerprint" $JSON_FILE)
MODEL=$(jq -r ".[\"$VERSION\"].model" $JSON_FILE)

# Apply via setprop to override in-memory properties
# These must be executed with root privileges
setprop ro.build.fingerprint "$FP"
setprop ro.product.model "$MODEL"
setprop ro.build.version.release "$VERSION"

echo "Fingerprint set to: $MODEL (Android $VERSION)"
