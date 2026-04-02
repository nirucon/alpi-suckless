#!/usr/bin/env bash
# alpi-suckless.sh — Arch Linux Post Install (NIRUCON Suckless Edition)
# Author: Nicklas Rudolfsson
#
# Single-file installer. No sub-scripts needed.
# Steps: core → apps → suckless → lookandfeel → statusbar → optimize → verify
#
# Usage:
#   ./alpi-suckless.sh                        # Full install
#   ./alpi-suckless.sh --fresh                # Fresh install (clears old state)
#   ./alpi-suckless.sh --only suckless,lookandfeel
#   ./alpi-suckless.sh --skip optimize
#   ./alpi-suckless.sh --dry-run

set -Eeuo pipefail
IFS=$'\n\t'

# ─────────────────────────────────────────────
# LOGGING
# ─────────────────────────────────────────────
NC="\033[0m"
BOLD="\033[1m"
BLU="\033[1;34m"
GRN="\033[1;32m"
YLW="\033[1;33m"
RED="\033[1;31m"
CYN="\033[1;36m"
MAG="\033[1;35m"

say()  { printf "${BLU}[*]${NC} %s\n" "$*"; }
ok()   { printf "${GRN}[✓]${NC} %s\n" "$*"; }
warn() { printf "${YLW}[!]${NC} %s\n" "$*"; }
err()  { printf "${RED}[✗]${NC} %s\n" "$*" >&2; }
die()  { err "$@"; exit 1; }
section() {
  echo
  printf "${BOLD}${MAG}══════════════════════════════════════════════════${NC}\n"
  printf "${BOLD}${MAG}  %s${NC}\n" "$*"
  printf "${BOLD}${MAG}══════════════════════════════════════════════════${NC}\n"
}

trap 'err "Failed at line $LINENO (${BASH_COMMAND:-?})"; exit 1' ERR

# Quick --help before any checks
for _a in "$@"; do [[ "$_a" == "--help" || "$_a" == "-h" ]] && { usage; exit 0; }; done

# ─────────────────────────────────────────────
# SAFETY
# ─────────────────────────────────────────────
[[ ${EUID:-$(id -u)} -ne 0 ]] || die "Do not run as root. Run as your normal user."
command -v sudo >/dev/null 2>&1   || die "sudo not found."
command -v git  >/dev/null 2>&1   || die "git not found. Install base-devel first."
command -v pacman >/dev/null 2>&1 || die "pacman not found. This script requires Arch Linux."

# ─────────────────────────────────────────────
# CONFIG — edit these if needed
# ─────────────────────────────────────────────
SUCKLESS_REPO="https://github.com/nirucon/suckless"
LOOKANDFEEL_REPO="https://github.com/nirucon/suckless_lookandfeel"
LOOKANDFEEL_BRANCH="main"
WALLPAPER_URL="https://n.rudolfsson.net/dl/wallpapers/wallpapers.zip"

SUCKLESS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/suckless"
LOOKANDFEEL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/alpi/lookandfeel/${LOOKANDFEEL_BRANCH}"
WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
LOCAL_BIN="$HOME/.local/bin"
XINITRC_HOOKS="$HOME/.config/xinitrc.d"
XINIT="$HOME/.xinitrc"
PREFIX="/usr/local"
JOBS="$(nproc 2>/dev/null || echo 2)"

# ─────────────────────────────────────────────
# PACKAGE LISTS
# ─────────────────────────────────────────────

PACMAN_PKGS=(
  # Base & build
  base base-devel git make gcc pkgconf curl wget unzip zip tar rsync
  grep sed findutils coreutils which diffutils gawk
  htop less nano tree imlib2 bash-completion

  # Network & security
  networkmanager openssh inetutils bind-tools iproute2 ufw

  # Audio (PipeWire)
  pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber

  # Xorg
  xorg-server xorg-xinit xorg-xsetroot xorg-xrandr xorg-xset xorg-xinput

  # Fonts (base)
  ttf-dejavu noto-fonts noto-fonts-emoji

  # Suckless build deps
  libx11 libxft libxinerama libxrandr libxext libxrender libxfixes freetype2 fontconfig
  xautolock

  # Desktop utilities
  feh arandr pcmanfm gvfs gvfs-mtp gvfs-gphoto2 gvfs-afc udisks2 udiskie

  # Compositor & launcher
  picom rofi

  # Screenshots
  flameshot maim slop

  # Terminal
  alacritty

  # Notifications
  dunst libnotify

  # Theming
  lxappearance arc-gtk-theme papirus-icon-theme qt5ct kvantum qt5-base qt6ct qt6-base

  # Polkit agent
  polkit-gnome

  # Media & graphics
  mpv gimp imagemagick playerctl

  # File tools
  7zip poppler yazi filezilla

  # System monitoring
  btop fastfetch

  # Network tools
  wireless_tools iw blueman

  # Clipboard & utilities
  xclip brightnessctl bc

  # Cloud
  nextcloud-client

  # Dev tools
  neovim lazygit ripgrep fd fzf jq zoxide

  # Neovim/LazyVim deps
  python-pynvim nodejs npm

  # GTK libs
  gtk3 gtk4

  # Btrfs
  btrfs-progs

  # Misc
  cava nsxiv ttf-nerd-fonts-symbols-mono
)

AUR_PKGS=(
  ttf-jetbrains-mono-nerd
  brave-bin
  spotify
  localsend-bin
  reversal-icon-theme-git
  fresh-editor-bin
)

# ─────────────────────────────────────────────
# FLAGS
# ─────────────────────────────────────────────
DRY_RUN=0
FRESH=0
ONLY_STEPS=()
SKIP_STEPS=()
ALL_STEPS=(core apps suckless lookandfeel statusbar optimize verify)

usage() {
  cat <<'EOF'
alpi-suckless.sh — NIRUCON Suckless Arch Installer

USAGE:
  ./alpi-suckless.sh [flags]

FLAGS:
  --fresh           Fresh install: remove old suckless sources, lookandfeel
                    cache, and ~/.xinitrc before installing (forces full redo)
  --only <list>     Run only these steps (comma-separated)
  --skip <list>     Skip these steps (comma-separated)
  --jobs N          Parallel jobs for compilation (default: nproc)
  --dry-run         Preview actions without changes
  --help            Show this help

STEPS:
  core, apps, suckless, lookandfeel, statusbar, optimize, verify

EXAMPLES:
  ./alpi-suckless.sh                                # Full install
  ./alpi-suckless.sh --fresh                        # Wipe and reinstall everything
  ./alpi-suckless.sh --only suckless,lookandfeel    # Rebuild suckless + configs only
  ./alpi-suckless.sh --skip optimize --dry-run      # Preview without optimizations
  ./alpi-suckless.sh --only verify                  # Just run verification

REPOS:
  Suckless:    https://github.com/nirucon/suckless
  Look&feel:   https://github.com/nirucon/suckless_lookandfeel
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fresh)    FRESH=1; shift ;;
    --dry-run)  DRY_RUN=1; shift ;;
    --jobs)     shift; [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]] || die "--jobs requires integer"; JOBS="$1"; shift ;;
    --only)     shift; [[ $# -gt 0 ]] || die "--only requires a list"; IFS=',' read -r -a tmp <<<"$1"; ONLY_STEPS+=("${tmp[@]}"); shift ;;
    --skip)     shift; [[ $# -gt 0 ]] || die "--skip requires a list"; IFS=',' read -r -a tmp <<<"$1"; SKIP_STEPS+=("${tmp[@]}"); shift ;;
    --help|-h)  usage; exit 0 ;;
    *)          die "Unknown flag: $1 (see --help)" ;;
  esac
done

# ─────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────
run() {
  if ((DRY_RUN)); then say "[dry-run] $*"; else "$@"; fi
}

run_shell() {
  if ((DRY_RUN)); then say "[dry-run] $*"; else bash -c "$1"; fi
}

should_run() {
  local step="$1"
  if ((${#ONLY_STEPS[@]} > 0)); then
    local found=1
    for s in "${ONLY_STEPS[@]}"; do [[ "$s" == "$step" ]] && found=0 && break; done
    ((found == 0)) || return 1
  fi
  for s in "${SKIP_STEPS[@]}"; do [[ "$s" == "$step" ]] && return 1; done
  return 0
}

ensure_dir() { mkdir -p "$@"; }

backup_file() {
  local f="$1"
  [[ -e "$f" ]] || return 0
  local ts; ts="$(date +%Y%m%d_%H%M%S)"
  cp -a -- "$f" "${f}.bak.${ts}"
  say "Backed up: $f → ${f}.bak.${ts}"
}

install_file() {
  # install_file SRC DST MODE
  local src="$1" dst="$2" mode="${3:-644}"
  [[ -f "$src" ]] || { warn "Missing source: $src (skipping)"; return 0; }
  if ((DRY_RUN)); then
    say "[dry-run] install $src -> $dst ($mode)"
    return 0
  fi
  ensure_dir "$(dirname "$dst")"
  backup_file "$dst"
  install -m "$mode" "$src" "$dst"
  ok "Installed: $(basename "$src") → $dst"
}

mirror_tree() {
  # mirror_tree SRC_DIR DST_DIR MODE
  local src_base="$1" dst_base="$2" mode="$3"
  [[ -d "$src_base" ]] || { say "No dir $src_base — skipping"; return 0; }
  while IFS= read -r -d '' f; do
    local rel="${f#"$src_base/"}"
    install_file "$f" "$dst_base/$rel" "$mode"
  done < <(find "$src_base" -type f -print0)
}

clone_or_pull() {
  local url="$1" dir="$2"
  if [[ -d "$dir/.git" ]]; then
    say "Updating $(basename "$dir")"
    run git -C "$dir" fetch --all --prune
    run git -C "$dir" reset --hard "origin/${3:-main}" || run git -C "$dir" pull --ff-only
  else
    ensure_dir "$(dirname "$dir")"
    say "Cloning $(basename "$dir")"
    run git clone --depth 1 --branch "${3:-main}" "$url" "$dir"
  fi
}

# ─────────────────────────────────────────────
# FRESH INSTALL CLEANUP
# ─────────────────────────────────────────────
do_fresh() {
  if ! ((FRESH)); then return 0; fi
  section "FRESH INSTALL — Clearing old state"
  warn "Removing old suckless sources, lookandfeel cache, and ~/.xinitrc"
  if ((DRY_RUN)); then
    say "[dry-run] Would remove: $SUCKLESS_DIR"
    say "[dry-run] Would remove: $LOOKANDFEEL_CACHE"
    say "[dry-run] Would remove: $XINIT"
  else
    [[ -d "$SUCKLESS_DIR" ]]       && rm -rf "$SUCKLESS_DIR"       && ok "Removed $SUCKLESS_DIR"
    [[ -d "$LOOKANDFEEL_CACHE" ]]  && rm -rf "$LOOKANDFEEL_CACHE"  && ok "Removed $LOOKANDFEEL_CACHE"
    [[ -f "$XINIT" ]]              && rm -f  "$XINIT"              && ok "Removed $XINIT"
  fi
  ok "Fresh state ready"
}

# ─────────────────────────────────────────────
# STEP: CORE
# ─────────────────────────────────────────────
step_core() {
  should_run core || { warn "Skipping: core"; return 0; }
  section "CORE — Base system setup"

  # Full system upgrade
  say "Syncing & upgrading system"
  run sudo pacman -Syu --noconfirm

  # Btrfs snapshots (if Btrfs root)
  if findmnt -n -o FSTYPE / 2>/dev/null | grep -q '^btrfs$'; then
    say "Btrfs detected — setting up Snapper"
    run sudo pacman -S --needed --noconfirm snapper snap-pac
    if command -v grub-mkconfig >/dev/null 2>&1; then
      run sudo pacman -S --needed --noconfirm grub-btrfs
    fi
    if [[ ! -d /.snapshots ]]; then
      run sudo snapper -c root create-config /
      run sudo sed -i 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="0"/'   /etc/snapper/configs/root
      run sudo sed -i 's/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="3"/'     /etc/snapper/configs/root
      run sudo sed -i 's/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="1"/'   /etc/snapper/configs/root
      run sudo sed -i 's/^TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="0"/' /etc/snapper/configs/root
      run sudo sed -i 's/^TIMELINE_LIMIT_YEARLY=.*/TIMELINE_LIMIT_YEARLY="0"/'   /etc/snapper/configs/root
    else
      say "Snapper already configured"
    fi
  else
    warn "Root is not Btrfs — skipping Snapper setup"
  fi

  # Services
  say "Enabling NetworkManager and ufw"
  run_shell "sudo systemctl enable --now NetworkManager"
  run_shell "sudo systemctl enable --now ufw || true"
  if command -v ufw >/dev/null 2>&1; then
    run_shell "sudo ufw default deny incoming  || true"
    run_shell "sudo ufw default allow outgoing || true"
    run_shell "sudo ufw enable                 || true"
  fi

  ok "Core done"
}

# ─────────────────────────────────────────────
# STEP: APPS
# ─────────────────────────────────────────────
step_apps() {
  should_run apps || { warn "Skipping: apps"; return 0; }
  section "APPS — Packages (pacman + AUR)"

  say "Installing ${#PACMAN_PKGS[@]} pacman packages"
  run sudo pacman -S --needed --noconfirm "${PACMAN_PKGS[@]}"

  # yay
  if ! command -v yay >/dev/null 2>&1; then
    say "Installing yay (AUR helper)"
    local tmp; tmp="$(mktemp -d)"
    run git clone https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
    (cd "$tmp/yay-bin" && run makepkg -si --noconfirm)
    rm -rf "$tmp"
  else
    say "yay already installed"
  fi

  say "Installing ${#AUR_PKGS[@]} AUR packages"
  run yay -S --needed --noconfirm "${AUR_PKGS[@]}" || true

  # LazyVim bootstrap
  local nvim_dir="$HOME/.config/nvim"
  if command -v nvim >/dev/null 2>&1 && [[ ! -d "$nvim_dir" ]]; then
    say "Bootstrapping LazyVim"
    run git clone --depth=1 https://github.com/LazyVim/starter "$nvim_dir"
    (cd "$nvim_dir" && run rm -rf .git)
    run nvim --headless "+Lazy! sync" +qa || true
  else
    say "Neovim config exists or nvim not found — skipping LazyVim bootstrap"
  fi

  # ~/.bash_profile
  local profile="$HOME/.bash_profile"
  if [[ ! -f "$profile" ]]; then
    cat > "$profile" <<'EOF'
# .bash_profile
[[ -f ~/.bashrc ]] && . ~/.bashrc
EOF
  fi
  grep -qxF 'export EDITOR=nvim' "$profile"  || echo 'export EDITOR=nvim' >> "$profile"
  grep -qxF 'export VISUAL=nvim' "$profile"  || echo 'export VISUAL=nvim' >> "$profile"
  printf '%s' "$PATH" | grep -q "$HOME/.local/bin" || \
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$profile"

  ok "Apps done"
}

# ─────────────────────────────────────────────
# STEP: SUCKLESS
# ─────────────────────────────────────────────
step_suckless() {
  should_run suckless || { warn "Skipping: suckless"; return 0; }
  section "SUCKLESS — dwm, st, dmenu, slock, slstatus"

  ensure_dir "$SUCKLESS_DIR" "$LOCAL_BIN" "$XINITRC_HOOKS"

  clone_or_pull "$SUCKLESS_REPO" "$SUCKLESS_DIR" "main"

  local components=(dwm st dmenu slock slstatus)
  for comp in "${components[@]}"; do
    if [[ -d "$SUCKLESS_DIR/$comp" ]]; then
      say "Building $comp"
      if ((DRY_RUN)); then
        say "[dry-run] make -j$JOBS && sudo make PREFIX=$PREFIX install (in $SUCKLESS_DIR/$comp)"
      else
        (cd "$SUCKLESS_DIR/$comp" && make clean && make -j"$JOBS" && sudo make PREFIX="$PREFIX" install)
        ok "Installed: $comp"
      fi
    else
      warn "$comp not found in $SUCKLESS_DIR — skipping"
    fi
  done

  # Create ~/.xinitrc once (never overwrite)
  ensure_dir "$XINITRC_HOOKS"
  if [[ ! -f "$XINIT" ]]; then
    say "Creating ~/.xinitrc"
    if ! ((DRY_RUN)); then
      cat > "$XINIT" <<'EOF'
#!/bin/sh
# .xinitrc — NIRUCON Suckless Edition
# Created ONCE by alpi-suckless.sh — never modified by install scripts.
# Autostart is managed via hooks in ~/.config/xinitrc.d/

cd "$HOME"

# D-Bus session
if [ -z "${DBUS_SESSION_BUS_ADDRESS-}" ] && command -v dbus-run-session >/dev/null 2>&1; then
  exec dbus-run-session "$0" "$@"
fi

command -v dbus-update-activation-environment >/dev/null 2>&1 && \
  dbus-update-activation-environment --systemd DISPLAY XAUTHORITY

# X resources & keyboard
[ -r "$HOME/.Xresources" ] && xrdb -merge "$HOME/.Xresources"
command -v setxkbmap  >/dev/null 2>&1 && setxkbmap se
command -v xsetroot   >/dev/null 2>&1 && xsetroot -solid "#111111"

# GTK/Qt theming
export XDG_CONFIG_HOME="$HOME/.config"
export GTK_THEME="Adwaita:dark"
export QT_STYLE_OVERRIDE="kvantum"
export QT_QPA_PLATFORMTHEME="qt5ct"
export XCURSOR_THEME="Adwaita"
export GTK2_RC_FILES="$HOME/.gtkrc-2.0"

# Run hooks from ~/.config/xinitrc.d/ (alphabetical order)
if [ -d "$HOME/.config/xinitrc.d" ]; then
  for hook in "$HOME/.config/xinitrc.d"/*.sh; do
    [ -x "$hook" ] && . "$hook"
  done
fi

# DWM restart loop (Mod+Shift+Q restarts, Mod+Shift+E exits)
trap 'kill -- -$$' EXIT
while true; do
  /usr/local/bin/dwm 2>/tmp/dwm.log
done
EOF
      chmod 644 "$XINIT"
      ok "Created ~/.xinitrc"
    fi
  else
    say "~/.xinitrc already exists — leaving untouched"
  fi

  # Suckless xinitrc hook (xautolock + slock)
  if ! ((DRY_RUN)); then
    cat > "$XINITRC_HOOKS/40-suckless.sh" <<'EOF'
#!/bin/sh
# Suckless hook: xautolock screen locker
if command -v xautolock >/dev/null 2>&1 && command -v slock >/dev/null 2>&1; then
  xautolock -time 10 -locker slock &
fi
EOF
    chmod +x "$XINITRC_HOOKS/40-suckless.sh"
  fi

  ok "Suckless done"
}

# ─────────────────────────────────────────────
# STEP: LOOKANDFEEL
# ─────────────────────────────────────────────
step_lookandfeel() {
  should_run lookandfeel || { warn "Skipping: lookandfeel"; return 0; }
  section "LOOKANDFEEL — Configs, themes, dotfiles, scripts"

  clone_or_pull "$LOOKANDFEEL_REPO" "$LOOKANDFEEL_CACHE" "$LOOKANDFEEL_BRANCH"

  # Install using new repo structure
  if [[ -d "$LOOKANDFEEL_CACHE/dotfiles" ]]; then
    say "Installing dotfiles → ~/"
    # Protected: never overwrite .xinitrc or .bash_profile
    while IFS= read -r -d '' f; do
      local base; base="$(basename "$f")"
      local rel="${f#"$LOOKANDFEEL_CACHE/dotfiles/"}"
      if [[ "$base" == ".xinitrc" || "$base" == ".bash_profile" ]]; then
        warn "Protected: $base — skipping (managed separately)"
        continue
      fi
      install_file "$f" "$HOME/$rel" 644
    done < <(find "$LOOKANDFEEL_CACHE/dotfiles" -type f -print0)
  fi

  [[ -d "$LOOKANDFEEL_CACHE/config" ]]       && mirror_tree "$LOOKANDFEEL_CACHE/config"       "$HOME/.config"       644
  [[ -d "$LOOKANDFEEL_CACHE/local/bin" ]]    && mirror_tree "$LOOKANDFEEL_CACHE/local/bin"    "$LOCAL_BIN"         755
  [[ -d "$LOOKANDFEEL_CACHE/local/share" ]]  && mirror_tree "$LOOKANDFEEL_CACHE/local/share"  "$HOME/.local/share"  644

  # Wallpapers
  say "Downloading wallpapers"
  if ! ((DRY_RUN)); then
    ensure_dir "$WALLPAPER_DIR"
    local tmp_zip; tmp_zip="$(mktemp --suffix=.zip)"
    if wget -q -O "$tmp_zip" "$WALLPAPER_URL" 2>/dev/null; then
      unzip -q -o "$tmp_zip" -d "$WALLPAPER_DIR" && ok "Wallpapers extracted to $WALLPAPER_DIR" || warn "Wallpaper extraction failed"
    else
      warn "Wallpaper download failed (non-fatal)"
    fi
    rm -f "$tmp_zip"
  fi

  # Xinitrc hooks
  if ! ((DRY_RUN)); then
    cat > "$XINITRC_HOOKS/10-compositor.sh" <<'EOF'
#!/bin/sh
command -v picom >/dev/null 2>&1 && picom &
EOF
    chmod +x "$XINITRC_HOOKS/10-compositor.sh"

    cat > "$XINITRC_HOOKS/20-wallpaper.sh" <<'EOF'
#!/bin/sh
# Restore last wallpaper set by feh, then start rotation if available
[ -f "$HOME/.fehbg" ] && "$HOME/.fehbg" &
[ -x "$HOME/.local/bin/wallrotate.sh" ] && "$HOME/.local/bin/wallrotate.sh" &
EOF
    chmod +x "$XINITRC_HOOKS/20-wallpaper.sh"

    cat > "$XINITRC_HOOKS/25-notifications.sh" <<'EOF'
#!/bin/sh
command -v dunst >/dev/null 2>&1 && dunst &
EOF
    chmod +x "$XINITRC_HOOKS/25-notifications.sh"

    cat > "$XINITRC_HOOKS/30-lookandfeel.sh" <<'EOF'
#!/bin/sh
# Polkit agent (needed for GUI privilege prompts)
_polkit="/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"
[ -x "$_polkit" ] && "$_polkit" &
EOF
    chmod +x "$XINITRC_HOOKS/30-lookandfeel.sh"

    cat > "$XINITRC_HOOKS/50-nextcloud.sh" <<'EOF'
#!/bin/sh
command -v nextcloud >/dev/null 2>&1 && nextcloud --background &
EOF
    chmod +x "$XINITRC_HOOKS/50-nextcloud.sh"

    ok "Xinitrc hooks written"
  fi

  ok "Lookandfeel done"
}

# ─────────────────────────────────────────────
# STEP: STATUSBAR
# ─────────────────────────────────────────────
step_statusbar() {
  should_run statusbar || { warn "Skipping: statusbar"; return 0; }
  section "STATUSBAR — dwm-status.sh"

  local src="$LOOKANDFEEL_CACHE/local/bin/dwm-status.sh"

  if [[ ! -d "$LOOKANDFEEL_CACHE" ]]; then
    die "Lookandfeel cache not found at $LOOKANDFEEL_CACHE. Run lookandfeel step first."
  fi

  if [[ ! -f "$src" ]]; then
    warn "dwm-status.sh not found in lookandfeel repo at: $src"
    warn "Expected: $LOOKANDFEEL_CACHE/local/bin/dwm-status.sh"
    warn "Skipping statusbar step — add the script to your lookandfeel repo."
    return 0
  fi

  ensure_dir "$LOCAL_BIN" "$XINITRC_HOOKS"

  if ((DRY_RUN)); then
    say "[dry-run] install $src -> $LOCAL_BIN/dwm-status.sh (755)"
  else
    install -Dm755 "$src" "$LOCAL_BIN/dwm-status.sh"
    ok "Installed: dwm-status.sh → $LOCAL_BIN/"

    cat > "$XINITRC_HOOKS/35-statusbar.sh" <<'EOF'
#!/bin/sh
[ -x "$HOME/.local/bin/dwm-status.sh" ] && "$HOME/.local/bin/dwm-status.sh" &
EOF
    chmod +x "$XINITRC_HOOKS/35-statusbar.sh"
    ok "Created xinitrc hook: 35-statusbar.sh"
  fi

  ok "Statusbar done"
}

# ─────────────────────────────────────────────
# STEP: OPTIMIZE
# ─────────────────────────────────────────────
step_optimize() {
  should_run optimize || { warn "Skipping: optimize"; return 0; }
  section "OPTIMIZE — System tuning"

  if ((DRY_RUN)); then
    say "[dry-run] optimize: would run system tuning as root"
    return 0
  fi

  say "Running system tuning as root (sudo)"
  local _cores; _cores="$(nproc)"

  sudo bash -s "$_cores" <<'OPTIMIZE_ROOT'
set -Eeuo pipefail
CORES="$1"

# Microcode
cpu_vendor="$(lscpu | awk -F: '/Vendor ID/{gsub(/^[ \t]+/,"",$2);print $2}')"
case "$cpu_vendor" in
  *Intel*) pacman -S --needed --noconfirm intel-ucode ;;
  *AMD*)   pacman -S --needed --noconfirm amd-ucode   ;;
  *)       echo "[!] Unknown CPU vendor — skipping microcode" ;;
esac
pacman -S --needed --noconfirm linux-firmware

# ZRAM
pacman -S --needed --noconfirm zram-generator
install -dm755 /etc/systemd/zram-generator.conf.d
cat > /etc/systemd/zram-generator.conf.d/90-alpi.conf << 'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
EOF
systemctl enable --now systemd-zram-setup@zram0.service || true

# journald
jconf=/etc/systemd/journald.conf
[[ -f "$jconf.bak" ]] || cp -a "$jconf" "$jconf.bak"
grep -q '^Storage='         "$jconf" && sed -i 's/^Storage=.*/Storage=persistent/'      "$jconf" || echo 'Storage=persistent'   >> "$jconf"
grep -q '^SystemMaxUse='    "$jconf" && sed -i 's/^SystemMaxUse=.*/SystemMaxUse=500M/'   "$jconf" || echo 'SystemMaxUse=500M'    >> "$jconf"
grep -q '^RuntimeMaxUse='   "$jconf" && sed -i 's/^RuntimeMaxUse=.*/RuntimeMaxUse=200M/' "$jconf" || echo 'RuntimeMaxUse=200M'   >> "$jconf"
grep -q '^MaxRetentionSec=' "$jconf" && sed -i 's/^MaxRetentionSec=.*/MaxRetentionSec=1month/' "$jconf" || echo 'MaxRetentionSec=1month' >> "$jconf"
systemctl restart systemd-journald

# sysctl
cat > /etc/sysctl.d/90-alpi.conf << 'EOF'
vm.swappiness = 60
vm.vfs_cache_pressure = 50
fs.inotify.max_user_watches = 1048576
fs.inotify.max_user_instances = 1024
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
EOF
sysctl --system > /dev/null

# pacman.conf
[[ -f /etc/pacman.conf.bak ]] || cp /etc/pacman.conf /etc/pacman.conf.bak
grep -Eq '^[#]*Color$'             /etc/pacman.conf && sed -Ei 's/^[#]*Color$/Color/'                        /etc/pacman.conf || echo 'Color'             >> /etc/pacman.conf
grep -Eq '^[#]*VerbosePkgLists$'   /etc/pacman.conf && sed -Ei 's/^[#]*VerbosePkgLists$/VerbosePkgLists/'   /etc/pacman.conf || echo 'VerbosePkgLists'    >> /etc/pacman.conf
grep -Eq '^[#]*ParallelDownloads'  /etc/pacman.conf \
  && sed -Ei 's/^[#]*ParallelDownloads *= *.*/ParallelDownloads = 10/' /etc/pacman.conf \
  || echo 'ParallelDownloads = 10' >> /etc/pacman.conf

# makepkg
[[ -f /etc/makepkg.conf.bak ]] || cp /etc/makepkg.conf /etc/makepkg.conf.bak
sed -Ei "s|^#?MAKEFLAGS=.*|MAKEFLAGS=\"-j${CORES}\"|"                  /etc/makepkg.conf
sed -Ei 's|^#?COMPRESSXZ=.*|COMPRESSXZ=(xz -c -T0 -z -)|'             /etc/makepkg.conf
sed -Ei 's|^#?COMPRESSZST=.*|COMPRESSZST=(zstd -c -T0 -z -q -19 -)|'  /etc/makepkg.conf

# paccache + fstrim
pacman -S --needed --noconfirm pacman-contrib util-linux
systemctl enable --now paccache.timer
systemctl enable --now fstrim.timer

# systemd-oomd
install -dm755 /etc/systemd/oomd.conf.d
cat > /etc/systemd/oomd.conf.d/90-alpi.conf << 'EOF'
[OOM]
DefaultMemoryPressureDurationSec=2min
DefaultMemoryPressureThreshold=70%
EOF
systemctl enable --now systemd-oomd.service || true

echo "[✓] Root-level system tuning complete"
OPTIMIZE_ROOT

  ok "Optimize done"
}

# ─────────────────────────────────────────────
# STEP: VERIFY
# ─────────────────────────────────────────────
step_verify() {
  should_run verify || { warn "Skipping: verify"; return 0; }
  section "VERIFY — Installation check"

  local failures=0 warnings=0

  chk_cmd() {
    local cmd="$1" label="$2"
    command -v "$cmd" >/dev/null 2>&1 && ok "$label" || { err "$label: NOT FOUND"; ((failures++)); }
  }
  chk_file() {
    local f="$1" label="$2"
    [[ -f "$f" ]] && ok "$label" || { err "$label: NOT FOUND at $f"; ((failures++)); }
  }
  chk_dir() {
    local d="$1" label="$2"
    [[ -d "$d" ]] && ok "$label" || { err "$label: NOT FOUND at $d"; ((failures++)); }
  }
  chk_svc() {
    local svc="$1" label="$2"
    systemctl is-enabled --quiet "$svc" 2>/dev/null && ok "$label" || { warn "$label: not enabled"; ((warnings++)); }
  }
  chk_font() {
    local name="$1" label="$2"
    fc-list | grep -qi "$name" && ok "$label" || { warn "$label: not found"; ((warnings++)); }
  }

  say "Suckless tools"
  chk_cmd dwm     "dwm window manager"
  chk_cmd st      "st terminal"
  chk_cmd dmenu   "dmenu launcher"
  chk_cmd slock   "slock screen locker"
  chk_cmd slstatus "slstatus"

  say "Essential apps"
  chk_cmd git       "git"
  chk_cmd nvim      "neovim"
  chk_cmd rofi      "rofi"
  chk_cmd feh       "feh"
  chk_cmd picom     "picom"
  chk_cmd alacritty "alacritty"
  chk_cmd btop      "btop"
  chk_cmd yazi      "yazi"
  chk_cmd brave     "brave browser"

  say "Config files"
  chk_file "$XINIT"                                      ".xinitrc"
  chk_dir  "$XINITRC_HOOKS"                              "xinitrc.d hooks dir"
  chk_file "$XINITRC_HOOKS/10-compositor.sh"             "hook: compositor"
  chk_file "$XINITRC_HOOKS/20-wallpaper.sh"              "hook: wallpaper"
  chk_file "$XINITRC_HOOKS/25-notifications.sh"          "hook: notifications"
  chk_file "$XINITRC_HOOKS/30-lookandfeel.sh"            "hook: lookandfeel/polkit"
  chk_file "$XINITRC_HOOKS/35-statusbar.sh"              "hook: statusbar"
  chk_file "$XINITRC_HOOKS/40-suckless.sh"               "hook: suckless/xautolock"

  say "Suckless sources"
  chk_dir "$SUCKLESS_DIR"        "suckless source dir"
  chk_dir "$SUCKLESS_DIR/dwm"   "dwm source"
  chk_dir "$SUCKLESS_DIR/st"    "st source"
  chk_dir "$SUCKLESS_DIR/dmenu" "dmenu source"

  say "Scripts"
  chk_file "$LOCAL_BIN/dwm-status.sh"      "dwm-status.sh"

  say "Services"
  chk_svc NetworkManager                  "NetworkManager"
  chk_svc "systemd-zram-setup@zram0"      "ZRAM"
  chk_svc paccache.timer                  "paccache.timer"
  chk_svc fstrim.timer                    "fstrim.timer"

  say "Fonts"
  chk_font "JetBrainsMono Nerd"   "JetBrainsMono Nerd Font"
  chk_font "Symbols Nerd Font"    "Symbols Nerd Font"

  echo
  if ((failures == 0 && warnings == 0)); then
    ok "All checks passed — ready to startx"
  elif ((failures == 0)); then
    warn "Passed with $warnings warning(s) — should work, check warnings above"
  else
    err "FAILED: $failures error(s), $warnings warning(s) — review output above"
    return 1
  fi
}

# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────
echo
printf "${BOLD}${CYN}  alpi-suckless.sh — NIRUCON Suckless Edition${NC}\n"
printf "${CYN}  %-20s %s${NC}\n" "Jobs:"    "$JOBS"
printf "${CYN}  %-20s %s${NC}\n" "Dry-run:" "$DRY_RUN"
printf "${CYN}  %-20s %s${NC}\n" "Fresh:"   "$FRESH"
((${#ONLY_STEPS[@]} > 0)) && printf "${CYN}  %-20s %s${NC}\n" "Only:" "${ONLY_STEPS[*]}"
((${#SKIP_STEPS[@]} > 0)) && printf "${CYN}  %-20s %s${NC}\n" "Skip:" "${SKIP_STEPS[*]}"
echo

do_fresh

for step in "${ALL_STEPS[@]}"; do
  case "$step" in
    core)        step_core        ;;
    apps)        step_apps        ;;
    suckless)    step_suckless    ;;
    lookandfeel) step_lookandfeel ;;
    statusbar)   step_statusbar   ;;
    optimize)    step_optimize    ;;
    verify)      step_verify      ;;
    *)           warn "Unknown step: $step" ;;
  esac
done

echo
ok "All selected steps completed!"
say "Reboot recommended to apply all changes."
say "Start X session with: startx"
echo
