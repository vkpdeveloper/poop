#!/bin/bash
# release.sh — Build poop.app and package it into a drag-to-install DMG
#
# Usage:
#   chmod +x release.sh
#   ./release.sh
#
# Output: build/Poop.dmg

set -euo pipefail

PROJECT="poop.xcodeproj"
SCHEME="poop"
APP_NAME="poop"
DMG_TITLE="Poop"
BUILD_DIR="$(pwd)/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$DMG_TITLE.dmg"

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${YELLOW}▶ $*${NC}"; }
success() { echo -e "${GREEN}✓ $*${NC}"; }
error()   { echo -e "${RED}✗ $*${NC}"; exit 1; }

# ── Clean ─────────────────────────────────────────────────────────────────────
info "Cleaning previous build..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ── Build ─────────────────────────────────────────────────────────────────────
info "Building $APP_NAME (Release)..."
xcodebuild build \
  -project "$PROJECT" \
  -scheme  "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  | grep -E "^(Build|error:|warning:|CompileSwift|Ld )" || true

[ -d "$APP_PATH" ] || error "Build failed — .app not found at:\n  $APP_PATH"
success "Build succeeded → $APP_PATH"

# ── Sign app bundle (local ad-hoc signing) ───────────────────────────────────
# We intentionally use ad-hoc signing so no Apple Developer account is required.
# This still gives the bundle a stable code signature for Accessibility/TCC checks.
info "Applying local ad-hoc signature..."
codesign --force --deep --sign - --identifier "com.ordinity.poop" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH" > /dev/null
success "App signed (ad-hoc)"

# ── Stage DMG contents ────────────────────────────────────────────────────────
info "Staging DMG contents..."
STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"

cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# ── Create DMG ────────────────────────────────────────────────────────────────
info "Creating DMG..."
hdiutil create \
  -volname  "$DMG_TITLE" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH" \
  > /dev/null

rm -rf "$STAGING"

success "Done!  →  $DMG_PATH"
echo ""
echo "  To install: open the DMG and drag Poop into Applications."
echo "  To run without DMG: open \"$APP_PATH\""
