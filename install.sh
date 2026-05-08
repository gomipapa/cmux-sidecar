#!/usr/bin/env bash
# cmux-sidecar installer.
# - Copies bin/cmux-sidecar to <bin-prefix>/bin/cmux-sidecar
# - Installs adapter files to global or project scope, per --tool selection
# - Records installed paths in a manifest for accurate uninstall
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BIN_PREFIX="$HOME/.local"
SCOPE="global"
PROJECT_DIR=""
TOOL_LIST="all"
FORCE=0
NO_CLOBBER=0
DRY_RUN=0
INTERACTIVE=1

usage() {
  cat <<'EOF'
Usage: install.sh [options]

Options:
  --bin-prefix=PATH   binary install prefix (default: $HOME/.local)
                      → <prefix>/bin/cmux-sidecar
  --scope=SCOPE       global | project (default: global)
  --project=PATH      target project dir when --scope=project (default: $PWD)
  --tool=LIST         claude-code,codex,all (default: all). comma-separated.
  --force             overwrite without backup
  --no-clobber        skip existing files
  --dry-run           print actions without performing them
  -h, --help          show this help
EOF
}

# Parse args
for arg in "$@"; do
  case "$arg" in
    --bin-prefix=*)  BIN_PREFIX="${arg#*=}"; INTERACTIVE=0 ;;
    --scope=*)       SCOPE="${arg#*=}"; INTERACTIVE=0 ;;
    --project=*)     PROJECT_DIR="${arg#*=}"; INTERACTIVE=0 ;;
    --tool=*)        TOOL_LIST="${arg#*=}"; INTERACTIVE=0 ;;
    --force)         FORCE=1; INTERACTIVE=0 ;;
    --no-clobber)    NO_CLOBBER=1; INTERACTIVE=0 ;;
    --dry-run)       DRY_RUN=1; INTERACTIVE=0 ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "unknown option: $arg" >&2; usage; exit 2 ;;
  esac
done

if (( FORCE && NO_CLOBBER )); then
  echo "--force and --no-clobber are mutually exclusive" >&2
  exit 2
fi

# Interactive prompts (only scope/tool; bin-prefix stays default)
if (( INTERACTIVE )); then
  printf "scope [global/project] (default: global): "
  read -r ans || true
  [[ -n "${ans:-}" ]] && SCOPE="$ans"
  printf "tool [claude-code,codex,all] (default: all): "
  read -r ans || true
  [[ -n "${ans:-}" ]] && TOOL_LIST="$ans"
fi

case "$SCOPE" in
  global) ;;
  project)
    [[ -z "$PROJECT_DIR" ]] && PROJECT_DIR="$PWD"
    PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
    ;;
  *) echo "invalid --scope: $SCOPE (must be global|project)" >&2; exit 2 ;;
esac

# Normalize tool list
declare -a TOOLS=()
IFS=',' read -ra raw_tools <<< "$TOOL_LIST"
for t in "${raw_tools[@]}"; do
  case "$t" in
    all)         TOOLS=(claude-code codex) ;;
    claude-code) TOOLS+=(claude-code) ;;
    codex)       TOOLS+=(codex) ;;
    "") ;;
    *) echo "invalid --tool entry: $t" >&2; exit 2 ;;
  esac
done
# dedupe
declare -a UNIQUE_TOOLS=()
for t in "${TOOLS[@]}"; do
  found=0
  for u in "${UNIQUE_TOOLS[@]:-}"; do [[ "$u" == "$t" ]] && found=1 && break; done
  (( found )) || UNIQUE_TOOLS+=("$t")
done
TOOLS=("${UNIQUE_TOOLS[@]}")

# Resolve adapter target dirs per tool/scope
adapter_dir_for() {
  local tool="$1"
  case "$SCOPE-$tool" in
    global-claude-code)  echo "$HOME/.claude/commands" ;;
    global-codex)        echo "$HOME/.codex/prompts" ;;
    project-claude-code) echo "$PROJECT_DIR/.claude/commands" ;;
    project-codex)       echo "$PROJECT_DIR/.codex/prompts" ;;
  esac
}

# Manifest path
MANIFEST_DIR="$HOME/.local/share/cmux-sidecar"
if [[ "$SCOPE" == "project" ]]; then
  proj_hash="$(printf '%s' "$PROJECT_DIR" | shasum | awk '{print $1}')"
  MANIFEST="$MANIFEST_DIR/installed-project-$proj_hash.txt"
else
  MANIFEST="$MANIFEST_DIR/installed-global.txt"
fi

# action helpers
say() { printf '%s\n' "$*"; }
do_run() {
  if (( DRY_RUN )); then
    printf '[dry-run] %s\n' "$*"
  else
    eval "$@"
  fi
}

ts() { date +%Y%m%d-%H%M%S; }

install_file() {
  # install_file <src> <dst>
  local src="$1" dst="$2"
  local dst_dir; dst_dir="$(dirname "$dst")"
  do_run "mkdir -p \"$dst_dir\""
  if [[ -e "$dst" || -L "$dst" ]]; then
    if (( NO_CLOBBER )); then
      say "skip (exists): $dst"
      return 0
    fi
    if (( ! FORCE )); then
      local bak="${dst}.bak.$(ts)"
      do_run "mv \"$dst\" \"$bak\""
      say "backup: $bak"
    fi
  fi
  do_run "cp \"$src\" \"$dst\""
  say "install: $dst"
  if (( ! DRY_RUN )); then
    printf '%s\n' "$dst" >> "$MANIFEST"
  fi
}

# Run doctor (informational; do not block)
say "== doctor =="
if ! "$SELF_DIR/doctor.sh"; then
  say "(some dependencies missing — adapter install will continue, but cmux-sidecar will not function until they are installed)"
fi
say ""

# Prepare manifest
if (( ! DRY_RUN )); then
  mkdir -p "$MANIFEST_DIR"
  : > "$MANIFEST"
fi

# 1) install bin
BIN_DST="$BIN_PREFIX/bin/cmux-sidecar"
say "== bin =="
install_file "$SELF_DIR/bin/cmux-sidecar" "$BIN_DST"
do_run "chmod +x \"$BIN_DST\""
say ""

# 2) install adapters
say "== adapters (scope=$SCOPE) =="
for tool in "${TOOLS[@]}"; do
  src="$SELF_DIR/adapters/$tool/sidecar.md"
  if [[ ! -f "$src" ]]; then
    say "missing adapter source: $src — skip"
    continue
  fi
  dst_dir="$(adapter_dir_for "$tool")"
  install_file "$src" "$dst_dir/sidecar.md"
done
say ""

# 3) Final notes
say "== notes =="
case ":$PATH:" in
  *":$BIN_PREFIX/bin:"*) ;;
  *) say "PATH missing: add \"$BIN_PREFIX/bin\" to PATH (e.g. in ~/.zshrc)" ;;
esac

say "invoke:"
for tool in "${TOOLS[@]}"; do
  case "$tool" in
    claude-code) say "  Claude Code : /cmux-sidecar:sidecar [path]" ;;
    codex)       say "  Codex CLI   : /prompts:sidecar [path]" ;;
  esac
done

# Legacy hint
if [[ -e "$HOME/.local/bin/cmux-code-viewer" || -e "$HOME/.claude/commands/code-viewer.md" ]]; then
  say ""
  say "legacy assets detected (no longer needed if you switch to cmux-sidecar):"
  [[ -e "$HOME/.local/bin/cmux-code-viewer" ]] && say "  $HOME/.local/bin/cmux-code-viewer"
  [[ -e "$HOME/.claude/commands/code-viewer.md" ]] && say "  $HOME/.claude/commands/code-viewer.md"
  say "remove manually if you no longer want them."
fi

if (( ! DRY_RUN )); then
  say ""
  say "manifest: $MANIFEST"
fi
