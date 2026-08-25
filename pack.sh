#!/usr/bin/env bash
# Linux equivalent of pack.ps1: fetch the AdGuardHome binary and build the
# flashable module zip.
#
# Usage: ./pack.sh [arm64|armv7] [version]   (default: arm64, today's date)
#
# Passing a version also refreshes update.json, which is what the module
# checks for updates. Leave it off for throwaway test builds.

set -euo pipefail

ARCH="${1:-arm64}"
VERSION="${2:-}"
case "$ARCH" in
arm64 | armv7) ;;
*)
  echo "Unsupported arch: $ARCH (expected arm64 or armv7)" >&2
  exit 1
  ;;
esac

cd "$(dirname "$0")"

CACHE_DIR="cache"
ARCHIVE="$CACHE_DIR/AdGuardHome_linux_$ARCH.tar.gz"
URL="https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_$ARCH.tar.gz"
OUT="AdGuardHomeForRoot_$ARCH.zip"

mkdir -p "$CACHE_DIR"

if [ ! -f "$ARCHIVE" ]; then
  echo "==> Downloading AdGuardHome ($ARCH)"
  curl -fL "$URL" -o "$ARCHIVE"
else
  echo "==> Using cached $ARCHIVE"
fi

if [ ! -d "$CACHE_DIR/$ARCH" ]; then
  echo "==> Extracting"
  mkdir -p "$CACHE_DIR/$ARCH"
  tar -xzf "$ARCHIVE" -C "$CACHE_DIR/$ARCH"
fi

echo "==> Staging module files"
rm -rf staging
mkdir -p staging
cp -a src/. staging/
cp "$CACHE_DIR/$ARCH/AdGuardHome/AdGuardHome" staging/bin/AdGuardHome

if [ -n "$VERSION" ]; then
  ./brand.sh staging "$VERSION" update.json
else
  ./brand.sh staging
fi

echo "==> Building $OUT"
rm -f "$OUT"
if command -v zip >/dev/null 2>&1; then
  (cd staging && zip -qr "../$OUT" .)
else
  # zip(1) is not installed everywhere; python3 is. Mode bits are carried over
  # so the shell scripts stay executable, though customize.sh chmods them anyway.
  echo "    (zip not found, using python3)"
  python3 - "$OUT" staging <<'PY'
import os, sys, zipfile

out, root = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for dirpath, _, filenames in os.walk(root):
        for name in sorted(filenames):
            full = os.path.join(dirpath, name)
            info = zipfile.ZipInfo(os.path.relpath(full, root))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (os.stat(full).st_mode & 0xFFFF) << 16
            with open(full, "rb") as f:
                z.writestr(info, f.read())
PY
fi
rm -rf staging

echo "==> Built $OUT ($(du -h "$OUT" | cut -f1))"
