#!/usr/bin/env bash
# Builds TokenStat.app
# Usage: bash build.sh
set -euo pipefail

APP="TokenStat"
BUNDLE_ID="com.tokenstat.app"
VERSION="1.0.0"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP}.app"

echo "Building ${APP}..."
swift build -c release 2>&1

# Create bundle structure
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP}" "${APP_BUNDLE}/Contents/MacOS/"

# Write Info.plist
cat > "${APP_BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

echo ""
echo "Built: ${APP_BUNDLE}"
echo ""
echo "Run now:   open ${APP_BUNDLE}"
echo "Install:   cp -r ${APP_BUNDLE} /Applications/"
echo ""
echo "First launch: click the progress bar in the menu bar -> Settings..."
echo "and paste your Anthropic API key (sk-ant-...)."
