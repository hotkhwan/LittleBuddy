#!/usr/bin/env bash
# Rebuilds LittleBuddySpeech for iOS arm64 (device) AND iOS Simulator
# (arm64 + x86_64, lipo'd into one universal simulator slice), and packages
# both platform slices into the xcframeworks referenced by
# littlebuddyspeech.gdextension.
#
# Verified working on: Xcode 27.0, Godot 4.7.2, godot-cpp branch "4.5",
# scons (Library/Python/3.9/bin/scons) 4.11.1, macOS host (Apple Silicon).
#
# Usage:
#   ./build_xcframeworks.sh
#
# Requires: godot-cpp vendored at ./godot-cpp (see README.md "Setup" for the
# clone command). Produces xcframeworks with TWO platform slices each:
#   ios-arm64             (device)
#   ios-arm64_x86_64-simulator   (Simulator, universal arm64+x86_64)
#   bin/liblittle_buddy_speech.ios.debug.xcframework
#   bin/liblittle_buddy_speech.ios.release.xcframework
#
# WHY BOTH arm64 AND x86_64 FOR THE SIMULATOR (not "arm64 only, this host is
# Apple Silicon"): the official Godot 4.7.2 export templates' own
# `libgodot.ios.debug.xcframework` bundles a simulator slice named
# `ios-arm64_x86_64-simulator` that is, in this template package, actually
# x86_64-ONLY (`lipo -info` on it reports "Non-fat file ... architecture:
# x86_64", not a real universal binary). An arm64-only simulator build of
# *our* plugin would silently fail to link against that (all of libgodot.a's
# objects get skipped as "wrong architecture", so even unrelated symbols
# like `_main` go missing). Building x86_64 too and lipo-ing it together
# with our arm64 slice into one universal `.a` (matching Godot's own
# platform-variant identifier exactly) makes the app linkable and bootable
# in the Simulator on this Apple Silicon host via Rosetta 2 today, AND keeps
# native arm64 simulator support ready for whenever Godot ships a template
# with a real universal (or arm64-only) simulator slice.
set -euo pipefail
cd "$(dirname "$0")"

export PATH="$HOME/Library/Python/3.9/bin:$PATH"

if [ ! -d "godot-cpp/gdextension" ]; then
  echo "error: godot-cpp not vendored. Run:" >&2
  echo "  git clone -b 4.5 --depth 1 https://github.com/godotengine/godot-cpp ios/speech_plugin/godot-cpp" >&2
  exit 1
fi

IOS_MIN=15.0

echo "== scons: template_debug (device, arm64) =="
scons platform=ios arch=arm64 target=template_debug ios_min_version="$IOS_MIN"

echo "== scons: template_release (device, arm64) =="
scons platform=ios arch=arm64 target=template_release ios_min_version="$IOS_MIN"

echo "== scons: template_debug (simulator, arm64) =="
scons platform=ios arch=arm64 target=template_debug ios_min_version="$IOS_MIN" ios_simulator=yes

echo "== scons: template_release (simulator, arm64) =="
scons platform=ios arch=arm64 target=template_release ios_min_version="$IOS_MIN" ios_simulator=yes

echo "== scons: template_debug (simulator, x86_64) =="
scons platform=ios arch=x86_64 target=template_debug ios_min_version="$IOS_MIN" ios_simulator=yes

echo "== scons: template_release (simulator, x86_64) =="
scons platform=ios arch=x86_64 target=template_release ios_min_version="$IOS_MIN" ios_simulator=yes

mkdir -p bin/combined

echo "== libtool: combine godot-cpp + extension code (debug, device arm64) =="
libtool -static -o bin/combined/liblittle_buddy_speech_combined.ios.template_debug.arm64.a \
  bin/liblittle_buddy_speech.ios.template_debug.arm64.a \
  godot-cpp/bin/libgodot-cpp.ios.template_debug.arm64.a

echo "== libtool: combine godot-cpp + extension code (release, device arm64) =="
libtool -static -o bin/combined/liblittle_buddy_speech_combined.ios.template_release.arm64.a \
  bin/liblittle_buddy_speech.ios.template_release.arm64.a \
  godot-cpp/bin/libgodot-cpp.ios.template_release.arm64.a

echo "== libtool: combine godot-cpp + extension code (debug, simulator arm64) =="
libtool -static -o bin/combined/liblittle_buddy_speech_combined.ios.template_debug.arm64.simulator.a \
  bin/liblittle_buddy_speech.ios.template_debug.arm64.simulator.a \
  godot-cpp/bin/libgodot-cpp.ios.template_debug.arm64.simulator.a

echo "== libtool: combine godot-cpp + extension code (release, simulator arm64) =="
libtool -static -o bin/combined/liblittle_buddy_speech_combined.ios.template_release.arm64.simulator.a \
  bin/liblittle_buddy_speech.ios.template_release.arm64.simulator.a \
  godot-cpp/bin/libgodot-cpp.ios.template_release.arm64.simulator.a

echo "== libtool: combine godot-cpp + extension code (debug, simulator x86_64) =="
libtool -static -o bin/combined/liblittle_buddy_speech_combined.ios.template_debug.x86_64.simulator.a \
  bin/liblittle_buddy_speech.ios.template_debug.x86_64.simulator.a \
  godot-cpp/bin/libgodot-cpp.ios.template_debug.x86_64.simulator.a

echo "== libtool: combine godot-cpp + extension code (release, simulator x86_64) =="
libtool -static -o bin/combined/liblittle_buddy_speech_combined.ios.template_release.x86_64.simulator.a \
  bin/liblittle_buddy_speech.ios.template_release.x86_64.simulator.a \
  godot-cpp/bin/libgodot-cpp.ios.template_release.x86_64.simulator.a

echo "== lipo: merge arm64+x86_64 simulator archives into one universal slice (debug) =="
lipo -create \
  bin/combined/liblittle_buddy_speech_combined.ios.template_debug.arm64.simulator.a \
  bin/combined/liblittle_buddy_speech_combined.ios.template_debug.x86_64.simulator.a \
  -output bin/combined/liblittle_buddy_speech_combined.ios.template_debug.universal.simulator.a

echo "== lipo: merge arm64+x86_64 simulator archives into one universal slice (release) =="
lipo -create \
  bin/combined/liblittle_buddy_speech_combined.ios.template_release.arm64.simulator.a \
  bin/combined/liblittle_buddy_speech_combined.ios.template_release.x86_64.simulator.a \
  -output bin/combined/liblittle_buddy_speech_combined.ios.template_release.universal.simulator.a

echo "== xcodebuild -create-xcframework (debug: device + universal simulator) =="
rm -rf bin/liblittle_buddy_speech.ios.debug.xcframework
xcodebuild -create-xcframework \
  -library bin/combined/liblittle_buddy_speech_combined.ios.template_debug.arm64.a \
  -library bin/combined/liblittle_buddy_speech_combined.ios.template_debug.universal.simulator.a \
  -output bin/liblittle_buddy_speech.ios.debug.xcframework

echo "== xcodebuild -create-xcframework (release: device + universal simulator) =="
rm -rf bin/liblittle_buddy_speech.ios.release.xcframework
xcodebuild -create-xcframework \
  -library bin/combined/liblittle_buddy_speech_combined.ios.template_release.arm64.a \
  -library bin/combined/liblittle_buddy_speech_combined.ios.template_release.universal.simulator.a \
  -output bin/liblittle_buddy_speech.ios.release.xcframework

echo "Done. Verify with:"
echo "  lipo -info bin/liblittle_buddy_speech.ios.debug.xcframework/ios-arm64/*.a"
echo "  lipo -info bin/liblittle_buddy_speech.ios.debug.xcframework/ios-arm64_x86_64-simulator/*.a"
