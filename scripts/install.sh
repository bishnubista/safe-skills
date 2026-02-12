#!/usr/bin/env bash
set -euo pipefail

# Cross-agent installer for llm-vulnerability-scan.
# Installs first-class adapters per platform docs:
# - Claude Code: SKILL.md skill bundle
# - Codex: SKILL.md + agents/openai.yaml skill bundle
# - Cursor: rule file

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CHECKSUMS_FILE="$PLUGIN_DIR/CHECKSUMS.sha256"

CLAUDE_SKILL_DIR="$PLUGIN_DIR/skills/claude-code/llm-vulnerability-scan"
CODEX_SKILL_DIR="$PLUGIN_DIR/skills/codex/llm-vulnerability-scan"
CURSOR_RULE_SOURCE="$PLUGIN_DIR/skills/cursor/llm-vulnerability-scan/security-scan.md"

MODE="copy"
VERIFY_CHECKSUMS=1
INSTALL_REPO_MODE="prompt"
FORCE_REINSTALL=0
AUDIT_LOG="${SAFE_SKILLS_AUDIT_LOG:-$HOME/.safe-skills-install.log}"

INSTALL_CLAUDE=0
INSTALL_CURSOR=0
INSTALL_CODEX=0
PLATFORM_SPECIFIED=0

usage() {
  cat <<USAGE
Usage: ./scripts/install.sh [options]

Platform options (pick one or more; omit for interactive chooser):
  --claude               Install Claude Code adapter (~/.claude/skills)
  --cursor               Install Cursor adapter (~/.cursor/rules)
  --codex                Install Codex adapter (~/.agents/skills)
  --all                  Install all adapters

Other options:
  --copy                 Install immutable copy mode (default)
  --symlink              Install live symlink mode (development)
  --no-verify            Skip CHECKSUMS.sha256 verification (symlink mode only)
  --include-repo         Also install Codex adapter to current repo (.agents/skills)
  --skip-repo            Do not install Codex adapter to current repo
  --force                Replace existing install path
  --audit-log <path>     Write install audit lines to this path
  -h, --help             Show this help

Examples:
  ./scripts/install.sh --claude
  ./scripts/install.sh --cursor --codex
  ./scripts/install.sh --all --force
USAGE
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

compute_tree_hash() {
  local dir="$1"
  local tmp
  tmp="$(mktemp)"

  (
    cd "$dir"
    find . -type f | sort | while read -r rel; do
      printf '%s  %s\n' "$(hash_file "$dir/$rel")" "$rel"
    done
  ) > "$tmp"

  local tree_hash
  tree_hash="$(hash_file "$tmp")"
  rm -f "$tmp"
  printf '%s' "$tree_hash"
}

verify_checksums() {
  if [[ "$VERIFY_CHECKSUMS" -eq 0 ]]; then
    echo "Skipping checksum verification (--no-verify)."
    return 0
  fi

  if [[ ! -f "$CHECKSUMS_FILE" ]]; then
    echo "ERROR: checksum manifest missing: $CHECKSUMS_FILE"
    echo "Refusing to install without checksum verification."
    exit 1
  fi

  echo "Verifying release checksums..."
  (
    cd "$PLUGIN_DIR"
    if command -v sha256sum >/dev/null 2>&1; then
      sha256sum -c CHECKSUMS.sha256
    elif command -v shasum >/dev/null 2>&1; then
      shasum -a 256 -c CHECKSUMS.sha256
    else
      echo "ERROR: need sha256sum, shasum, or openssl to verify checksums"
      exit 1
    fi
  )
}

log_install() {
  local agent_name="$1"
  local target_path="$2"
  local status="$3"
  local source_hash="$4"
  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  mkdir -p "$(dirname "$AUDIT_LOG")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$ts" "$status" "$agent_name" "$MODE" "$target_path" "$source_hash" >> "$AUDIT_LOG"
}

install_skill_dir() {
  local source_dir="$1"
  local target_dir="$2"
  local agent_name="$3"
  local install_path="$target_dir/llm-vulnerability-scan"
  local source_hash

  source_hash="$(compute_tree_hash "$source_dir")"
  mkdir -p "$target_dir"

  if [[ -L "$install_path" || -e "$install_path" ]]; then
    if [[ "$FORCE_REINSTALL" -eq 1 ]]; then
      rm -rf -- "$install_path"
      log_install "$agent_name" "$install_path" "replaced-existing" "$source_hash"
    else
      echo "  [$agent_name] Already present at $install_path (skipping)"
      log_install "$agent_name" "$install_path" "skipped-existing" "$source_hash"
      return 0
    fi
  fi

  if [[ "$MODE" == "symlink" ]]; then
    ln -s "$source_dir" "$install_path"
  else
    cp -R "$source_dir" "$install_path"
  fi

  echo "  [$agent_name] Installed -> $install_path ($MODE)"
  log_install "$agent_name" "$install_path" "installed" "$source_hash"
}

install_cursor_rule() {
  local target_dir="$1"
  local target_path="$target_dir/safe-skills-security-scan.md"
  local source_hash

  source_hash="$(hash_file "$CURSOR_RULE_SOURCE")"
  mkdir -p "$target_dir"

  if [[ -L "$target_path" || -e "$target_path" ]]; then
    if [[ "$FORCE_REINSTALL" -eq 1 ]]; then
      rm -rf -- "$target_path"
      log_install "Cursor" "$target_path" "replaced-existing" "$source_hash"
    else
      echo "  [Cursor] Already present at $target_path (skipping)"
      log_install "Cursor" "$target_path" "skipped-existing" "$source_hash"
      return 0
    fi
  fi

  if [[ "$MODE" == "symlink" ]]; then
    ln -s "$CURSOR_RULE_SOURCE" "$target_path"
  else
    cp "$CURSOR_RULE_SOURCE" "$target_path"
  fi

  echo "  [Cursor] Installed -> $target_path ($MODE)"
  log_install "Cursor" "$target_path" "installed" "$source_hash"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --claude)
      INSTALL_CLAUDE=1
      PLATFORM_SPECIFIED=1
      ;;
    --cursor)
      INSTALL_CURSOR=1
      PLATFORM_SPECIFIED=1
      ;;
    --codex)
      INSTALL_CODEX=1
      PLATFORM_SPECIFIED=1
      ;;
    --all)
      INSTALL_CLAUDE=1
      INSTALL_CURSOR=1
      INSTALL_CODEX=1
      PLATFORM_SPECIFIED=1
      ;;
    --copy)
      MODE="copy"
      ;;
    --symlink)
      MODE="symlink"
      ;;
    --no-verify)
      VERIFY_CHECKSUMS=0
      ;;
    --include-repo)
      INSTALL_REPO_MODE="yes"
      ;;
    --skip-repo)
      INSTALL_REPO_MODE="no"
      ;;
    --force)
      FORCE_REINSTALL=1
      ;;
    --audit-log)
      shift
      if [[ $# -eq 0 ]]; then
        echo "ERROR: --audit-log requires a path"
        exit 2
      fi
      AUDIT_LOG="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown option: $1"
      usage
      exit 2
      ;;
  esac
  shift
done

echo "=== LLM Vulnerability Scan — Cross-Agent Installer ==="
echo

required_files=(
  "$CLAUDE_SKILL_DIR/SKILL.md"
  "$CLAUDE_SKILL_DIR/references/safe-t-checklist.md"
  "$CLAUDE_SKILL_DIR/references/owasp-llm-checklist.md"
  "$CLAUDE_SKILL_DIR/references/agentic-controls.md"
  "$CODEX_SKILL_DIR/SKILL.md"
  "$CODEX_SKILL_DIR/agents/openai.yaml"
  "$CODEX_SKILL_DIR/references/safe-t-checklist.md"
  "$CODEX_SKILL_DIR/references/owasp-llm-checklist.md"
  "$CODEX_SKILL_DIR/references/agentic-controls.md"
  "$CURSOR_RULE_SOURCE"
)

for path in "${required_files[@]}"; do
  if [[ ! -f "$path" ]]; then
    echo "ERROR: required file missing: $path"
    exit 1
  fi
done

if [[ "$MODE" == "copy" && "$VERIFY_CHECKSUMS" -eq 0 ]]; then
  echo "ERROR: --no-verify is only allowed with --symlink development mode"
  exit 2
fi

verify_checksums

echo "Install mode: $MODE"
echo "Audit log: $AUDIT_LOG"
echo

if [[ "$PLATFORM_SPECIFIED" -eq 0 ]]; then
  if [[ -t 0 ]]; then
    echo "Which platforms do you want to install for?"
    echo
    echo "  1) Claude Code  (~/.claude/skills)"
    echo "  2) Cursor       (~/.cursor/rules)"
    echo "  3) Codex        (~/.agents/skills)"
    echo "  4) All of the above"
    echo
    read -rp "Enter choices (comma-separated, e.g. 1,2): " choices
    IFS=',' read -r -a selected_choices <<< "$choices"
    for raw_choice in "${selected_choices[@]}"; do
      choice="$(printf '%s' "$raw_choice" | tr -d '[:space:]')"
      [[ -z "$choice" ]] && continue
      case "$choice" in
        1) INSTALL_CLAUDE=1 ;;
        2) INSTALL_CURSOR=1 ;;
        3) INSTALL_CODEX=1 ;;
        4) INSTALL_CLAUDE=1; INSTALL_CURSOR=1; INSTALL_CODEX=1 ;;
        *) echo "WARNING: ignoring unknown choice '$choice'" ;;
      esac
    done
    if [[ "$INSTALL_CLAUDE" -eq 0 && "$INSTALL_CURSOR" -eq 0 && "$INSTALL_CODEX" -eq 0 ]]; then
      echo "ERROR: no platforms selected"
      exit 2
    fi
  else
    INSTALL_CLAUDE=1
    INSTALL_CURSOR=1
    INSTALL_CODEX=1
  fi
fi

echo "Installing selected adapters..."
echo

[[ "$INSTALL_CLAUDE" -eq 1 ]] && install_skill_dir "$CLAUDE_SKILL_DIR" "$HOME/.claude/skills" "Claude Code"
[[ "$INSTALL_CURSOR" -eq 1 ]] && install_cursor_rule "$HOME/.cursor/rules"
[[ "$INSTALL_CODEX" -eq 1 ]] && install_skill_dir "$CODEX_SKILL_DIR" "$HOME/.agents/skills" "Codex"

if [[ "$INSTALL_CODEX" -eq 1 ]]; then
  echo
  if [[ "$INSTALL_REPO_MODE" == "yes" ]]; then
    install_skill_dir "$CODEX_SKILL_DIR" ".agents/skills" "Repo-level Codex"
  elif [[ "$INSTALL_REPO_MODE" == "prompt" && -t 0 ]]; then
    read -rp "Also install Codex adapter to current repo (.agents/skills/)? [y/N] " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
      install_skill_dir "$CODEX_SKILL_DIR" ".agents/skills" "Repo-level Codex"
    fi
  elif [[ "$INSTALL_REPO_MODE" == "prompt" ]]; then
    echo "Skipping repo-level Codex install (non-interactive shell)."
  fi
fi

echo
echo "Done. Installed adapters:"
[[ "$INSTALL_CLAUDE" -eq 1 ]] && echo "  Claude Code skill: ~/.claude/skills/llm-vulnerability-scan"
[[ "$INSTALL_CURSOR" -eq 1 ]] && echo "  Cursor rule:       ~/.cursor/rules/safe-skills-security-scan.md"
[[ "$INSTALL_CODEX" -eq 1 ]] && echo "  Codex skill:       ~/.agents/skills/llm-vulnerability-scan"
