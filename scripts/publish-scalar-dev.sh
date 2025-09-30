#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="diversifi-0qxwn"
SLUG="dev"
SPEC_URL="https://dev.diversifi.ai/api_v1/openapi.json"

: "${SCALAR_TOKEN:?Please export SCALAR_TOKEN first}"

command -v scalar >/dev/null || { echo "scalar CLI not found"; exit 1; }
command -v curl   >/dev/null || { echo "curl not found"; exit 1; }
command -v jq     >/dev/null || { echo "jq not found"; exit 1; }

scalar auth login --token "$SCALAR_TOKEN" >/dev/null

scalar document validate "$SPEC_URL"

RAW_VER="$(curl -fsSL "$SPEC_URL" | jq -r '.info.version // empty')"
VER="${RAW_VER#v}"
VER="${VER%%-*}"
VER="${VER%%+*}"
if [[ "$VER" =~ ^[0-9]+\.[0-9]+$ ]]; then VER="${VER}.0"; fi
if [[ ! "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  MAJ=9999
  MIN="$(date -u +'%Y%m%d')"
  PAT="$(date -u +'%H%M%S')"
  VER="${MAJ}.${MIN}.${PAT}"
fi

attempt_publish () {
  scalar registry publish "$SPEC_URL" --namespace "$NAMESPACE" --slug "$SLUG" --version "$1"
}

TRIES=0
MAX=50
while [ $TRIES -lt $MAX ]; do
  if attempt_publish "$VER"; then
    echo "Published version: v$VER"
    echo "URL: https://scalar.com/registry/$NAMESPACE/$SLUG"
    exit 0
  fi
  IFS='.' read -r MAJ MIN PAT <<<"$VER"
  : "${MAJ:=0}" ; : "${MIN:=0}" ; : "${PAT:=0}"
  PAT=$((PAT+1))
  VER="${MAJ}.${MIN}.${PAT}"
  TRIES=$((TRIES+1))
done

echo "Failed to publish after $MAX attempts."
exit 1
