#!/usr/bin/env bash
# cmux-sidecar uninstaller.
# Reads the install manifest and removes only those exact paths.
# Empty parent directories (e.g. .claude/commands) are NOT removed —
# they may have been created by the user or other tools.
set -euo pipefail

SCOPE="global"
PROJECT_DIR=""
DRY_RUN=0
YES=0

usage() {
  cat <<'EOF'
Usage: uninstall.sh [options]

Options:
  --scope=SCOPE     global | project (default: global)
  --project=PATH    target project dir when --scope=project (default: $PWD)
  --dry-run         print actions without performing them
  -y, --yes         skip confirmation when manifest is missing
  -h, --help        show this help
EOF
}

for arg in "$@"; do
  case "$arg" in
    --scope=*)    SCOPE="${arg#*=}" ;;
    --project=*)  PROJECT_DIR="${arg#*=}" ;;
    --dry-run)    DRY_RUN=1 ;;
    -y|--yes)     YES=1 ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "unknown option: $arg" >&2; usage; exit 2 ;;
  esac
done

case "$SCOPE" in
  global) ;;
  project)
    [[ -z "$PROJECT_DIR" ]] && PROJECT_DIR="$PWD"
    PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
    ;;
  *) echo "invalid --scope: $SCOPE (must be global|project)" >&2; exit 2 ;;
esac

MANIFEST_DIR="$HOME/.local/share/cmux-sidecar"
if [[ "$SCOPE" == "project" ]]; then
  proj_hash="$(printf '%s' "$PROJECT_DIR" | shasum | awk '{print $1}')"
  MANIFEST="$MANIFEST_DIR/installed-project-$proj_hash.txt"
else
  MANIFEST="$MANIFEST_DIR/installed-global.txt"
fi

remove_path() {
  local p="$1"
  if [[ ! -e "$p" && ! -L "$p" ]]; then
    echo "skip (absent): $p"
    return 0
  fi
  if (( DRY_RUN )); then
    echo "[dry-run] rm \"$p\""
  else
    rm -- "$p"
    echo "remove: $p"
  fi
}

if [[ -f "$MANIFEST" ]]; then
  echo "manifest: $MANIFEST"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    remove_path "$line"
  done < "$MANIFEST"
  if (( ! DRY_RUN )); then
    rm -f "$MANIFEST"
    echo "remove manifest: $MANIFEST"
  fi
  exit 0
fi

# Manifest missing: list candidate paths and ask for confirmation
echo "manifest not found: $MANIFEST"
echo "candidate paths (cmux-sidecar default install locations):"
candidates=(
  "$HOME/.local/bin/cmux-sidecar"
)
if [[ "$SCOPE" == "project" ]]; then
  candidates+=(
    "$PROJECT_DIR/.claude/commands/sidecar.md"
    "$PROJECT_DIR/.codex/prompts/sidecar.md"
  )
else
  candidates+=(
    "$HOME/.claude/commands/sidecar.md"
    "$HOME/.codex/prompts/sidecar.md"
  )
fi
present=()
for c in "${candidates[@]}"; do
  if [[ -e "$c" || -L "$c" ]]; then
    echo "  $c"
    present+=("$c")
  fi
done

if [[ ${#present[@]} -eq 0 ]]; then
  echo "(nothing to remove)"
  exit 0
fi

if (( ! YES )) && (( ! DRY_RUN )); then
  printf "remove the listed paths? [y/N]: "
  read -r ans || true
  case "${ans:-}" in
    y|Y|yes|YES) ;;
    *) echo "aborted."; exit 1 ;;
  esac
fi

for p in "${present[@]}"; do
  remove_path "$p"
done
