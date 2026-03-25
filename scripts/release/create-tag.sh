#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  create-tag.sh mobile <prod|test> [--bump <patch|minor|major>] [--version <x.y.z>] [--remote <name>] [--source-repo <owner/repo>] [--source-ref <ref>] [--source-sha <sha>] [--dry-run]
  create-tag.sh server [--bump <patch|minor|major>] [--version <x.y.z>] [--remote <name>] [--source-repo <owner/repo>] [--source-ref <ref>] [--source-sha <sha>] [--dry-run]

Examples:
  ./scripts/release/create-tag.sh mobile prod
  ./scripts/release/create-tag.sh mobile test --bump minor
  ./scripts/release/create-tag.sh server --source-ref refs/heads/main
EOF
}

validate_version() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

bump_version() {
  local version="$1"
  local bump_type="$2"
  local major minor patch

  IFS='.' read -r major minor patch <<<"$version"

  case "$bump_type" in
    patch)
      patch=$((patch + 1))
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
    *)
      echo "Unsupported bump type: $bump_type" >&2
      exit 1
      ;;
  esac

  printf '%s.%s.%s\n' "$major" "$minor" "$patch"
}

latest_version_for_pattern() {
  local tag_pattern="$1"
  local mode="$2"

  git tag --list "$tag_pattern" \
    | awk -v mode="$mode" '
        mode == "server" && $0 ~ /^v[0-9]+\.[0-9]+\.[0-9]+$/ {
          sub(/^v/, "", $0)
          print
        }
        mode == "mobile" && $0 ~ /^mobile-(prod|test)-[0-9]+\.[0-9]+\.[0-9]+$/ {
          sub(/^mobile-(prod|test)-/, "", $0)
          print
        }
        mode == "mobile" && $0 ~ /^mobile-[0-9]+\.[0-9]+\.[0-9]+$/ {
          sub(/^mobile-/, "", $0)
          print
        }
      ' \
    | sort -V \
    | tail -n 1
}

normalize_source_ref() {
  local ref="$1"
  if [[ "$ref" == refs/* ]]; then
    printf '%s\n' "$ref"
    return
  fi
  printf 'refs/heads/%s\n' "$ref"
}

resolve_source_sha() {
  local source_repo="$1"
  local source_ref="$2"
  local source_url="git@github.com:${source_repo}.git"
  local resolved

  resolved="$(git ls-remote "$source_url" "$source_ref" | awk 'NR == 1 { print $1 }')"
  if [[ -z "$resolved" ]]; then
    echo "Unable to resolve $source_ref from $source_repo" >&2
    exit 1
  fi

  printf '%s\n' "$resolved"
}

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  usage
  exit 1
fi
shift

CHANNEL=""
BUMP_TYPE="patch"
EXPLICIT_VERSION=""
REMOTE="origin"
SOURCE_REPO="askchance/aibot"
SOURCE_REF="refs/heads/main"
SOURCE_SHA=""
DRY_RUN="false"

case "$TARGET" in
  mobile)
    CHANNEL="${1:-}"
    if [[ "$CHANNEL" != "prod" && "$CHANNEL" != "test" ]]; then
      echo "mobile target requires channel prod or test" >&2
      usage
      exit 1
    fi
    shift
    TAG_PREFIX="mobile-${CHANNEL}-"
    TAG_PATTERN="mobile-*"
    VERSION_MODE="mobile"
    ;;
  server)
    TAG_PREFIX="v"
    TAG_PATTERN="v*"
    VERSION_MODE="server"
    ;;
  *)
    echo "Unsupported target: $TARGET" >&2
    usage
    exit 1
    ;;
esac

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bump)
      BUMP_TYPE="${2:-}"
      shift 2
      ;;
    --version)
      EXPLICIT_VERSION="${2:-}"
      shift 2
      ;;
    --remote)
      REMOTE="${2:-}"
      shift 2
      ;;
    --source-repo)
      SOURCE_REPO="${2:-}"
      shift 2
      ;;
    --source-ref)
      SOURCE_REF="${2:-}"
      shift 2
      ;;
    --source-sha)
      SOURCE_SHA="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -n "$EXPLICIT_VERSION" ]] && ! validate_version "$EXPLICIT_VERSION"; then
  echo "Version must match x.y.z using numeric segments" >&2
  exit 1
fi

if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
  echo "Git remote not found: $REMOTE" >&2
  exit 1
fi

SOURCE_REF="$(normalize_source_ref "$SOURCE_REF")"

git fetch "$REMOTE" --tags --force

LATEST_VERSION="$(latest_version_for_pattern "$TAG_PATTERN" "$VERSION_MODE")"
if [[ -z "$LATEST_VERSION" ]]; then
  LATEST_VERSION="0.0.0"
fi

if [[ -n "$EXPLICIT_VERSION" ]]; then
  NEXT_VERSION="$EXPLICIT_VERSION"
else
  NEXT_VERSION="$(bump_version "$LATEST_VERSION" "$BUMP_TYPE")"
fi

if [[ -z "$SOURCE_SHA" ]]; then
  SOURCE_SHA="$(resolve_source_sha "$SOURCE_REPO" "$SOURCE_REF")"
fi

TAG_NAME="${TAG_PREFIX}${NEXT_VERSION}"

if git rev-parse -q --verify "refs/tags/$TAG_NAME" >/dev/null; then
  echo "Tag already exists locally: $TAG_NAME" >&2
  exit 1
fi

if git ls-remote --tags "$REMOTE" "refs/tags/$TAG_NAME" | grep -q .; then
  echo "Tag already exists on $REMOTE: $TAG_NAME" >&2
  exit 1
fi

TAG_MESSAGE=$(
  cat <<EOF
source-repo: $SOURCE_REPO
source-ref: $SOURCE_REF
source-sha: $SOURCE_SHA
EOF
)

echo "Latest version: $LATEST_VERSION"
echo "Next version:   $NEXT_VERSION"
echo "Tag:            $TAG_NAME"
echo "Remote:         $REMOTE"
echo "Source repo:    $SOURCE_REPO"
echo "Source ref:     $SOURCE_REF"
echo "Source sha:     $SOURCE_SHA"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "Dry run only. No tag created."
  exit 0
fi

git tag -a "$TAG_NAME" -m "$TAG_MESSAGE"
git push "$REMOTE" "$TAG_NAME"

if [[ "$TARGET" == "mobile" ]]; then
  echo "Triggered mobile CI for $TAG_NAME"
else
  echo "Triggered server deploy for $TAG_NAME"
fi
