#!/usr/bin/env bash
# install_suckless.sh — build & install suckless stack (NIRUCON Edition)
# Purpose: Compile and install suckless programs from nirucon repo, create minimal ~/.xinitrc
#          (with hook system), and install required fonts.
# Author:  Nicklas Rudolfsson (NIRUCON)
#
# This version ONLY supports the nirucon custom suckless repository.
# No vanilla option, no interactive prompts.

set -Eeuo pipefail
IFS=$'\n\t'

# ───────── Pretty logging ─────────
MAG="\033[1;35m"
YLW="\033[1;33m"
RED="\033[1;31m"
BLU="\033[1;34m"
GRN="\033[1;32m"
NC="\033[0m"
say() { printf "${MAG}[SUCK]${NC} %s\n" "$*"; }
step() { printf "${BLU}==>${NC} %s\n" "$*"; }
warn() { printf "${YLW}[WARN]${NC} %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; }
ok() { printf "${GRN}[OK]${NC} %s\n" "$*"; }
trap 'fail "install_suckless.sh failed. See previous messages for details."' ERR

# ───────── Safety ─────────
[[ ${EUID:-$(id -u)} -ne 0 ]] || {
  fail "Do not run as root."
  exit 1
}
command -v sudo >/dev/null 2>&1 || warn "sudo not found — system install steps may be skipped."

# ───────── Paths / Defaults ─────────
SUCKLESS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/suckless"
LOCAL_BIN="$HOME/.local/bin"
XINIT="$HOME/.xinitrc"
XINITRC_HOOKS="$HOME/.config/xinitrc.d"
PREFIX="/usr/local"
JOBS="$(nproc 2>/dev/null || echo 2)"

# NIRUCON mono-repo (hardcoded)
NIRUCON_REPO="https://github.com/nirucon/suckless"

MANAGE_XINIT=1
INSTALL_FONTS=1
DRY_RUN=0
COMPONENTS=(dwm st dmenu slock slstatus)

FONT_MAIN="JetBrainsMono Nerd Font"
FONT_ICON="Symbols Nerd Font Mono"

usage() {
  cat <<'EOF'
install_suckless.sh — NIRUCON Edition

Builds and installs custom suckless tools from:
  https://github.com/nirucon/suckless

OPTIONS:
  --prefix DIR       Install prefix (default: /usr/local)
  --only LIST        Comma-separated subset: dwm,st,dmenu,slock,slstatus
  --no-xinit         Do NOT create ~/.xinitrc
  --no-fonts         Do NOT attempt to install fonts
  --jobs N           Parallel make -j (default: nproc)
  --dry-run          Print actions without changing the system
  -h|--help          Show this help

DESIGN:
  • Clones nirucon suckless to ~/.config/suckless/
  • Builds and installs to /usr/local/bin/
  • Creates minimal .xinitrc ONCE (with hook system for autostart)
  • Other scripts add hooks to ~/.config/xinitrc.d/ (no conflicts)
  • Installs required Nerd Fonts automatically
EOF
}

need_val() {
  local opt="$1" val="${2-}"
  [[ -n "$val" ]] || fail "Option $opt requires a value. See --help."
}
parse_components() { IFS=',' read -r -a COMPONENTS <<<"$1"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
  --prefix)
    need_val "$1" "${2-}"
    PREFIX="$2"
    shift 2
    ;;
  --only)
    need_val "$1" "${2-}"
    parse_components "$2"
    shift 2
    ;;
  --jobs)
    need_val "$1" "${2-}"
    JOBS="$2"
    shift 2
    ;;
  --no-xinit)
    MANAGE_XINIT=0
    shift
    ;;
  --no-fonts)
    INSTALL_FONTS=0
    shift
    ;;
  --dry-run)
    DRY_RUN=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    warn "Unknown argument: $1"
    usage
    exit 1
    ;;
  esac
done

# ───────── Helpers (array-safe) ─────────
ts() { date +"%Y%m%d-%H%M%S"; }
ensure_dir() { mkdir -p "$@"; }
run() { if [[ $DRY_RUN -eq 1 ]]; then say "[dry-run] $*"; else "$@"; fi; }

pkg_install() {
  local pkgs=(base-devel git make gcc pkgconf
    libx11 libxft libxinerama libxrandr libxext libxrender libxfixes
    freetype2 fontconfig
    xorg-xsetroot xorg-xinit)
  if command -v pacman >/dev/null 2>&1; then
    step "Installing build/runtime dependencies via pacman (if missing)"
    run sudo pacman -S --needed --noconfirm "${pkgs[@]}" || warn "pacman dependency install failed (continuing)"
  else
    warn "pacman not found; ensure build deps are present manually."
  fi
}

fonts_install_if_missing() {
  [[ $INSTALL_FONTS -eq 1 ]] || {
    warn "--no-fonts set: skipping font checks/install"
    return 0
  }
  step "Checking for required fonts"
  local need_main=1 need_icon=1
  fc-list | grep -qi "${FONT_MAIN}" && need_main=0 || true
  fc-list | grep -qi "${FONT_ICON}" && need_icon=0 || true
  ((need_main == 0 && need_icon == 0)) && {
    say "Required fonts already installed"
    return 0
  }
  if ((need_icon == 1)) && command -v pacman >/dev/null 2>&1; then
    say "Installing ${FONT_ICON} via pacman"
    run sudo pacman -S --needed --noconfirm ttf-nerd-fonts-symbols-mono || true
  fi
  if ((need_main == 1)); then
    if ! command -v yay >/dev/null 2>&1; then
      step "Installing yay-bin (AUR helper) to fetch ${FONT_MAIN}"
      local tmp
      tmp="$(mktemp -d)"
      run git clone https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
      (cd "$tmp/yay-bin" && run makepkg -si --noconfirm)
      rm -rf "$tmp"
    fi
    say "Installing ${FONT_MAIN} via yay"
    run yay --noconfirm --needed -S ttf-jetbrains-mono-nerd || true
  fi
}

clone_or_pull() {
  local url="$1" dir="$2"
  if [[ -d "$dir/.git" ]]; then
    step "Updating $(basename "$dir")"
    run git -C "$dir" fetch --all --prune || warn "git fetch failed for $dir"
    run git -C "$dir" pull --ff-only || warn "git pull failed for $dir; keeping existing tree."
  else
    ensure_dir "$(dirname "$dir")"
    step "Cloning $(basename "$dir")"
    run git clone "$url" "$dir"
  fi
}

make_install() {
  local dir="$1" name="$2"
  step "Building $name"
  (cd "$dir" && { [[ $DRY_RUN -eq 1 ]] && say "[dry-run] make -j$JOBS && sudo make PREFIX=$PREFIX install" ||
    { make clean && make -j"$JOBS" && sudo make PREFIX="$PREFIX" install; }; })
}

# ───────── Prepare & deps ─────────
ensure_dir "$SUCKLESS_DIR" "$LOCAL_BIN" "$XINITRC_HOOKS"
pkg_install
fonts_install_if_missing

# ───────── Fetch sources ─────────
say "Source: NIRUCON ($NIRUCON_REPO)"
clone_or_pull "$NIRUCON_REPO" "$SUCKLESS_DIR"

# ───────── Build & install ─────────
for comp in "${COMPONENTS[@]}"; do
  if [[ -d "$SUCKLESS_DIR/$comp" ]]; then
    make_install "$SUCKLESS_DIR/$comp" "$comp"
  else
    warn "$comp not found under $SUCKLESS_DIR — skipping"
  fi
done

# ───────── .xinitrc creation (ONCE, minimal template) ─────────
if [[ $MANAGE_XINIT -eq 1 ]]; then
  # CRITICAL: Always ensure hooks directory exists
  step "Ensuring xinitrc hooks directory exists"
  ensure_dir "$XINITRC_HOOKS"
  
  if [[ ! -f "$XINIT" ]]; then
    step "Creating minimal ~/.xinitrc with hook system"
    cat >"$XINIT" <<'EOF'
#!/bin/sh
# =============================================================================
#  .xinitrc — Arch Linux + Suckless (NIRUCON Edition)
#  Created by install_suckless.sh
#  
#  This file is created ONCE and never modified by install scripts.
#  Autostart programs are managed via hooks in ~/.config/xinitrc.d/
# =============================================================================

# ───────── 1) Session Setup ─────────

# Always start in $HOME
cd "$HOME"

# Start D-Bus session if not already running
if [ -z "${DBUS_SESSION_BUS_ADDRESS-}" ] && command -v dbus-run-session >/dev/null 2>&1; then
  exec dbus-run-session "$0" "$@"
fi

# Export X environment to systemd user services
if command -v dbus-update-activation-environment >/dev/null 2>&1; then
  dbus-update-activation-environment --systemd DISPLAY XAUTHORITY
fi

# Load X resources (fonts, colors, DPI settings)
[ -r "$HOME/.Xresources" ] && xrdb -merge "$HOME/.Xresources"

# Set keyboard layout (change 'se' to your layout: us, gb, de, etc.)
command -v setxkbmap >/dev/null 2>&1 && setxkbmap se

# Set root window background color (prevents ugly gray)
command -v xsetroot >/dev/null 2>&1 && xsetroot -solid "#111111"

# Optional: enable NumLock at startup
# command -v numlockx >/dev/null 2>&1 && numlockx on

# Optional: HiDPI scaling (uncomment and adjust for your display)
# command -v xrandr >/dev/null 2>&1 && xrandr --output eDP-1 --scale 0.75x0.75

# ───────── 2) GTK & Qt Theming ─────────

export XDG_CONFIG_HOME="$HOME/.config"
export GTK_THEME="Adwaita:dark"
export QT_STYLE_OVERRIDE="kvantum"
export QT_QPA_PLATFORMTHEME="qt5ct"
export XCURSOR_THEME="Adwaita"
export GTK2_RC_FILES="$HOME/.gtkrc-2.0"

# ───────── 3) Autostart Programs (via hooks) ─────────

# Source all executable hooks from ~/.config/xinitrc.d/
# Other install scripts (lookandfeel, statusbar) create hooks here
# Hooks are executed in alphabetical order (10-*, 20-*, 30-*, etc.)
if [ -d "$HOME/.config/xinitrc.d" ]; then
  for hook in "$HOME/.config/xinitrc.d"/*.sh; do
    [ -x "$hook" ] && . "$hook"
  done
fi

# ───────── 4) DWM Launch & Cleanup ─────────

# Ensure all background processes terminate when X session ends
trap 'kill -- -$$' EXIT

# DWM restart loop
# If DWM crashes or you reload config (Mod+Shift+Q), it restarts automatically
# Exit loop by logging out (Mod+Shift+E) or closing X server
while true; do
  /usr/local/bin/dwm 2>/tmp/dwm.log
done
EOF
    chmod 644 "$XINIT"
    ok "Created ~/.xinitrc (will never be modified by install scripts)"
  else
    say "~/.xinitrc already exists — leaving untouched"
  fi

  # Create basic suckless hook (screen locker)
  step "Creating xinitrc hook for suckless tools"
  cat >"$XINITRC_HOOKS/40-suckless.sh" <<'EOF'
#!/bin/sh
# Suckless tools hook
# Created by install_suckless.sh

# Automatic screen lock on idle (requires slock and xautolock)
if command -v xautolock >/dev/null 2>&1 && command -v slock >/dev/null 2>&1; then
  xautolock -time 10 -locker slock &
fi
EOF
  chmod +x "$XINITRC_HOOKS/40-suckless.sh"
  ok "Created xinitrc hook: ~/.config/xinitrc.d/40-suckless.sh"

else
  warn "--no-xinit set: leaving ~/.xinitrc untouched"
fi

cat <<'EOT'
========================================================
Suckless installation complete (NIRUCON Edition)

- Components built and installed to /usr/local/bin/
- Sources stored in ~/.config/suckless/
- Minimal ~/.xinitrc created with hook system
- Other scripts will add autostart hooks to ~/.config/xinitrc.d/

Next steps:
  1. Run other install scripts (lookandfeel, statusbar, etc.)
  2. Start X session with: startx
  
To rebuild after config changes:
  cd ~/.config/suckless/dwm && sudo make clean install

Repository: https://github.com/nirucon/suckless
========================================================
EOT
