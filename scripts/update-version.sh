#!/usr/bin/env bash
# Usage: ./scripts/update-version.sh <container-name> <new-version>
# Updates the version field in containers/<name>/ci/values.yaml.

set -euo pipefail

CONTAINER="${1:?Usage: update-version.sh <container-name> <new-version>}"
NEW_VERSION="${2:?Usage: update-version.sh <container-name> <new-version>}"
VALUES="containers/${CONTAINER}/ci/values.yaml"

if [[ ! -f "$VALUES" ]]; then
	echo "ERROR: ${VALUES} not found" >&2
	exit 1
fi

CURRENT=$(grep '^  version:' "$VALUES" | awk '{print $2}' | tr -d '"')

if [[ "$CURRENT" == "$NEW_VERSION" ]]; then
	echo "Already at version ${NEW_VERSION}, nothing to do."
	exit 0
fi

# In-place sed that works on both macOS and Linux
if sed --version 2>/dev/null | grep -q GNU; then
	sed -i "s/^  version: \".*\"/  version: \"${NEW_VERSION}\"/" "$VALUES"
else
	sed -i '' "s/^  version: \".*\"/  version: \"${NEW_VERSION}\"/" "$VALUES"
fi

echo "Updated ${CONTAINER}: ${CURRENT} → ${NEW_VERSION}"
