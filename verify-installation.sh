#!/usr/bin/env bash
# verify-installation.sh — Check if alpi-suckless installed correctly
# Run this after installation to verify everything works

set -u

GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
NC="\033[0m"

pass() { printf "${GREEN}✓${NC} %s\n" "$*"; }
fail() { printf "${RED}✗${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}⚠${NC} %s\n" "$*"; }
info() { printf "${BLUE}ℹ${NC} %s\n" "$*"; }

FAILURES=0
WARNINGS=0

check_cmd() {
  local cmd="$1" desc="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "$desc: $(command -v "$cmd")"
  else
    fail "$desc: NOT FOUND"
    ((FAILURES++))
  fi
}

check_file() {
  local file="$1" desc="$2"
  if [[ -f "$file" ]]; then
    pass "$desc: $file"
  else
    fail "$desc: NOT FOUND"
    ((FAILURES++))
  fi
}

check_dir() {
  local dir="$1" desc="$2"
  if [[ -d "$dir" ]]; then
    pass "$desc: $dir"
  else
    fail "$desc: NOT FOUND"
    ((FAILURES++))
  fi
}

check_service() {
  local svc="$1" desc="$2"
  if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
    pass "$desc: enabled"
  else
    warn "$desc: not enabled (may be normal)"
    ((WARNINGS++))
  fi
}

echo "========================================"
echo "  ALPI-SUCKLESS Installation Verification"
echo "========================================"
echo

info "Checking suckless tools..."
check_cmd dwm "DWM window manager"
check_cmd st "ST terminal"
check_cmd dmenu "Dmenu launcher"
check_cmd slock "Slock screen locker"
check_cmd slstatus "Slstatus (if installed)"

echo
info "Checking essential tools..."
check_cmd git "Git"
check_cmd make "Make"
check_cmd gcc "GCC compiler"
check_cmd picom "Picom compositor"
check_cmd rofi "Rofi launcher"
check_cmd feh "Feh image viewer"
check_cmd alacritty "Alacritty terminal"
check_cmd nvim "Neovim"

echo
info "Checking configuration files..."
check_file "$HOME/.xinitrc" ".xinitrc"
check_dir "$HOME/.config/xinitrc.d" "Xinitrc hooks directory"
check_file "$HOME/.config/xinitrc.d/20-lookandfeel.sh" "Look&feel hook"
check_file "$HOME/.config/xinitrc.d/30-statusbar.sh" "Status bar hook"
check_file "$HOME/.config/xinitrc.d/40-suckless.sh" "Suckless hook"

echo
info "Checking suckless sources..."
check_dir "$HOME/.config/suckless" "Suckless source directory"
check_dir "$HOME/.config/suckless/dwm" "DWM source"
check_dir "$HOME/.config/suckless/st" "ST source"
check_dir "$HOME/.config/suckless/dmenu" "Dmenu source"

echo
info "Checking dotfiles..."
check_file "$HOME/.config/alacritty/alacritty.yml" "Alacritty config"
check_file "$HOME/.config/rofi/config.rasi" "Rofi config"
check_file "$HOME/.config/picom/picom.conf" "Picom config"
check_file "$HOME/.config/dunst/dunstrc" "Dunst config"

echo
info "Checking scripts..."
check_file "$HOME/.local/bin/dwm-status.sh" "Status bar script"
check_file "$HOME/.local/bin/wallrotate.sh" "Wallpaper rotation"
check_file "$HOME/.local/bin/screenshot-select.sh" "Screenshot tool"

echo
info "Checking system services..."
check_service NetworkManager "NetworkManager"
check_service "systemd-zram-setup@zram0" "ZRAM"
check_service paccache.timer "Pacman cache cleanup"
check_service fstrim.timer "SSD trim"

echo
info "Checking fonts..."
if fc-list | grep -qi "JetBrainsMono Nerd"; then
  pass "JetBrainsMono Nerd Font: installed"
else
  warn "JetBrainsMono Nerd Font: not found (may cause icon issues)"
  ((WARNINGS++))
fi

if fc-list | grep -qi "Symbols Nerd Font"; then
  pass "Symbols Nerd Font: installed"
else
  warn "Symbols Nerd Font: not found (may cause icon issues)"
  ((WARNINGS++))
fi

echo
echo "========================================"
if ((FAILURES == 0 && WARNINGS == 0)); then
  pass "Installation verification PASSED! All checks OK."
  echo
  info "You can now start X with: startx"
elif ((FAILURES == 0)); then
  warn "Installation verification passed with $WARNINGS warning(s)."
  warn "System should work, but check warnings above."
  echo
  info "You can now start X with: startx"
else
  fail "Installation verification FAILED with $FAILURES error(s) and $WARNINGS warning(s)."
  echo
  info "Review errors above and re-run installation if needed."
  exit 1
fi
echo "========================================"
