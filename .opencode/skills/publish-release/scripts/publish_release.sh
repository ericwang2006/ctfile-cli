#!/usr/bin/env bash
# Publish a GitHub Release with the cross-compiled ctfile-cli binaries.
# Creates the tag + release on the target branch and uploads every file in --dist.
set -euo pipefail

REPO="ericwang2006/ctfile-cli"
TARGET="main"
DIST="dist"
TOKEN_FILE="/tmp/opencode/gh_token"
TAG=""
TITLE=""
BODY=""
BODY_FILE=""
DRAFT="false"
PRERELEASE="false"

usage() {
  cat <<'EOF'
Usage: publish_release.sh --tag <tag> [options]

  --tag <tag>          Release tag, e.g. v26.11.05 (required)
  --title <title>      Release title (default: "ctfile-cli <tag>")
  --body <text>        Release notes body
  --body-file <file>   Read release notes from a file (overrides --body)
  --repo <owner/name>  GitHub repo (default: ericwang2006/ctfile-cli)
  --target <ref>       Target branch/commit for the tag (default: main)
  --dist <dir>         Directory with assets to upload (default: dist)
  --token-file <file>  File containing the token (default: /tmp/opencode/gh_token)
  --draft              Create as draft
  --prerelease         Mark as prerelease
  -h, --help           Show this help

Token resolution: $GITHUB_TOKEN, else the --token-file contents.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --tag)        TAG="${2:-}"; shift 2;;
    --title)      TITLE="${2:-}"; shift 2;;
    --body)       BODY="${2:-}"; shift 2;;
    --body-file)  BODY_FILE="${2:-}"; shift 2;;
    --repo)       REPO="${2:-}"; shift 2;;
    --target)     TARGET="${2:-}"; shift 2;;
    --dist)       DIST="${2:-}"; shift 2;;
    --token-file) TOKEN_FILE="${2:-}"; shift 2;;
    --draft)      DRAFT="true"; shift;;
    --prerelease) PRERELEASE="true"; shift;;
    -h|--help)    usage; exit 0;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2;;
  esac
done

[ -n "$TAG" ] || { echo "error: --tag is required" >&2; usage >&2; exit 2; }
[ -d "$DIST" ] || { echo "error: asset directory not found: $DIST (run ./build.sh first)" >&2; exit 2; }

TOKEN="${GITHUB_TOKEN:-}"
if [ -z "$TOKEN" ] && [ -f "$TOKEN_FILE" ]; then
  TOKEN="$(cat "$TOKEN_FILE")"
fi
[ -n "$TOKEN" ] || { echo "error: no token; set GITHUB_TOKEN or write $TOKEN_FILE" >&2; exit 2; }

TITLE="${TITLE:-ctfile-cli $TAG}"
if [ -n "$BODY_FILE" ]; then
  BODY="$(cat "$BODY_FILE")"
elif [ -z "$BODY" ]; then
  BODY="$(git log -1 --pretty=%s 2>/dev/null || true)"
fi

API="https://api.github.com/repos/$REPO"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

json_get() {
  python3 -c 'import sys,json;d=json.load(sys.stdin);v=d.get(sys.argv[1]);print("" if v is None else v)' "$1"
}

echo "==> Verifying token"
code="$(curl -s -o "$TMP/user.json" -w '%{http_code}' -H "Authorization: Bearer $TOKEN" https://api.github.com/user)"
if [ "$code" != "200" ]; then
  echo "error: token check failed (HTTP $code): $(json_get message < "$TMP/user.json")" >&2
  exit 1
fi
echo "    authenticated as $(json_get login < "$TMP/user.json")"

echo "==> Checking for existing release $TAG"
code="$(curl -s -o "$TMP/existing.json" -w '%{http_code}' -H "Authorization: Bearer $TOKEN" "$API/releases/tags/$TAG")"
if [ "$code" = "200" ]; then
  echo "error: release $TAG already exists: $(json_get html_url < "$TMP/existing.json")" >&2
  exit 1
fi

echo "==> Creating release $TAG (target: $TARGET)"
payload="$(python3 - "$TAG" "$TITLE" "$TARGET" "$BODY" "$DRAFT" "$PRERELEASE" <<'PY'
import json, sys
tag, title, target, body, draft, prerelease = sys.argv[1:7]
print(json.dumps({
    "tag_name": tag,
    "target_commitish": target,
    "name": title,
    "body": body,
    "draft": draft == "true",
    "prerelease": prerelease == "true",
}))
PY
)"
code="$(curl -s -o "$TMP/release.json" -w '%{http_code}' -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "$API/releases" -d "$payload")"
if [ "$code" != "201" ]; then
  echo "error: failed to create release (HTTP $code): $(json_get message < "$TMP/release.json")" >&2
  exit 1
fi
rel_id="$(json_get id < "$TMP/release.json")"
rel_url="$(json_get html_url < "$TMP/release.json")"
echo "    $rel_url"

UP="https://uploads.github.com/repos/$REPO/releases/$rel_id/assets"
echo "==> Uploading assets from $DIST"
count=0
for f in "$DIST"/*; do
  [ -f "$f" ] || continue
  n="$(basename "$f")"
  case "$n" in
    *.tar.gz) ct="application/x-gzip";;
    *.zip)    ct="application/zip";;
    *)        ct="application/octet-stream";;
  esac
  code="$(curl -s -o "$TMP/asset.json" -w '%{http_code}' -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: $ct" \
    --data-binary @"$f" \
    "$UP?name=$n")"
  if [ "$code" = "201" ]; then
    echo "    [ok] $n"
    count=$((count + 1))
  else
    echo "    [fail] $n (HTTP $code): $(json_get message < "$TMP/asset.json")" >&2
  fi
done

echo "==> Done: $count asset(s) uploaded"
echo "    Release: $rel_url"
[ "$count" -gt 0 ] || exit 1
