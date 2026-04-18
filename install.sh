#!/usr/bin/env bash
# install.sh — install dfan fan controller daemon and tools
set -euo pipefail

bold='\033[1m' green='\033[1;32m' yellow='\033[1;33m' red='\033[1;31m' reset='\033[0m'

step()  { echo -e "${bold}==> $*${reset}"; }
ok()    { echo -e "${green}    ✓ $*${reset}"; }
warn()  { echo -e "${yellow}    ! $*${reset}"; }
die()   { echo -e "${red}error:${reset} $*" >&2; exit 1; }

[[ "$EUID" -eq 0 ]] || die "must be run as root (sudo ./install.sh)"

PROJ="$(cd "$(dirname "$0")" && pwd)"

# Detect the invoking user's home and shell (works under sudo)
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
REAL_SHELL=$(basename "$(getent passwd "$REAL_USER" | cut -d: -f7)")

add_to_path() {
  local rc_file path_line

  case "$REAL_SHELL" in
    zsh)  rc_file="$REAL_HOME/.zshrc" ;         path_line='export PATH="$PATH:/usr/local/sbin"' ;;
    bash) rc_file="$REAL_HOME/.bashrc" ;         path_line='export PATH="$PATH:/usr/local/sbin"' ;;
    fish) rc_file="$REAL_HOME/.config/fish/config.fish" ; path_line='fish_add_path /usr/local/sbin' ;;
    *)    rc_file="$REAL_HOME/.profile" ;        path_line='export PATH="$PATH:/usr/local/sbin"' ;;
  esac

  if grep -qF '/usr/local/sbin' "$rc_file" 2>/dev/null; then
    ok "/usr/local/sbin already in PATH ($rc_file)"
    return
  fi

  mkdir -p "$(dirname "$rc_file")"
  echo "$path_line" >> "$rc_file"
  chown "$REAL_USER:" "$rc_file"
  ok "Added /usr/local/sbin to PATH in $rc_file"
  warn "Restart your shell or run: source $rc_file"
}

# Check if already installed
if [[ -L /usr/local/sbin/dfan ]] && systemctl is-enabled --quiet dfan.service 2>/dev/null; then
  warn "dfan is already installed and enabled."
  warn "To reinstall, run: sudo ./uninstall.sh && sudo ./install.sh"
  warn "To update symlinks only, re-run install.sh — existing symlinks will be refreshed."
  echo
  systemctl status dfan.service --no-pager -l || true
  exit 0
fi

step "Installing binaries"
mkdir -p /usr/local/sbin
ln -sfn "$PROJ/src/dfan"    /usr/local/sbin/dfan
ln -sfn "$PROJ/src/dfanctl" /usr/local/sbin/dfanctl
chmod +x "$PROJ/src/dfan" "$PROJ/src/dfanctl"
ok "Symlinks: /usr/local/sbin/{dfan,dfanctl} → $PROJ/src/"
add_to_path

step "Installing systemd service"
cp "$PROJ/systemd/dfan.service" /etc/systemd/system/dfan.service
systemctl daemon-reload
ok "/etc/systemd/system/dfan.service"

step "Installing tmpfiles (runtime dir /run/dfan)"
cp "$PROJ/tmpfiles/dfan.conf" /etc/tmpfiles.d/dfan.conf
systemd-tmpfiles --create /etc/tmpfiles.d/dfan.conf
ok "/etc/tmpfiles.d/dfan.conf  (/run/dfan created, mode 1777)"

step "Installing polkit rule (dfanctl without sudo)"
cp "$PROJ/polkit/dfan.rules" /etc/polkit-1/rules.d/50-dfan.rules
ok "/etc/polkit-1/rules.d/50-dfan.rules"

step "Enabling and starting dfan.service"
systemctl enable --now dfan.service
ok "dfan.service enabled and started"

echo
echo -e "${green}Installation complete.${reset}"
echo "  Monitor : journalctl -fu dfan"
echo "  Control : dfanctl --help"
echo "  Stats   : dfanctl stats"
