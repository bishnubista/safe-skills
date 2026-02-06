#!/usr/bin/env bash
set -euo pipefail

# Remote installer — download, verify, install, clean up.
# Usage: curl -fsSL https://raw.githubusercontent.com/bishnubista/safe-skills/main/scripts/remote-install.sh | bash
# Pass flags: curl ... | bash -s -- --claude --force

REPO_HTTPS="https://github.com/bishnubista/safe-skills"
BRANCH="main"
TMP_DIR="$(mktemp -d)"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

echo "Downloading safe-skills..."

# Try git clone first; fall back to curl+tar if git is unavailable or clone fails.
if command -v git >/dev/null 2>&1 && git clone --depth 1 --branch "$BRANCH" "$REPO_HTTPS.git" "$TMP_DIR/safe-skills" 2>/dev/null; then
  true
elif command -v curl >/dev/null 2>&1; then
  curl -fsSL "$REPO_HTTPS/archive/refs/heads/$BRANCH.tar.gz" | tar -xz -C "$TMP_DIR"
  mv "$TMP_DIR"/safe-skills-* "$TMP_DIR/safe-skills"
elif command -v wget >/dev/null 2>&1; then
  wget -qO- "$REPO_HTTPS/archive/refs/heads/$BRANCH.tar.gz" | tar -xz -C "$TMP_DIR"
  mv "$TMP_DIR"/safe-skills-* "$TMP_DIR/safe-skills"
else
  echo "ERROR: need git, curl, or wget to download safe-skills"
  exit 1
fi

cd "$TMP_DIR/safe-skills"
bash ./scripts/install.sh "$@"
