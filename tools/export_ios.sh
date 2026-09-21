#!/bin/bash
# Export Little Buddy to an Xcode project and strip Info.plist keys the app does not use.
#
# Why the strip step exists:
#   Godot's iOS export template hardcodes NSCameraUsageDescription and
#   NSPhotoLibraryUsageDescription in godot_apple_embedded-Info.plist as
#   "$camera_usage_description" / "$photolibrary_usage_description" placeholders.
#   They are emitted on EVERY export regardless of the preset, so removing the
#   privacy/* options from export_presets.cfg does not remove the keys -- it only
#   leaves them empty, which Xcode then warns about:
#       warning: The value for NSCameraUsageDescription must be a non-empty string.
#   Little Buddy uses neither the camera nor the photo library, and filling them in
#   with dummy text would be a false privacy declaration. So they are deleted here.
#
#   Re-run this script instead of calling Godot's --export-debug directly, or the
#   keys come back.
#
# Usage: tools/export_ios.sh [debug|release]      (default: debug)

set -euo pipefail

MODE="${1:-debug}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
OUT_DIR="$REPO_ROOT/build/ios"
PLIST="$OUT_DIR/LittleBuddy/LittleBuddy-Info.plist"

case "$MODE" in
	debug)   EXPORT_FLAG="--export-debug" ;;
	release) EXPORT_FLAG="--export-release" ;;
	*) echo "usage: $0 [debug|release]" >&2; exit 2 ;;
esac

[ -x "$GODOT" ] || { echo "Godot not found at $GODOT" >&2; exit 1; }

# ---- Preflight: the native speech plugin must be loadable, or the export
# silently ships an app that dies in dyld at launch ("Symbol not found:
# _little_buddy_speech_library_init"). Seen 2026-09-21: a stray symlink named
# `bin` committed in 1af02bb replaced the real folder with a self-loop.
PLUGIN_BIN="$REPO_ROOT/game/ios/speech_plugin/bin"
if [ -L "$PLUGIN_BIN" ]; then
	echo "PREFLIGHT FAIL: $PLUGIN_BIN is a symlink (it must be the real folder). Restore it with:" >&2
	echo "  rm $PLUGIN_BIN && mkdir -p $PLUGIN_BIN && cp -R ios/speech_plugin/bin/liblittle_buddy_speech.{ios.debug,ios.release}.xcframework ios/speech_plugin/bin/liblittle_buddy_speech.macos.template_{debug,release}.framework $PLUGIN_BIN/" >&2
	exit 1
fi
if git -C "$REPO_ROOT" ls-files --error-unmatch game/ios/speech_plugin/bin >/dev/null 2>&1; then
	echo "PREFLIGHT FAIL: game/ios/speech_plugin/bin is tracked by git; it must stay ignored (git rm --cached it)." >&2
	exit 1
fi
for FW in liblittle_buddy_speech.ios.debug.xcframework liblittle_buddy_speech.ios.release.xcframework liblittle_buddy_speech.macos.template_debug.framework; do
	[ -e "$PLUGIN_BIN/$FW/Info.plist" ] || [ -e "$PLUGIN_BIN/$FW/Resources/Info.plist" ] || [ -d "$PLUGIN_BIN/$FW" ] || {
		echo "PREFLIGHT FAIL: $PLUGIN_BIN/$FW is missing. Rebuild with ios/speech_plugin/build_xcframeworks.sh (and build_macos_framework.sh) or copy from ios/speech_plugin/bin." >&2
		exit 1
	}
done
lipo -info "$PLUGIN_BIN"/liblittle_buddy_speech.ios.debug.xcframework/ios-arm64/*.a 2>/dev/null | grep -q arm64 || {
	echo "PREFLIGHT FAIL: the iOS debug plugin slice is not arm64." >&2; exit 1; }
echo "==> Preflight: speech plugin binaries present (real folder, untracked, arm64)"

echo "==> Exporting iOS Xcode project ($MODE)"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
# Force a rescan so GDExtension libraries are re-detected.
rm -f "$REPO_ROOT/game/.godot/extension_list.cfg"

EXPORT_LOG="$REPO_ROOT/build/ios_export.log"
"$GODOT" --headless --path "$REPO_ROOT/game" "$EXPORT_FLAG" "iOS" "$OUT_DIR/LittleBuddy.ipa" 2>&1 | tee "$EXPORT_LOG"

# ---- Post-export: the exporter must have loaded and bundled the extension.
if grep -q "Can't open GDExtension" "$EXPORT_LOG"; then
	echo "EXPORT FAIL: Godot could not open the speech GDExtension during export; the app would abort in dyld at launch. See $EXPORT_LOG." >&2
	exit 1
fi
grep -q "little_buddy_speech" "$OUT_DIR/LittleBuddy.xcodeproj/project.pbxproj" || {
	echo "EXPORT FAIL: the Xcode project does not reference the speech plugin library." >&2; exit 1; }
echo "==> Post-export: speech plugin bundled into the Xcode project"

[ -f "$PLIST" ] || { echo "Expected Info.plist not found at $PLIST" >&2; exit 1; }

echo "==> Removing unused privacy keys from Info.plist"
for KEY in NSCameraUsageDescription NSPhotoLibraryUsageDescription; do
	if /usr/libexec/PlistBuddy -c "Print :$KEY" "$PLIST" >/dev/null 2>&1; then
		/usr/libexec/PlistBuddy -c "Delete :$KEY" "$PLIST"
		echo "    removed $KEY"
	fi
done

echo "==> Privacy keys now declared:"
/usr/libexec/PlistBuddy -c "Print" "$PLIST" | grep -E 'UsageDescription' || echo "    (none)"

echo "==> Done: $OUT_DIR/LittleBuddy.xcodeproj"
