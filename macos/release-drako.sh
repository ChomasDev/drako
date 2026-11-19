#!/bin/sh
# Builds Drako in Release, signs it with Developer ID, packs a DMG,
# notarizes it with Apple and staples the ticket. Output: build/Release/Drako.dmg
#
# One-time setup (stores the notary credentials in the login keychain):
#   xcrun notarytool store-credentials drako --apple-id <apple id> --team-id 88W5BB6R94
#
# DRAKO_VERSION (e.g. 0.2.0) and DRAKO_BUILD (a number that only grows, which
# Sparkle compares) stamp the app; the release workflow sets both from the tag.
set -eu

IDENTITY="${DRAKO_SIGN_IDENTITY:-Developer ID Application: Thomas Favero (88W5BB6R94)}"
cd "$(dirname "$0")"
APP=build/Release/Drako.app
DMG=build/Release/Drako.dmg
STAGE=build/Release/dmg

xcodebuild -target Ghostty -configuration Release -quiet

if [ -n "${DRAKO_VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $DRAKO_VERSION" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${DRAKO_BUILD:?}" "$APP/Contents/Info.plist"
fi

sign() { codesign --force --timestamp --options runtime --sign "$IDENTITY" "$@"; }

# Nested code first, the app last (same order as the upstream release workflow).
SPARKLE=$APP/Contents/Frameworks/Sparkle.framework/Versions/B
sign "$SPARKLE/XPCServices/Downloader.xpc"
sign "$SPARKLE/XPCServices/Installer.xpc"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign "$APP/Contents/PlugIns/DockTilePlugin.plugin"
sign --entitlements Ghostty.entitlements "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname Drako -srcfolder "$STAGE" -format UDZO "$DMG"
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

xcrun notarytool submit "$DMG" --keychain-profile drako --wait
xcrun stapler staple "$DMG"
xcrun stapler staple "$APP"
spctl --assess --type open --context context:primary-signature -vv "$DMG"
spctl --assess --type execute -vv "$APP"
