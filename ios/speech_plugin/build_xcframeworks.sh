#!/usr/bin/env bash
# Rebuilds LittleBuddySpeech for iOS arm64 (device) and packages the
# xcframeworks referenced by littlebuddyspeech.gdextension.
#
# Verified working on: Xcode 27.0, Godot 4.7.2, godot-cpp branch "4.5",
# scons (Library/Python/3.9/bin/scons) 4.11.1, macOS host.
#
# Usage:
#   ./build_xcframeworks.sh
#
# Requires: godot-cpp vendored at ./godot-cpp (see README.md "Setup" for the
# clone command). Produces:
#   bin/liblittle_buddy_speech.ios.debug.xcframework
#   bin/liblittle_buddy_speech.ios.release.xcframework
set -euo pipefail
cd "$(dirname "$0")"

export PATH="$HOME/Library/Python/3.9/bin:$PATH"

if [ ! -d "godot-cpp/gdextension" ]; then
  echo "error: godot-cpp not vendored. Run:" >&2
  echo "  git clone -b 4.5 --depth 1 https://github.com/godotengine/godot-cpp ios/speech_plugin/godot-cpp" >&2
  exit 1
fi

IOS_MIN=15.0

echo "== scons: template_debug =="
scons platform=ios arch=arm64 target=template_debug ios_min_version="$IOS_MIN"

echo "== scons: template_release =="
scons platform=ios arch=arm64 target=template_release ios_min_version="$IOS_MIN"

mkdir -p bin/combined

echo "== libtool: combine godot-cpp + extension code (debug) =="
libtool -static -o bin/combined/liblittle_buddy_speech_combined.ios.template_debug.a \
  bin/liblittle_buddy_speech.ios.template_debug.a \
  godot-cpp/bin/libgodot-cpp.ios.template_debug.arm64.a

echo "== libtool: combine godot-cpp + extension code (release) =="
libtool -static -o bin/combined/liblittle_buddy_speech_combined.ios.template_release.a \
  bin/liblittle_buddy_speech.ios.template_release.a \
  godot-cpp/bin/libgodot-cpp.ios.template_release.arm64.a

echo "== xcodebuild -create-xcframework (debug) =="
rm -rf bin/liblittle_buddy_speech.ios.debug.xcframework
xcodebuild -create-xcframework \
  -library bin/combined/liblittle_buddy_speech_combined.ios.template_debug.a \
  -output bin/liblittle_buddy_speech.ios.debug.xcframework

echo "== xcodebuild -create-xcframework (release) =="
rm -rf bin/liblittle_buddy_speech.ios.release.xcframework
xcodebuild -create-xcframework \
  -library bin/combined/liblittle_buddy_speech_combined.ios.template_release.a \
  -output bin/liblittle_buddy_speech.ios.release.xcframework

echo "Done. Verify with:"
echo "  lipo -info bin/liblittle_buddy_speech.ios.debug.xcframework/ios-arm64/*.a"
