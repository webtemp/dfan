#!/usr/bin/env bash
# uninstall.sh — remove dfan fan controller daemon and tools
set -euo pipefail

bold='\033[1m' green='\033[1;32m' yellow='\033[1;33m' red='\033[1;31m' reset='\033[0m'

step()    { echo -e "${bold}==> $*${reset}"; }
ok()      { echo -e "${green}    ✓ $*${reset}"; }
skipped() { echo -e "${yellow}    - $* (not found, skipping)${reset}"; }
die()     { echo -e "${red}error:${reset} $*" >&2; exit 1; }

[[ "$EUID" -eq 0 ]] || die "must be run as root (sudo ./uninstall.sh)"

step "Stopping and disabling dfan.service"
if systemctl is-active --quiet dfan.service; then
  systemctl disable --now dfan.service
  ok "dfan.service stopped and disabled"
else
  systemctl disable dfan.service 2>/dev/null || true
  skipped "dfan.service was not running"
fi

step "Removing binaries"
for f in /usr/local/sbin/dfan /usr/local/sbin/dfanctl; do
  if [[ -L "$f" || -f "$f" ]]; then
    rm -f "$f" && ok "$f"
  else
    skipped "$f"
  fi
done

step "Removing systemd service"
if [[ -f /etc/systemd/system/dfan.service ]]; then
  rm -f /etc/systemd/system/dfan.service
  systemctl daemon-reload
  ok "/etc/systemd/system/dfan.service"
else
  skipped "/etc/systemd/system/dfan.service"
fi

step "Removing tmpfiles config"
if [[ -f /etc/tmpfiles.d/dfan.conf ]]; then
  rm -f /etc/tmpfiles.d/dfan.conf
  rm -rf /run/dfan
  ok "/etc/tmpfiles.d/dfan.conf  (/run/dfan removed)"
else
  skipped "/etc/tmpfiles.d/dfan.conf"
fi

step "Removing polkit rule"
if [[ -f /etc/polkit-1/rules.d/50-dfan.rules ]]; then
  rm -f /etc/polkit-1/rules.d/50-dfan.rules
  ok "/etc/polkit-1/rules.d/50-dfan.rules"
else
  skipped "/etc/polkit-1/rules.d/50-dfan.rules"
fi

echo
echo -e "${green}Uninstall complete. Fan control returned to hardware AUTO mode.${reset}"
