#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="diversifi-0qxwn"
SLUG="dev"
SPEC_URL="https://dev.diversifi.ai/api_v1/openapi.json"
CLI="npx -y @scalar/cli@latest"

: "${SCALAR_TOKEN:?Please export SCALAR_TOKEN first}"

command -v curl >/dev/null || { echo "curl not found"; exit 1; }
command -v jq   >/dev/null || { echo "jq not found"; exit 1; }

export SCALAR_TELEMETRY_DISABLED=1
$CLI auth logout >/dev/null 2>&1 || true
$CLI auth login --token "$SCALAR_TOKEN" >/dev/null

$CLI document validate "$SPEC_URL"

RAW_VER="$(curl -fsSL "$SPEC_URL" | jq -r '.info.version // empty')"
VER="${RAW_VER#v}"; VER="${VER%%-*}"; VER="${VER%%+*}"
VER="$(echo "$VER" | sed -E 's/[^0-9.].*$//')"
[[ "$VER" =~ ^[0-9]+\.[0-9]+$ ]] && VER="${VER}.0"
if [[ ! "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Could not normalize info.version ('$RAW_VER') to semver."
  exit 1
fi

OUT=$($CLI registry publish "$SPEC_URL" \
  --namespace "$NAMESPACE" \
  --slug "$SLUG" \
  --version "$VER" \
  --force 2>&1) || { echo "$OUT"; exit 1; }

echo "$OUT"
echo "Published version: v$VER"
echo "Public URL (latest): https://scalar.com/@$NAMESPACE/apis/$SLUG"
echo "Version URL:        https://registry.scalar.com/@$NAMESPACE/apis/$SLUG/$VER"
