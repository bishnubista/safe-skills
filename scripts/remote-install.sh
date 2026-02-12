#!/usr/bin/env bash
set -euo pipefail

# Remote installer — download, verify, install, clean up.
# Usage:
#   1) Download this script from an immutable ref (tag or commit SHA)
#   2) Run with:
#      bash remote-install.sh --ref <immutable-ref> --archive-sha256 <sha256> -- --codex

REPO_HTTPS="https://github.com/bishnubista/safe-skills"
REF="${SAFE_SKILLS_REF:-}"
ARCHIVE_SHA256="${SAFE_SKILLS_ARCHIVE_SHA256:-}"
ALLOW_MUTABLE_REF=0
ALLOW_UNVERIFIED_ARCHIVE=0
INSTALL_ARGS=()

usage() {
  cat <<'USAGE'
Usage: bash scripts/remote-install.sh [options] -- [install.sh options]

Required options:
  --ref <immutable-ref>             Git tag or commit SHA to install
  --archive-sha256 <hex>            Expected SHA-256 of https://github.com/.../archive/<ref>.tar.gz

Optional (unsafe; for local dev only):
  --allow-mutable-ref               Allow mutable refs like main/master/HEAD
  --allow-unverified-archive        Skip archive SHA-256 verification

Environment variable equivalents:
  SAFE_SKILLS_REF
  SAFE_SKILLS_ARCHIVE_SHA256

Examples:
  bash remote-install.sh \
    --ref v0.1.0 \
    --archive-sha256 <sha256-from-signed-release-metadata> \
    -- --codex --force
USAGE
}

require_option_value() {
  local option="$1"
  local value="${2:-}"
  if [[ -z "$value" || "$value" == --* ]]; then
    echo "ERROR: $option requires a value" >&2
    usage
    exit 2
  fi
}

is_mutable_ref() {
  case "$1" in
    main|master|HEAD|latest|refs/heads/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

hash_file() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  else
    openssl dgst -sha256 "$path" | awk '{print $2}'
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref)
      shift
      require_option_value "--ref" "${1:-}"
      REF="$1"
      ;;
    --archive-sha256)
      shift
      require_option_value "--archive-sha256" "${1:-}"
      ARCHIVE_SHA256="$1"
      ;;
    --allow-mutable-ref)
      ALLOW_MUTABLE_REF=1
      ;;
    --allow-unverified-archive)
      ALLOW_UNVERIFIED_ARCHIVE=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      INSTALL_ARGS+=("$@")
      break
      ;;
    *)
      INSTALL_ARGS+=("$1")
      ;;
  esac
  shift
done

if [[ -z "$REF" ]]; then
  echo "ERROR: --ref is required (or set SAFE_SKILLS_REF)." >&2
  usage
  exit 2
fi

if [[ ! "$REF" =~ ^[A-Za-z0-9._/-]+$ ]]; then
  echo "ERROR: invalid ref '$REF'" >&2
  exit 2
fi

if is_mutable_ref "$REF" && [[ "$ALLOW_MUTABLE_REF" -ne 1 ]]; then
  echo "ERROR: '$REF' is mutable. Use an immutable tag/commit or pass --allow-mutable-ref (unsafe)." >&2
  exit 2
fi

if [[ -z "$ARCHIVE_SHA256" && "$ALLOW_UNVERIFIED_ARCHIVE" -ne 1 ]]; then
  echo "ERROR: --archive-sha256 is required unless --allow-unverified-archive is set." >&2
  exit 2
fi

if [[ -n "$ARCHIVE_SHA256" && ! "$ARCHIVE_SHA256" =~ ^[A-Fa-f0-9]{64}$ ]]; then
  echo "ERROR: --archive-sha256 must be a 64-character hex digest." >&2
  exit 2
fi

TMP_DIR="$(mktemp -d)"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

ARCHIVE_URL="$REPO_HTTPS/archive/$REF.tar.gz"
ARCHIVE_FILE="$TMP_DIR/safe-skills.tar.gz"

echo "Downloading safe-skills archive for ref: $REF"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$ARCHIVE_URL" -o "$ARCHIVE_FILE"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$ARCHIVE_FILE" "$ARCHIVE_URL"
else
  echo "ERROR: need curl or wget to download safe-skills" >&2
  exit 1
fi

if [[ -n "$ARCHIVE_SHA256" ]]; then
  expected="$(printf '%s' "$ARCHIVE_SHA256" | tr '[:upper:]' '[:lower:]')"
  actual="$(hash_file "$ARCHIVE_FILE")"
  if [[ "$actual" != "$expected" ]]; then
    echo "ERROR: archive checksum mismatch for ref '$REF'" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    exit 1
  fi
  echo "Archive checksum verified."
else
  echo "WARNING: archive checksum verification skipped (--allow-unverified-archive)." >&2
fi

tar -xzf "$ARCHIVE_FILE" -C "$TMP_DIR"
SOURCE_DIR="$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d -name 'safe-skills-*' | head -n 1)"
if [[ -z "$SOURCE_DIR" ]]; then
  echo "ERROR: extracted source directory not found" >&2
  exit 1
fi

cd "$SOURCE_DIR"
bash ./scripts/install.sh "${INSTALL_ARGS[@]}"
