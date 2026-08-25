#!/usr/bin/env bash
# Stamps this project's identity onto a staged module tree, and optionally
# writes the update manifest the installed module polls.
#
# Why this is a build step instead of a committed patch: every upstream release
# rewrites src/module.prop and version.json to bump the version. Those are
# exactly the fields this project wants to change, so carrying them as a diff
# means a conflict every time anything is picked up from twoone-3. Leaving both
# files byte-identical to upstream in git and rewriting them here keeps merges
# clean.
#
# Usage: ./brand.sh <staging-dir> [version] [manifest-out]
#   AGH_VERSION=v0.107.x  records which AdGuardHome build went into the zip

set -euo pipefail

STAGING="${1:?usage: brand.sh <staging-dir> [version] [manifest-out]}"
VERSION="${2:-$(date -u +%Y%m%d)}"
MANIFEST_OUT="${3:-}"
AGH_VERSION="${AGH_VERSION:-}"

MODULE_NAME="AdGuardHome for Root (Aliyerki)"
MODULE_AUTHOR="twoone3, Aliyerki"
REPO="Aliyerki/AdGuardHomeRoot"
# Served raw rather than through /releases/latest/download so the root manager
# gets a plain 200 instead of a redirect. Named update.json rather than
# version.json so that picking changes up from twoone-3 never touches it.
MANIFEST_URL="https://raw.githubusercontent.com/$REPO/main/update.json"

if [[ ! "$VERSION" =~ ^[0-9]{8}$ ]]; then
  echo "Version must be an 8-digit date (YYYYMMDD), got: $VERSION" >&2
  exit 1
fi

# The date doubles as the versionCode: it only has to be monotonic, and only
# this project's own releases are ever compared against it, so upstream
# renumbering (52, 53, ...) can never collide with it.
VERSION_CODE="$VERSION"

PROP="$STAGING/module.prop"
[ -f "$PROP" ] || { echo "No module.prop in $STAGING" >&2; exit 1; }

sed -i \
  -e "s|^name=.*|name=$MODULE_NAME|" \
  -e "s|^version=.*|version=$VERSION|" \
  -e "s|^versionCode=.*|versionCode=$VERSION_CODE|" \
  -e "s|^author=.*|author=$MODULE_AUTHOR|" \
  -e "s|^updateJson=.*|updateJson=$MANIFEST_URL|" \
  "$PROP"

# An unbranded build would keep pulling updates from upstream, so fail loudly if
# any key was missing from module.prop rather than shipping it absent-mindedly.
for key in name version versionCode author updateJson; do
  grep -q "^$key=" "$PROP" || { echo "module.prop has no $key= line" >&2; exit 1; }
done

echo "==> Branded $PROP as $MODULE_NAME $VERSION"

if [ -n "$MANIFEST_OUT" ]; then
  # adguardHome is what the daily job compares against to decide whether a new
  # AdGuardHome release is worth cutting a build for.
  cat >"$MANIFEST_OUT" <<JSON
{
  "versionCode": $VERSION_CODE,
  "version": "$VERSION",
  "zipUrl": "https://github.com/$REPO/releases/download/$VERSION/AdGuardHomeForRoot_arm64.zip",
  "changelog": "https://raw.githubusercontent.com/$REPO/main/changelog.md",
  "adguardHome": "$AGH_VERSION"
}
JSON
  echo "==> Wrote $MANIFEST_OUT (AdGuardHome: ${AGH_VERSION:-unrecorded})"
fi
