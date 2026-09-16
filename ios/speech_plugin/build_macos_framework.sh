#!/usr/bin/env bash
# Builds the macOS arm64 variant of LittleBuddySpeech.
#
# This is NOT a shipping target -- the child-facing game only ever runs the
# iOS build (see build_xcframeworks.sh). This macOS build exists solely so
# Godot's macOS *editor* can successfully open littlebuddyspeech.gdextension:
# GDExtensionManager requires a library entry matching the editor's own
# running OS/arch to load an extension at all, and only once loaded does
# Godot's built-in GDExtensionExportPlugin see it and bundle its iOS
# library/dependencies into an iOS export. See README.md "Why a macOS
# build" for the full writeup and the export verification that confirmed
# this.
#
# Usage:
#   ./build_macos_framework.sh
#
# Produces (matching the paths littlebuddyspeech.gdextension expects):
#   bin/liblittle_buddy_speech.macos.template_debug.framework/liblittle_buddy_speech.macos.template_debug
#   bin/liblittle_buddy_speech.macos.template_release.framework/liblittle_buddy_speech.macos.template_release
set -euo pipefail
cd "$(dirname "$0")"

export PATH="$HOME/Library/Python/3.9/bin:$PATH"

if [ ! -d "godot-cpp/gdextension" ]; then
  echo "error: godot-cpp not vendored. Run:" >&2
  echo "  git clone -b 4.5 --depth 1 https://github.com/godotengine/godot-cpp ios/speech_plugin/godot-cpp" >&2
  exit 1
fi

echo "== scons: macos template_debug =="
scons platform=macos arch=arm64 target=template_debug

echo "== scons: macos template_release =="
scons platform=macos arch=arm64 target=template_release

echo "Done. Verify with:"
echo "  file bin/liblittle_buddy_speech.macos.template_debug.framework/liblittle_buddy_speech.macos.template_debug"
echo "  otool -L bin/liblittle_buddy_speech.macos.template_debug.framework/liblittle_buddy_speech.macos.template_debug"
