#!/usr/bin/env bash
# cmux-sidecar uninstaller.
# - Removes installed paths recorded in the manifest
# - Optionally removes code-server (brew + processes) and its data dirs
# Empty parent directories (e.g. .claude/commands) are NOT removed —
# they may have been created by the user or other tools.
set -euo pipefail

VERSION="0.1.0"

SCOPE="global"
PROJECT_DIR=""
DRY_RUN=0
ASSUME_YES=0
REMOVE_CS=""        # "" ask / "1" remove / "0" keep
REMOVE_CS_DATA=""   # "" ask / "1" remove / "0" keep

usage() {
  cat <<'EOF'
Usage: uninstall.sh [options]

Removes the cmux-sidecar binary, adapter files, and (optionally) the
code-server installation that was set up alongside it.

Options:
  --scope=SCOPE                  global | project (default: global)
  --project=PATH                 target project dir when --scope=project
  --remove-code-server           also brew-uninstall code-server
  --keep-code-server             keep code-server (skip prompt)
  --remove-code-server-data      also wipe ~/.local/share/code-server
                                 and ~/.config/code-server
  --keep-code-server-data        keep code-server data (skip prompt)
  --dry-run                      print actions without performing them
  -y, --yes                      skip confirmations when manifest is missing
  --no-color                     disable ANSI colors
  -h, --help                     show this help
EOF
}

USE_COLOR=1
[[ -n "${NO_COLOR:-}" ]] && USE_COLOR=0
[[ ! -t 1 ]] && USE_COLOR=0
[[ -n "${FORCE_COLOR:-}" ]] && USE_COLOR=1

for arg in "$@"; do
  case "$arg" in
    --scope=*)                    SCOPE="${arg#*=}" ;;
    --project=*)                  PROJECT_DIR="${arg#*=}" ;;
    --remove-code-server)         REMOVE_CS=1 ;;
    --keep-code-server)           REMOVE_CS=0 ;;
    --remove-code-server-data)    REMOVE_CS_DATA=1 ;;
    --keep-code-server-data)      REMOVE_CS_DATA=0 ;;
    --dry-run)                    DRY_RUN=1 ;;
    -y|--yes)                     ASSUME_YES=1 ;;
    --no-color)                   USE_COLOR=0 ;;
    -h|--help)                    usage; exit 0 ;;
    *) echo "unknown option: $arg" >&2; usage; exit 2 ;;
  esac
done

c() { (( USE_COLOR )) && printf '\033[%sm' "$1" || true; }
RESET="$(c 0)"; BOLD="$(c 1)"; DIM="$(c 2)"
RED="$(c 31)"; GREEN="$(c 32)"; YELLOW="$(c 33)"; CYAN="$(c 36)"
ICON_OK="${GREEN}✓${RESET}"
ICON_FAIL="${RED}✗${RESET}"
ICON_ARROW="${CYAN}›${RESET}"

case "$SCOPE" in
  global) ;;
  project)
    [[ -z "$PROJECT_DIR" ]] && PROJECT_DIR="$PWD"
    PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
    ;;
  *) echo "${RED}invalid --scope: $SCOPE${RESET}" >&2; exit 2 ;;
esac

# ---------- TTY for prompts ----------
TTY_FD=""; TTY_OUT=""
{ exec 3</dev/tty; } 2>/dev/null && TTY_FD=3
{ exec 4>/dev/tty; } 2>/dev/null && TTY_OUT=4

confirm() {
  local prompt="$1" default="${2:-N}"
  local hint="[y/N]"
  [[ "$default" == "Y" ]] && hint="[Y/n]"
  if (( ASSUME_YES )) || (( DRY_RUN )); then
    [[ "$default" == "Y" ]] && return 0 || return 1
  fi
  if [[ -z "$TTY_FD" ]]; then
    [[ "$default" == "Y" ]] && return 0 || return 1
  fi
  printf '\n%s %s %s ' "$prompt" "$hint" "$ICON_ARROW" >&"${TTY_OUT:-2}"
  local ans=""
  IFS= read -u "$TTY_FD" -r ans || true
  ans="${ans:-$default}"
  case "$ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# ---------- intro ----------
if (( USE_COLOR )); then
  printf '\n%s%s%s  %sv%s%s\n' "$BOLD" "cmux-sidecar uninstaller" "$RESET" "$DIM" "$VERSION" "$RESET"
  printf '%s──────────────────────────────────────────%s\n' "$DIM" "$RESET"
else
  printf '\ncmux-sidecar uninstaller  v%s\n' "$VERSION"
  printf '%s\n' "──────────────────────────────────────────"
fi

# ---------- manifest path ----------
MANIFEST_DIR="$HOME/.local/share/cmux-sidecar"
if [[ "$SCOPE" == "project" ]]; then
  proj_hash="$(printf '%s' "$PROJECT_DIR" | shasum | awk '{print $1}')"
  MANIFEST="$MANIFEST_DIR/installed-project-$proj_hash.txt"
else
  MANIFEST="$MANIFEST_DIR/installed-global.txt"
fi

# ---------- helpers ----------
remove_path() {
  local p="$1"
  if [[ ! -e "$p" && ! -L "$p" ]]; then
    printf '  %s  %sskip (absent)%s %s\n' "$ICON_FAIL" "$DIM" "$RESET" "$p"
    return 0
  fi
  if (( DRY_RUN )); then
    printf '  %s[dry] rm %s%s\n' "$DIM" "$p" "$RESET"
  else
    rm -- "$p"
    printf '  %s  %s\n' "$ICON_OK" "$p"
  fi
}

remove_dir() {
  local p="$1"
  if [[ ! -e "$p" ]]; then
    printf '  %s  %sskip (absent)%s %s\n' "$ICON_FAIL" "$DIM" "$RESET" "$p"
    return 0
  fi
  if (( DRY_RUN )); then
    printf '  %s[dry] rm -rf %s%s\n' "$DIM" "$p" "$RESET"
  else
    rm -rf -- "$p"
    printf '  %s  %s\n' "$ICON_OK" "$p"
  fi
}

# ---------- step 1: manifest-based removal ----------
printf '\n%scmux-sidecar files (scope=%s):%s\n' "$BOLD" "$SCOPE" "$RESET"

if [[ -f "$MANIFEST" ]]; then
  printf '  %smanifest: %s%s\n' "$DIM" "$MANIFEST" "$RESET"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    remove_path "$line"
  done < "$MANIFEST"
  if (( ! DRY_RUN )); then
    rm -f "$MANIFEST"
    printf '  %s  manifest: %s\n' "$ICON_OK" "$MANIFEST"
  fi
else
  printf '  %smanifest not found — falling back to candidate paths%s\n' "$DIM" "$RESET"
  candidates=( "$HOME/.local/bin/cmux-sidecar" )
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
  for cand in "${candidates[@]}"; do
    [[ -e "$cand" || -L "$cand" ]] && present+=("$cand")
  done
  if (( ${#present[@]} == 0 )); then
    printf '  %s(nothing to remove)%s\n' "$DIM" "$RESET"
  else
    if confirm "Remove the following candidate paths?" N; then
      for p in "${present[@]}"; do remove_path "$p"; done
    else
      printf '  %sskipped.%s\n' "$DIM" "$RESET"
    fi
  fi
fi

# ---------- step 2: optional code-server removal ----------
printf '\n%scode-server:%s\n' "$BOLD" "$RESET"
CS_PATH="$(command -v code-server 2>/dev/null || true)"
if [[ -z "$CS_PATH" ]]; then
  printf '  %s  %snot installed%s\n' "$ICON_FAIL" "$DIM" "$RESET"
else
  printf '  %s  %s\n' "$ICON_OK" "$CS_PATH"

  do_remove_cs=0
  if [[ "$REMOVE_CS" == "1" ]]; then
    do_remove_cs=1
  elif [[ "$REMOVE_CS" == "0" ]]; then
    do_remove_cs=0
  else
    if confirm "Also remove code-server (brew uninstall + stop processes)?" N; then
      do_remove_cs=1
    fi
  fi

  if (( do_remove_cs )); then
    if (( DRY_RUN )); then
      printf '  %s[dry] pkill -f code-server%s\n' "$DIM" "$RESET"
      printf '  %s[dry] brew uninstall code-server%s\n' "$DIM" "$RESET"
    else
      if pgrep -f code-server >/dev/null 2>&1; then
        pkill -f code-server 2>/dev/null || true
        sleep 1
        printf '  %s  stopped running processes\n' "$ICON_OK"
      fi
      if command -v brew >/dev/null 2>&1; then
        if brew uninstall code-server; then
          printf '  %s  brew uninstall code-server\n' "$ICON_OK"
        else
          printf '  %s  brew uninstall failed\n' "$ICON_FAIL"
        fi
      else
        printf '  %s  Homebrew not found — remove code-server manually\n' "$ICON_FAIL"
      fi
    fi
  fi
fi

# ---------- step 3: optional code-server data removal ----------
USER_DATA_DIR="${CMUX_SIDECAR_USER_DATA:-$HOME/.local/share/code-server}"
CONFIG_DIR="$HOME/.config/code-server"
LOG_FILE="${CMUX_SIDECAR_LOG:-/tmp/code-server.log}"
LOCK_DIR="${CMUX_SIDECAR_LOCK:-/tmp/code-server.start.lockdir}"

data_targets=()
[[ -e "$USER_DATA_DIR" ]] && data_targets+=("$USER_DATA_DIR")
[[ -e "$CONFIG_DIR" ]]    && data_targets+=("$CONFIG_DIR")
[[ -e "$LOG_FILE" ]]      && data_targets+=("$LOG_FILE")
[[ -e "$LOCK_DIR" ]]      && data_targets+=("$LOCK_DIR")

if (( ${#data_targets[@]} > 0 )); then
  printf '\n%scode-server data:%s\n' "$BOLD" "$RESET"
  for t in "${data_targets[@]}"; do printf '  %s  %s\n' "$ICON_OK" "$t"; done

  do_remove_data=0
  if [[ "$REMOVE_CS_DATA" == "1" ]]; then
    do_remove_data=1
  elif [[ "$REMOVE_CS_DATA" == "0" ]]; then
    do_remove_data=0
  else
    if confirm "Also remove code-server data (settings, extensions, logs)?" N; then
      do_remove_data=1
    fi
  fi

  if (( do_remove_data )); then
    for t in "${data_targets[@]}"; do remove_dir "$t"; done
  fi
fi

# ---------- outro ----------
if (( DRY_RUN )); then
  printf '\n%sPreview complete (dry-run).%s\n\n' "$BOLD" "$RESET"
else
  printf '\n%sDone.%s\n\n' "$BOLD" "$RESET"
fi
