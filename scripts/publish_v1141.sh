#!/usr/bin/env bash
# One-shot publish for DRS Video v1.14.1
# Usage: scripts/publish_v1141.sh <github_token>
# Token is passed as an argument, used only in one-shot URLs/headers, NEVER persisted to disk or git config.
set -euo pipefail

TOKEN="${1:?usage: publish_v1141.sh <token>}"
REPO="CTO-DRS/DRS-Video"
TAG="v1.14.1"
REPO_DIR="/home/z/my-project/drs_video_latest"
DL="/home/z/my-project/download"
SCRIPT_DIR="${REPO_DIR}/scripts"

echo "== 1/3 pushing main + tag ${TAG} =="
git -C "${REPO_DIR}" push "https://x-access-token:${TOKEN}@github.com/${REPO}.git" main 2>&1 | sed 's|x-access-token:[^@]*|x-access-token:***|g'
git -C "${REPO_DIR}" push "https://x-access-token:${TOKEN}@github.com/${REPO}.git" "${TAG}" 2>&1 | sed 's|x-access-token:[^@]*|x-access-token:***|g'

echo "== 2/3 creating release =="
RELEASE_ID=$(curl -sS -X POST \
  -H "Authorization: token ${TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -H "Content-Type: application/json" \
  -d @"${SCRIPT_DIR}/release_payload_v1141.json" \
  "https://api.github.com/repos/${REPO}/releases" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('id') or ('ERR: '+str(d.get('errors',d.get('message')))))")
echo "release id: ${RELEASE_ID}"
case "${RELEASE_ID}" in ERR*|'') echo "release creation failed"; exit 1;; esac

echo "== 3/3 uploading assets =="
upload_asset() {
  local file="$1" name ct
  name="$(basename "${file}")"
  ct="application/octet-stream"
  case "${name}" in
    *.md5) ct="text/plain" ;;
    *.zip) ct="application/zip" ;;
  esac
  echo "--- ${name}"
  curl -sS -X POST \
    -H "Authorization: token ${TOKEN}" \
    -H "Content-Type: ${ct}" \
    --data-binary "@${file}" \
    "https://uploads.github.com/repos/${REPO}/releases/${RELEASE_ID}/assets?name=${name}" \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print('  uploaded:', d.get('name'), '| state:', d.get('state'), '| size:', d.get('size')) if 'name' in d else print('  ERROR:', d)"
}
upload_asset "${DL}/DRS-Video-v1.14.1-release.apk"
upload_asset "${DL}/DRS-Video-v1.14.1-release.apk.md5"
upload_asset "${DL}/DRS-Video-v1.14.1-source.zip"

echo "== DONE: https://github.com/${REPO}/releases/tag/${TAG} =="
