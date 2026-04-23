#!/usr/bin/env bash
# Builds TokenStat for Ubuntu/Linux and installs to ~/.local/bin
#
# Prerequisites (run once):
#   sudo apt install libgtk-3-dev libayatana-appindicator3-dev libsecret-tools swift
#
# Usage:
#   bash build.sh

set -euo pipefail

APP="TokenStat"
BUILD_DIR=".build/release"
INSTALL_DIR="${HOME}/.local/bin"

echo "Building ${APP} for Linux…"
swift build -c release

mkdir -p "${INSTALL_DIR}"
cp "${BUILD_DIR}/${APP}" "${INSTALL_DIR}/${APP}"

echo ""
echo "Installed: ${INSTALL_DIR}/${APP}"
echo ""
echo "Run now:   ${APP}"
echo ""
echo "To auto-start at login, create ~/.config/autostart/tokenstat.desktop:"
cat <<DESKTOP
[Desktop Entry]
Type=Application
Name=TokenStat
Exec=${INSTALL_DIR}/${APP}
StartupNotify=false
X-GNOME-Autostart-enabled=true
DESKTOP
echo ""
echo "Make sure Claude Code is installed and you are logged in"
echo "so that credentials are available in the GNOME keyring."
