#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-diversifi-0qxwn}"
SLUG="${SLUG:-dev}"
SPEC_URL="${SPEC_URL:-https://dev.diversifi.ai/api_v1/openapi.json}"
S3_BUCKET="${S3_BUCKET:-docs-api-dev-diversifi-ai}"
CLOUDFRONT_DISTRIBUTION_ID="${CLOUDFRONT_DISTRIBUTION_ID:-}"
CLI="npx -y @scalar/cli@latest"

: "${SCALAR_TOKEN:?Please export SCALAR_TOKEN first}"

command -v curl >/dev/null || { echo "curl not found"; exit 1; }
command -v jq   >/dev/null || { echo "jq not found"; exit 1; }
command -v aws  >/dev/null || { echo "aws CLI not found"; exit 1; }

export SCALAR_TELEMETRY_DISABLED=1
$CLI auth logout >/dev/null 2>&1 || true
$CLI auth login --token "$SCALAR_TOKEN" >/dev/null

echo "Validating OpenAPI spec..."
$CLI document validate "$SPEC_URL"

RAW_VER="$(curl -fsSL "$SPEC_URL" | jq -r '.info.version // empty')"
VER="${RAW_VER#v}"
VER="${VER%%-*}"
VER="${VER%%+*}"
VER="$(echo "$VER" | sed -E 's/[^0-9.].*$//')"
[[ "$VER" =~ ^[0-9]+\.[0-9]+$ ]] && VER="${VER}.0"
if [[ ! "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Could not normalize info.version ('$RAW_VER') to semver (x.y.z)."
  exit 1
fi

echo "Publishing to Scalar Registry (namespace=$NAMESPACE, slug=$SLUG, version=$VER)..."
OUT=$($CLI registry publish "$SPEC_URL" \
  --namespace "$NAMESPACE" \
  --slug "$SLUG" \
  --version "$VER" \
  --force 2>&1) || { echo "$OUT"; exit 1; }

echo "$OUT"
echo "Published version: v$VER"
echo "Public (latest): https://scalar.com/@$NAMESPACE/apis/$SLUG"
echo "Exact version  : https://registry.scalar.com/@$NAMESPACE/apis/$SLUG/$VER"

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
    Scalar.createApiReference('#app', {
      url: '${SPEC_URL}',
      proxyUrl: 'https://proxy.scalar.com'
    })
  </script>
</body>
</html>
HTML

echo "Uploading static site to s3://${S3_BUCKET}/ ..."
aws s3 cp "${BUILD_DIR}/index.html" "s3://${S3_BUCKET}/index.html" --content-type text/html --cache-control "no-store"

if [[ -n "$CLOUDFRONT_DISTRIBUTION_ID" ]]; then
  echo "Creating CloudFront invalidation on ${CLOUDFRONT_DISTRIBUTION_ID} ..."
  aws cloudfront create-invalidation --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" --paths '/index.html' >/dev/null
fi

echo "Done."
echo "DEV URL: https://docs-api-dev.diversifi.ai"
