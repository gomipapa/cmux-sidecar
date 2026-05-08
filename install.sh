#!/usr/bin/env bash
# cmux-sidecar installer.
# - Copies bin/cmux-sidecar to <bin-prefix>/bin/cmux-sidecar
# - Installs adapter files to global or project scope, per --tool selection
# - Records installed paths in a manifest for accurate uninstall
# - Optionally offers to brew-install code-server (with consent)
set -euo pipefail

VERSION="0.1.0"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- defaults ----------
BIN_PREFIX="$HOME/.local"
SCOPE="global"
PROJECT_DIR=""
TOOL_PICK="all"
FORCE=0
NO_CLOBBER=0
DRY_RUN=0
INTERACTIVE=1
INSTALL_DEPS=""   # "" = ask in interactive / skip in non-interactive; "1" yes; "0" no
ASSUME_YES=0

# ---------- color helpers ----------
USE_COLOR=1
[[ -n "${NO_COLOR:-}" ]] && USE_COLOR=0
[[ ! -t 1 ]] && USE_COLOR=0
[[ -n "${FORCE_COLOR:-}" ]] && USE_COLOR=1

c() { (( USE_COLOR )) && printf '\033[%sm' "$1" || true; }
init_colors() {
  RESET="$(c 0)"; BOLD="$(c 1)"; DIM="$(c 2)"
  RED="$(c 31)"; GREEN="$(c 32)"; YELLOW="$(c 33)"
  BLUE="$(c 34)"; CYAN="$(c 36)"
  ICON_OK="${GREEN}✓${RESET}"
  ICON_FAIL="${RED}✗${RESET}"
  ICON_ARROW="${CYAN}›${RESET}"
  ICON_BULLET="${BLUE}•${RESET}"
}

usage() {
  cat <<EOF
Usage: install.sh [options]

Without options, runs an interactive setup wizard.

Options (all imply non-interactive mode):
  --bin-prefix=PATH      binary install prefix (default: \$HOME/.local)
  --scope=SCOPE          global | project (default: global)
  --project=PATH         target project dir when --scope=project (default: \$PWD)
  --tool=LIST            claude-code,codex,all (default: all). comma-separated.
  --install-deps         install missing dependencies (currently: code-server via brew)
  --no-install-deps      skip dependency install
  --force                overwrite existing files without backup
  --no-clobber           skip existing files
  --dry-run              print actions without performing them
  -y, --yes              skip the final Proceed? confirmation
  --no-color             disable ANSI colors
  -h, --help             show this help
EOF
}

# ---------- arg parsing ----------
for arg in "$@"; do
  case "$arg" in
    --bin-prefix=*)     BIN_PREFIX="${arg#*=}"; INTERACTIVE=0 ;;
    --scope=*)          SCOPE="${arg#*=}"; INTERACTIVE=0 ;;
    --project=*)        PROJECT_DIR="${arg#*=}"; INTERACTIVE=0 ;;
    --tool=*)           TOOL_PICK="${arg#*=}"; INTERACTIVE=0 ;;
    --install-deps)     INSTALL_DEPS=1; INTERACTIVE=0 ;;
    --no-install-deps)  INSTALL_DEPS=0; INTERACTIVE=0 ;;
    --force)            FORCE=1 ;;
    --no-clobber)       NO_CLOBBER=1 ;;
    --dry-run)          DRY_RUN=1 ;;
    -y|--yes)           ASSUME_YES=1; INTERACTIVE=0 ;;
    --no-color)         USE_COLOR=0 ;;
    -h|--help)          usage; exit 0 ;;
    *) echo "unknown option: $arg" >&2; usage; exit 2 ;;
  esac
done

(( FORCE && NO_CLOBBER )) && { echo "--force and --no-clobber are mutually exclusive" >&2; exit 2; }

init_colors

# ---------- UI primitives ----------
section() { printf '\n%s%s%s\n' "$BOLD" "$1" "$RESET"; }

banner() {
  if (( ! USE_COLOR )); then
    printf '\ncmux-sidecar installer  v%s\n' "$VERSION"
    printf '%s\n' "──────────────────────────────────────────"
    return
  fi
  printf '\n%s%s%s  %sv%s%s\n' "$BOLD" "cmux-sidecar installer" "$RESET" "$DIM" "$VERSION" "$RESET"
  printf '%s──────────────────────────────────────────%s\n' "$DIM" "$RESET"
}

# Open /dev/tty for direct input/output, sidestepping any redirected stdin.
# Sets TTY_FD (input) and TTY_OUT (output), or empty strings if unavailable.
# Use { ... } 2>/dev/null so a failed open doesn't leak a shell error.
TTY_FD=""
TTY_OUT=""
{ exec 3</dev/tty; } 2>/dev/null && TTY_FD=3
{ exec 4>/dev/tty; } 2>/dev/null && TTY_OUT=4

# Read a single keypress directly from the TTY into the global REPLY_KEY.
# Returns one of: ENTER, UP, DOWN, LEFT, RIGHT, ESC, or a literal character.
read_key() {
  REPLY_KEY=""
  local k=""
  IFS= read -u "$TTY_FD" -rsn1 k || { REPLY_KEY="EOF"; return 1; }
  if [[ "$k" == $'\x1b' ]]; then
    local k2=""
    if ! IFS= read -u "$TTY_FD" -rsn1 -t 1 k2; then REPLY_KEY="ESC"; return 0; fi
    if [[ "$k2" == "[" || "$k2" == "O" ]]; then
      local k3=""
      if ! IFS= read -u "$TTY_FD" -rsn1 -t 1 k3; then REPLY_KEY="ESC"; return 0; fi
      case "$k3" in
        A) REPLY_KEY="UP" ;;    B) REPLY_KEY="DOWN" ;;
        C) REPLY_KEY="RIGHT" ;; D) REPLY_KEY="LEFT" ;;
        *) REPLY_KEY="ESC" ;;
      esac
    else
      REPLY_KEY="ESC"
    fi
    return 0
  fi
  case "$k" in
    ""|$'\n'|$'\r') REPLY_KEY="ENTER" ;;
    *)              REPLY_KEY="$k" ;;
  esac
}

# arrow_menu "Title" default_value value1 value2 ...
# Interactive arrow-key menu. Result lands in global REPLY_MENU.
# Falls back to numbered menu() if /dev/tty is unavailable.
arrow_menu() {
  local title="$1" default="$2"; shift 2
  local opts=("$@")
  local n=${#opts[@]}
  REPLY_MENU=""

  if [[ -z "$TTY_FD" || -z "$TTY_OUT" ]]; then
    REPLY_MENU="$(menu "$title" "$default" "${opts[@]}")"
    return
  fi

  local sel=0 i=0
  for v in "${opts[@]}"; do
    [[ "$v" == "$default" ]] && sel=$i
    i=$((i+1))
  done

  printf '\033[?25l' >&"$TTY_OUT"
  trap 'printf "\033[?25h\n" >&'"$TTY_OUT"'; exit 130' INT

  _draw_menu() {
    printf '%s%s:%s\n' "$BOLD" "$title" "$RESET" >&"$TTY_OUT"
    local j=0
    for v in "${opts[@]}"; do
      if (( j == sel )); then
        printf '  %s›%s %s%s%s\n' "$CYAN" "$RESET" "$BOLD" "$v" "$RESET" >&"$TTY_OUT"
      else
        printf '    %s%s%s\n' "$DIM" "$v" "$RESET" >&"$TTY_OUT"
      fi
      j=$((j+1))
    done
    printf '  %s↑/↓ move · Enter select · 1-%d quick · q quit%s\n' "$DIM" "$n" "$RESET" >&"$TTY_OUT"
  }

  printf '\n' >&"$TTY_OUT"
  _draw_menu
  local lines=$((n+2))

  while true; do
    read_key
    case "$REPLY_KEY" in
      UP)    sel=$(( (sel - 1 + n) % n )) ;;
      DOWN)  sel=$(( (sel + 1) % n )) ;;
      ENTER)
        printf '\033[?25h' >&"$TTY_OUT"
        trap - INT
        REPLY_MENU="${opts[$sel]}"
        return 0
        ;;
      ESC|q|Q|EOF)
        printf '\033[?25h\n' >&"$TTY_OUT"
        trap - INT
        printf '%saborted.%s\n' "$YELLOW" "$RESET" >&2
        exit 130
        ;;
      [1-9])
        local idx=$((REPLY_KEY - 1))
        (( idx >= 0 && idx < n )) && sel=$idx
        ;;
      *) continue ;;
    esac
    printf '\033[%dF\033[J' "$lines" >&"$TTY_OUT"
    _draw_menu
  done
}

# menu "Title" default_value value1 value2 ...
# Numbered fallback (used when /dev/tty is unavailable). Emits to stdout.
menu() {
  local title="$1" default="$2"; shift 2
  printf '\n%s%s:%s\n' "$BOLD" "$title" "$RESET" >&2
  local i=1
  for v in "$@"; do
    if [[ "$v" == "$default" ]]; then
      printf '  %s%d)%s %-14s %s· default%s\n' "$BOLD" "$i" "$RESET" "$v" "$DIM" "$RESET" >&2
    else
      printf '  %s%d)%s %s\n' "$DIM" "$i" "$RESET" "$v" >&2
    fi
    i=$((i+1))
  done
  printf '%s ' "$ICON_ARROW" >&2
  local ans=""
  read -r ans || true
  if [[ -z "$ans" ]]; then printf '%s' "$default"; return; fi
  if [[ "$ans" =~ ^[0-9]+$ ]]; then
    local idx="$ans" i2=1
    for v in "$@"; do
      [[ "$i2" == "$idx" ]] && { printf '%s' "$v"; return; }
      i2=$((i2+1))
    done
  fi
  for v in "$@"; do
    [[ "$v" == "$ans" ]] && { printf '%s' "$ans"; return; }
  done
  printf '%s' "$default"
}

# confirm "prompt" default(Y|N)  → returns 0 yes / 1 no
confirm() {
  local prompt="$1" default="${2:-Y}"
  local hint="[Y/n]"
  [[ "$default" == "N" ]] && hint="[y/N]"
  local out_fd="${TTY_OUT:-2}" in_fd="${TTY_FD:-0}"
  printf '\n%s %s %s ' "$prompt" "$hint" "$ICON_ARROW" >&"$out_fd"
  local ans=""
  IFS= read -u "$in_fd" -r ans || true
  ans="${ans:-$default}"
  case "$ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# ---------- intro ----------
banner

# ---------- step 1: scope ----------
if (( INTERACTIVE )); then
  arrow_menu "Scope" global global project
  SCOPE="$REPLY_MENU"
fi
case "$SCOPE" in
  global) ;;
  project)
    [[ -z "$PROJECT_DIR" ]] && PROJECT_DIR="$PWD"
    PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
    ;;
  *) echo "${RED}invalid --scope: $SCOPE${RESET}" >&2; exit 2 ;;
esac

# ---------- step 2: tool ----------
if (( INTERACTIVE )); then
  arrow_menu "Tools to install" all all claude-code codex
  TOOL_PICK="$REPLY_MENU"
fi
declare -a TOOLS=()
IFS=',' read -ra raw_tools <<< "$TOOL_PICK"
for t in "${raw_tools[@]}"; do
  case "$t" in
    all)         TOOLS=(claude-code codex) ;;
    claude-code) TOOLS+=(claude-code) ;;
    codex)       TOOLS+=(codex) ;;
    "") ;;
    *) echo "${RED}invalid --tool entry: $t${RESET}" >&2; exit 2 ;;
  esac
done
declare -a UNIQUE_TOOLS=()
for t in "${TOOLS[@]}"; do
  found=0
  for u in "${UNIQUE_TOOLS[@]:-}"; do [[ "$u" == "$t" ]] && found=1 && break; done
  (( found )) || UNIQUE_TOOLS+=("$t")
done
TOOLS=("${UNIQUE_TOOLS[@]}")

# ---------- step 3: dependency check ----------
section "Dependencies:"
declare -a DEP_LINES=()
DEP_FAIL=0
CS_MISSING=0
CMUX_MISSING=0

dep_check() {
  local name="$1" cmd="$2" required="$3"   # required=1|0
  local resolved
  resolved="$(command -v "$cmd" 2>/dev/null || true)"
  if [[ -n "$resolved" ]]; then
    local v
    v="$("$cmd" --version 2>&1 | head -n1)"
    printf '  %s  %-13s %s%s%s\n' "$ICON_OK" "$name" "$DIM" "${v:0:50}" "$RESET"
  else
    if (( required )); then
      printf '  %s  %-13s %snot installed%s\n' "$ICON_FAIL" "$name" "$DIM" "$RESET"
      DEP_FAIL=1
    else
      printf '  %s  %-13s %snot installed (optional / lazy)%s\n' "$ICON_FAIL" "$name" "$DIM" "$RESET"
    fi
    case "$cmd" in
      code-server) CS_MISSING=1 ;;
      cmux)        CMUX_MISSING=1 ;;
    esac
  fi
}
dep_check "cmux"         cmux         1
dep_check "code-server"  code-server  0
dep_check "curl"         curl         1
dep_check "python3"      python3      1

# ---------- step 4: dep install consent (code-server only) ----------
WILL_INSTALL_CS=0
if (( CS_MISSING )); then
  if command -v brew >/dev/null 2>&1; then
    if [[ "$INSTALL_DEPS" == "1" ]]; then
      WILL_INSTALL_CS=1
    elif [[ "$INSTALL_DEPS" == "0" ]]; then
      WILL_INSTALL_CS=0
    elif (( INTERACTIVE )); then
      if confirm "Install ${BOLD}code-server${RESET} via brew?" Y; then
        WILL_INSTALL_CS=1
      fi
    fi
  else
    printf '\n  %sHomebrew not found — install code-server manually:%s\n' "$DIM" "$RESET"
    printf '  %s  https://coder.com/docs/code-server/install%s\n' "$DIM" "$RESET"
  fi
fi

if (( CMUX_MISSING )); then
  printf '\n  %scmux is required but not handled here. install via your cmux distribution.%s\n' "$DIM" "$RESET"
fi

# ---------- step 5: plan summary ----------
adapter_dir_for() {
  local tool="$1"
  case "$SCOPE-$tool" in
    global-claude-code)  echo "$HOME/.claude/commands" ;;
    global-codex)        echo "$HOME/.codex/prompts" ;;
    project-claude-code) echo "$PROJECT_DIR/.claude/commands" ;;
    project-codex)       echo "$PROJECT_DIR/.codex/prompts" ;;
  esac
}

BIN_DST="$BIN_PREFIX/bin/cmux-sidecar"
declare -a PLAN_LINES=()
PLAN_LINES+=("$(printf '%s  bin    → %s' "$ICON_BULLET" "$BIN_DST")")
(( WILL_INSTALL_CS )) && PLAN_LINES+=("$(printf '%s  dep    → brew install code-server' "$ICON_BULLET")")
for tool in "${TOOLS[@]}"; do
  PLAN_LINES+=("$(printf '%s  hook   → %s/sidecar.md  %s(%s)%s' "$ICON_BULLET" "$(adapter_dir_for "$tool")" "$DIM" "$tool" "$RESET")")
done

section "Ready to install:"
for line in "${PLAN_LINES[@]}"; do printf '  %s\n' "$line"; done
if (( DRY_RUN )); then
  printf '\n  %s(dry-run — nothing will be written)%s\n' "$YELLOW" "$RESET"
fi

# ---------- step 6: confirm gate ----------
if (( ! ASSUME_YES )) && (( INTERACTIVE )) && (( ! DRY_RUN )); then
  if ! confirm "Proceed?" Y; then
    printf '\n%saborted.%s\n' "$YELLOW" "$RESET"
    exit 1
  fi
fi

# ---------- execution helpers ----------
do_run() {
  if (( DRY_RUN )); then
    printf '    %s[dry] %s%s\n' "$DIM" "$*" "$RESET"
  else
    eval "$@"
  fi
}
ts() { date +%Y%m%d-%H%M%S; }

MANIFEST_DIR="$HOME/.local/share/cmux-sidecar"
if [[ "$SCOPE" == "project" ]]; then
  proj_hash="$(printf '%s' "$PROJECT_DIR" | shasum | awk '{print $1}')"
  MANIFEST="$MANIFEST_DIR/installed-project-$proj_hash.txt"
else
  MANIFEST="$MANIFEST_DIR/installed-global.txt"
fi
if (( ! DRY_RUN )); then
  mkdir -p "$MANIFEST_DIR"
  : > "$MANIFEST"
fi

install_file() {
  local src="$1" dst="$2" label="$3"
  local dst_dir; dst_dir="$(dirname "$dst")"
  do_run "mkdir -p \"$dst_dir\""
  if [[ -e "$dst" || -L "$dst" ]]; then
    if (( NO_CLOBBER )); then
      printf '  %s  %-7s %sskip (exists)%s %s\n' "$ICON_FAIL" "$label" "$DIM" "$RESET" "$dst"
      return 0
    fi
    if (( ! FORCE )); then
      local bak="${dst}.bak.$(ts)"
      do_run "mv \"$dst\" \"$bak\""
      printf '  %s  %-7s %sbackup → %s%s\n' "$ICON_OK" "$label" "$DIM" "$bak" "$RESET"
    fi
  fi
  do_run "cp \"$src\" \"$dst\""
  printf '  %s  %-7s %s\n' "$ICON_OK" "$label" "$dst"
  if (( ! DRY_RUN )); then printf '%s\n' "$dst" >> "$MANIFEST"; fi
}

# ---------- step 7: execute ----------
section "Installing..."

install_file "$SELF_DIR/bin/cmux-sidecar" "$BIN_DST" "bin"
do_run "chmod +x \"$BIN_DST\""

if (( WILL_INSTALL_CS )); then
  printf '  %s  %-7s %sbrew install code-server (this may take a few minutes)%s\n' "$ICON_BULLET" "dep" "$DIM" "$RESET"
  if (( DRY_RUN )); then
    printf '    %s[dry] brew install code-server%s\n' "$DIM" "$RESET"
  else
    if brew install code-server; then
      printf '  %s  %-7s code-server installed\n' "$ICON_OK" "dep"
    else
      printf '  %s  %-7s brew install failed (continuing)\n' "$ICON_FAIL" "dep"
    fi
  fi
fi

for tool in "${TOOLS[@]}"; do
  src="$SELF_DIR/adapters/$tool/sidecar.md"
  if [[ ! -f "$src" ]]; then
    printf '  %s  %-7s missing source: %s\n' "$ICON_FAIL" "hook" "$src"
    continue
  fi
  install_file "$src" "$(adapter_dir_for "$tool")/sidecar.md" "hook"
done

# ---------- step 8: outro ----------
if (( DRY_RUN )); then
  section "Preview complete (dry-run)."
else
  section "Done."
fi

# PATH hint
case ":$PATH:" in
  *":$BIN_PREFIX/bin:"*) ;;
  *)
    printf '\n  %s%s%s/bin not in PATH. Add to your shell rc:%s\n' "$YELLOW" "$BIN_PREFIX" "$RESET" ""
    printf '    %sexport PATH="%s/bin:$PATH"%s\n' "$DIM" "$BIN_PREFIX" "$RESET"
    ;;
esac

printf '\n  %sTry it:%s\n' "$BOLD" "$RESET"
for tool in "${TOOLS[@]}"; do
  case "$tool" in
    claude-code) printf '    %sClaude Code%s   /cmux-sidecar:sidecar [path]\n' "$CYAN" "$RESET" ;;
    codex)       printf '    %sCodex CLI%s     /prompts:sidecar [path]\n' "$CYAN" "$RESET" ;;
  esac
done

# Legacy hint
LEGACY=()
[[ -e "$HOME/.local/bin/cmux-code-viewer" ]] && LEGACY+=("$HOME/.local/bin/cmux-code-viewer")
[[ -e "$HOME/.claude/commands/code-viewer.md" ]] && LEGACY+=("$HOME/.claude/commands/code-viewer.md")
if (( ${#LEGACY[@]} > 0 )); then
  printf '\n  %sLegacy assets detected — remove if no longer needed:%s\n' "$DIM" "$RESET"
  for p in "${LEGACY[@]}"; do printf '    %s%s%s\n' "$DIM" "$p" "$RESET"; done
fi

if (( ! DRY_RUN )); then
  printf '\n  %smanifest: %s%s\n' "$DIM" "$MANIFEST" "$RESET"
fi
printf '\n'
