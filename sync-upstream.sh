#!/usr/bin/env bash
# Rebase this project's patches on top of twoone-3/AdGuardHomeForRoot.
#
# This repo carries a small set of local commits on top of upstream main. Keeping
# them as a rebased stack (rather than merging upstream in) keeps the diff
# readable and makes the patches easy to send upstream later.
#
# Usage: ./sync-upstream.sh [--push]

set -euo pipefail

UPSTREAM_URL="https://github.com/twoone-3/AdGuardHomeForRoot.git"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
PUSH=false
[ "${1:-}" = "--push" ] && PUSH=true

cd "$(dirname "$0")"

if ! git remote get-url upstream >/dev/null 2>&1; then
  echo "==> Adding upstream remote"
  git remote add upstream "$UPSTREAM_URL"
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "!! Working tree is dirty. Commit or stash first." >&2
  exit 1
fi

echo "==> Fetching upstream"
git fetch upstream --tags

OLD_BASE="$(git merge-base HEAD upstream/main)"
NEW_HEAD="$(git rev-parse upstream/main)"

if [ "$OLD_BASE" = "$NEW_HEAD" ]; then
  echo "==> Already up to date with upstream/main"
else
  echo "==> Upstream changes since our base:"
  git log --oneline --no-decorate "$OLD_BASE..$NEW_HEAD"
  echo
  echo "==> Our patches being replayed:"
  git log --oneline --no-decorate "$OLD_BASE..HEAD"
  echo
  echo "==> Rebasing $BRANCH onto upstream/main"
  if ! git rebase upstream/main; then
    cat >&2 <<'EOF'

!! Rebase hit a conflict. Upstream touched a file we patch.
   Resolve it, then:  git add <file> && git rebase --continue
   Or abandon with:   git rebase --abort
EOF
    exit 1
  fi
fi

# The AdGuardHome binary is pulled at build time, so a version bump upstream
# only matters for the module metadata we ship.
echo
echo "==> Module version now: $(grep '^version=' src/module.prop | cut -d= -f2)"

if $PUSH; then
  echo "==> Pushing $BRANCH to origin"
  git push --force-with-lease origin "$BRANCH"
else
  echo "==> Done. Review, then: git push --force-with-lease origin $BRANCH"
fi
