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

echo "==> Exporting iOS Xcode project ($MODE)"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
# Force a rescan so GDExtension libraries are re-detected.
rm -f "$REPO_ROOT/game/.godot/extension_list.cfg"

"$GODOT" --headless --path "$REPO_ROOT/game" "$EXPORT_FLAG" "iOS" "$OUT_DIR/LittleBuddy.ipa"

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
