#!/usr/bin/env bash
set -euo pipefail

# === Config ===
NAMESPACE="${NAMESPACE:-diversifi-0qxwn}"
SLUG="${SLUG:-prod}"
SPEC_URL="${SPEC_URL:-https://platform.diversifi.ai/api_v1/openapi.json}"
S3_BUCKET="${S3_BUCKET:-docs-api-diversifi-ai}"
CLOUDFRONT_DISTRIBUTION_ID="${CLOUDFRONT_DISTRIBUTION_ID:-}"
CLI="npx -y @scalar/cli@latest"

: "${SCALAR_TOKEN:?Please export SCALAR_TOKEN first}"

# === Preflight checks ===
command -v curl >/dev/null || { echo "curl not found"; exit 1; }
command -v jq   >/dev/null || { echo "jq not found"; exit 1; }
command -v aws  >/dev/null || { echo "aws CLI not found"; exit 1; }

# === Scalar CLI auth (no telemetry) ===
export SCALAR_TELEMETRY_DISABLED=1
$CLI auth logout >/dev/null 2>&1 || true
$CLI auth login --token "$SCALAR_TOKEN" >/dev/null

# === Fetch original spec and patch it ===
# Why patch? Ensure UI uses /api_v1 and requires X-API-Key on Try It
TMP_SPEC_ORIG="$(mktemp -t spec-orig.XXXX.json)"
TMP_SPEC_PATCHED="$(mktemp -t spec-patched.XXXX.json)"
trap 'rm -f "$TMP_SPEC_ORIG" "$TMP_SPEC_PATCHED"' EXIT

curl -fsSL "$SPEC_URL" > "$TMP_SPEC_ORIG"

# Patch rules:
# 1) set OpenAPI "servers" to include /api_v1 base
# 2) ensure components.securitySchemes.ApiKeyAuth (header X-API-Key)
# 3) apply global security requirement so Try It sends the header
jq '
  .servers = [
    { "url": "https://platform.diversifi.ai/api_v1" },
    { "url": "https://api.diversifi.ai/api_v1" }
  ]
  |
  (.components //= {}) |
  (.components.securitySchemes //= {}) |
  (.components.securitySchemes.ApiKeyAuth = {
    "type": "apiKey",
    "in": "header",
    "name": "X-API-Key"
  })
  |
  (.security = [ { "ApiKeyAuth": [] } ])
' "$TMP_SPEC_ORIG" > "$TMP_SPEC_PATCHED"

echo "Validating OpenAPI spec (patched)..."
$CLI document validate "$TMP_SPEC_PATCHED"

# === Extract and normalize version from patched spec (semver x.y.z) ===
RAW_VER="$(jq -r '.info.version // empty' "$TMP_SPEC_PATCHED")"
VER="${RAW_VER#v}"
VER="${VER%%-*}"
VER="${VER%%+*}"
VER="$(echo "$VER" | sed -E 's/[^0-9.].*$//')"
[[ "$VER" =~ ^[0-9]+\.[0-9]+$ ]] && VER="${VER}.0"
if [[ ! "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Could not normalize info.version ('$RAW_VER') to semver (x.y.z)."
  exit 1
fi

# === Publish patched spec to Scalar Registry ===
echo "Publishing to Scalar Registry (namespace=$NAMESPACE, slug=$SLUG, version=$VER)..."
OUT=$($CLI registry publish "$TMP_SPEC_PATCHED" \
  --namespace "$NAMESPACE" \
  --slug "$SLUG" \
  --version "$VER" \
  --force 2>&1) || { echo "$OUT"; exit 1; }

echo "$OUT"
echo "Published version: v$VER"
echo "Public (latest): https://scalar.com/@$NAMESPACE/apis/$SLUG"
echo "Exact version  : https://registry.scalar.com/@$NAMESPACE/apis/$SLUG/$VER"

# === Build a minimal static UI page ===
BUILD_DIR="${BUILD_DIR:-./public}"
mkdir -p "$BUILD_DIR"

cat > "${BUILD_DIR}/index.html" <<HTML
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>API Reference</title>
  <meta name="viewport" content="width=device-width, initial-scale=1" />
</head>
<body>
  <div id="app"></div>
  <script src="https://cdn.jsdelivr.net/npm/@scalar/api-reference"></script>
  <script>
    // The UI will primarily honor the "servers" defined in the patched spec.
    // The "url" below is a fallback to load the document itself.
    Scalar.createApiReference('#app', {
      url: '${SPEC_URL}',
      proxyUrl: 'https://proxy.scalar.com'
    })
  </script>
</body>
</html>
HTML

# === Upload to S3 and optionally invalidate CloudFront ===
echo "Uploading static site to s3://${S3_BUCKET}/ ..."
aws s3 cp "${BUILD_DIR}/index.html" "s3://${S3_BUCKET}/index.html" \
  --content-type text/html --cache-control "no-store"

if [[ -n "$CLOUDFRONT_DISTRIBUTION_ID" ]]; then
  echo "Creating CloudFront invalidation on ${CLOUDFRONT_DISTRIBUTION_ID} ..."
  aws cloudfront create-invalidation \
    --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
    --paths '/index.html' >/dev/null
fi

echo "Done."
echo "Prod URL: https://docs.diversifi.ai"

