#!/usr/bin/env bash
# Usage: ./scripts/check-upstream.sh <container-name>
# Prints the latest upstream version to stdout.
# Exits non-zero on error.

set -euo pipefail

CONTAINER="${1:?Usage: check-upstream.sh <container-name>}"
VALUES="containers/${CONTAINER}/ci/values.yaml"

if [[ ! -f "$VALUES" ]]; then
	echo "ERROR: ${VALUES} not found" >&2
	exit 1
fi

# Parse YAML fields (simple grep — no yq dependency)
SOURCE=$(grep '^  source:' "$VALUES" | awk '{print $2}')
PACKAGE=$(grep '^  package:' "$VALUES" | awk '{print $2}' | tr -d '"')

case "$SOURCE" in
npm)
	npm view "$PACKAGE" version 2>/dev/null
	;;
github)
	# PACKAGE format: owner/repo
	curl -fsSL "https://api.github.com/repos/${PACKAGE}/releases/latest" |
		grep '"tag_name"' |
		head -1 |
		sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' |
		sed 's/^v//'
	;;
*)
	echo "ERROR: Unknown upstream source '${SOURCE}'" >&2
	exit 1
	;;
esac
