#!/usr/bin/env bash
set -euo pipefail

DEST_DIR="${1:-aibot-source}"
SOURCE_REPO="${SOURCE_REPO:-askchance/aibot}"
SOURCE_REF="${SOURCE_REF:-refs/heads/main}"
SOURCE_SHA="${SOURCE_SHA:-}"

if [[ -z "${MY_GITHUB_TOKEN:-}" ]]; then
  echo "MY_GITHUB_TOKEN is required" >&2
  exit 1
fi

if [[ -e "$DEST_DIR" ]]; then
  rm -rf "$DEST_DIR"
fi

mkdir -p "$(dirname "$DEST_DIR")"
git init "$DEST_DIR" >/dev/null
cd "$DEST_DIR"

git config advice.detachedHead false
git remote add origin "https://x-access-token:${MY_GITHUB_TOKEN}@github.com/${SOURCE_REPO}.git"

if [[ -n "$SOURCE_SHA" ]]; then
  git fetch --depth 1 origin "$SOURCE_SHA"
  git checkout --detach FETCH_HEAD
else
  git fetch --depth 1 origin "$SOURCE_REF"
  git checkout --detach FETCH_HEAD
fi

echo "Checked out ${SOURCE_REPO} at $(git rev-parse HEAD)"
