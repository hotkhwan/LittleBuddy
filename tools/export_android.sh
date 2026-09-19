#!/bin/bash
# Export Little Buddy to an Android APK.
#
# ## Status
#
# 2026-09-19: this now WORKS. The toolchain was installed and the export branch
# has actually run -- build/android/LittleDays-debug.apk, 36.4 MB, signed, with
# ZERO declared permissions. Before that date the script had never produced an
# APK and only ever printed its blocking list.
#
# It still fails loudly and usefully on a machine that is missing a piece: it
# collects EVERY missing prerequisite rather than dying on the first, and prints
# a numbered list with copy-pasteable commands instead of dying inside Gradle
# with a stack trace. See `docs/ANDROID_READINESS.md` for the same list in prose.
#
# Everything the toolchain needs installs WITHOUT sudo, into the user's home
# directory. That is worth knowing: the obvious `brew install --cask temurin@17`
# route needs an admin password, and a plain tarball unpacked into
# ~/Library/Java/JavaVirtualMachines/ does not -- `/usr/libexec/java_home`
# discovers it there just the same (verified).
#
# ## Why every check is here
#
# Godot's Android exporter needs FIVE separate things, and it reports a missing
# one as a one-line editor error that is easy to mistake for a project problem:
#
#   1. the Android export templates (android_debug.apk / android_release.apk)
#   2. a JDK -- Godot 4.7.2's build template requires Java 17
#   3. the Android SDK, with build-tools containing `apksigner`
#   4. a debug keystore (Godot can generate one, but only once it has a JDK)
#   5. an "Android" preset in game/export_presets.cfg
#
# and the NDK only if gradle_build/use_gradle_build is turned on. That last
# distinction matters: a plain APK export from the prebuilt template needs NO
# NDK at all, so this script warns about the NDK rather than refusing to run.
#
# Usage:
#   tools/export_android.sh [debug|release]   (default: debug)
#   tools/export_android.sh debug --install   (also `adb install -r` the result)
#   tools/export_android.sh --check           (run the checks, export nothing)

set -uo pipefail

MODE="debug"
DO_INSTALL=0
CHECK_ONLY=0
for ARG in "$@"; do
	case "$ARG" in
		debug|release) MODE="$ARG" ;;
		--install)     DO_INSTALL=1 ;;
		--check)       CHECK_ONLY=1 ;;
		-h|--help)
			echo "usage: $0 [debug|release] [--install] [--check]"
			exit 0 ;;
		*) echo "unknown argument: $ARG" >&2
		   echo "usage: $0 [debug|release] [--install] [--check]" >&2
		   exit 2 ;;
	esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME_DIR="$REPO_ROOT/game"
PRESETS="$GAME_DIR/export_presets.cfg"
PRESET_NAME="Android"
OUT_DIR="$REPO_ROOT/build/android"
# Mode-suffixed on purpose. A debug and a release APK are NOT interchangeable
# (the debug one is signed with a throwaway key and is android:debuggable), and
# a single filename lets one silently overwrite the other.
OUT_APK="$OUT_DIR/LittleDays-$MODE.apk"

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
if [ ! -x "$GODOT" ]; then
	FALLBACK="$(command -v godot 2>/dev/null || true)"
	[ -n "$FALLBACK" ] && GODOT="$FALLBACK"
fi

# Versions pinned by the Godot 4.7.2 Android build template (config.gradle):
#   compileSdk 36 | minSdk 24 | targetSdk 36 | buildTools 36.1.0
#   javaVersion 17 | ndkVersion 29.0.14206865 | AGP 8.6.1
REQUIRED_JAVA_MAJOR=17
REQUIRED_NDK="29.0.14206865"
REQUIRED_BUILD_TOOLS="36.1.0"

EDITOR_SUPPORT="$HOME/Library/Application Support/Godot"
case "$(uname -s)" in
	Linux) EDITOR_SUPPORT="${XDG_DATA_HOME:-$HOME/.local/share}/godot" ;;
esac

BLOCKERS=()
WARNINGS=()

blocker() { BLOCKERS+=("$1"); }
warn()    { WARNINGS+=("$1"); }
ok()      { printf '  \033[32mok\033[0m    %s\n' "$1"; }
bad()     { printf '  \033[31mMISSING\033[0m %s\n' "$1"; }
note()    { printf '  \033[33mwarn\033[0m  %s\n' "$1"; }

echo "==> Little Buddy Android export preflight ($MODE)"
echo ""

# -- 1. Godot editor binary ----------------------------------------------------

GODOT_VERSION=""
if [ -x "$GODOT" ]; then
	GODOT_VERSION="$("$GODOT" --version 2>/dev/null | tail -1 | tr -d '\r')"
	ok "Godot: $GODOT ($GODOT_VERSION)"
else
	bad "Godot editor binary"
	blocker "Godot editor not found. Install Godot 4.7.2 (the standard build, NOT
     the .NET build) to /Applications/Godot.app, or set GODOT=/path/to/godot:
         brew install --cask godot
     Godot's own export templates are what build the APK, so the editor binary
     is required even though nothing is exported by hand."
fi

# -- 2. Android export templates ----------------------------------------------

TEMPLATE_DIR=""
if [ -n "$GODOT_VERSION" ]; then
	# "4.7.2.stable.official.ed1daf0bf" -> "4.7.2.stable"
	TEMPLATE_VERSION="$(printf '%s' "$GODOT_VERSION" | cut -d. -f1-4)"
	TEMPLATE_DIR="$EDITOR_SUPPORT/export_templates/$TEMPLATE_VERSION"
fi
if [ -n "$TEMPLATE_DIR" ] \
		&& [ -f "$TEMPLATE_DIR/android_${MODE}.apk" ] \
		&& [ -f "$TEMPLATE_DIR/android_source.zip" ]; then
	ok "export templates: $TEMPLATE_DIR (android_${MODE}.apk present)"
else
	bad "Android export templates for $GODOT_VERSION"
	blocker "Android export templates missing (expected android_${MODE}.apk in
       ${TEMPLATE_DIR:-<editor data dir>}/).
     Install them from the editor -- Editor > Manage Export Templates >
     Download and Install -- or drop the matching .tpz there by hand. The
     version string must match the editor EXACTLY; a 4.7.1 template will not
     satisfy a 4.7.2 editor."
fi

# -- 3. JDK 17 -----------------------------------------------------------------

JAVA_BIN=""
if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
	JAVA_BIN="$JAVA_HOME/bin/java"
elif command -v /usr/libexec/java_home >/dev/null 2>&1 \
		&& DETECTED_HOME="$(/usr/libexec/java_home -v "$REQUIRED_JAVA_MAJOR" 2>/dev/null)" \
		&& [ -x "$DETECTED_HOME/bin/java" ]; then
	JAVA_BIN="$DETECTED_HOME/bin/java"
	JAVA_HOME="$DETECTED_HOME"
elif command -v java >/dev/null 2>&1 && java -version >/dev/null 2>&1; then
	JAVA_BIN="$(command -v java)"
fi

if [ -n "$JAVA_BIN" ]; then
	JAVA_VERSION_LINE="$("$JAVA_BIN" -version 2>&1 | head -1)"
	JAVA_MAJOR="$(printf '%s' "$JAVA_VERSION_LINE" \
		| sed -n 's/.*version "\([0-9][0-9]*\).*/\1/p')"
	if [ -n "$JAVA_MAJOR" ] && [ "$JAVA_MAJOR" -ge "$REQUIRED_JAVA_MAJOR" ] 2>/dev/null; then
		ok "JDK: $JAVA_BIN (major $JAVA_MAJOR, need >= $REQUIRED_JAVA_MAJOR)"
	else
		bad "JDK $REQUIRED_JAVA_MAJOR+ (found: $JAVA_VERSION_LINE)"
		blocker "JDK too old. Godot 4.7.2's Android build template requires Java
     $REQUIRED_JAVA_MAJOR (config.gradle: javaVersion JavaVersion.VERSION_17):
         brew install --cask temurin@17
         export JAVA_HOME=\"\$(/usr/libexec/java_home -v $REQUIRED_JAVA_MAJOR)\""
	fi
else
	bad "JDK (no working java on PATH; macOS ships a stub that only prints an ad)"
	blocker "No JDK. Install Temurin $REQUIRED_JAVA_MAJOR and export JAVA_HOME:
         brew install --cask temurin@$REQUIRED_JAVA_MAJOR
         export JAVA_HOME=\"\$(/usr/libexec/java_home -v $REQUIRED_JAVA_MAJOR)\"
         echo 'export JAVA_HOME=\"\$(/usr/libexec/java_home -v $REQUIRED_JAVA_MAJOR)\"' >> ~/.zshrc
     Godot ALSO needs this path in its own Editor Settings (see below) -- the
     shell environment alone is not enough, because the editor is launched from
     Finder and never reads your ~/.zshrc."
fi

# -- 4. Android SDK ------------------------------------------------------------

SDK_DIR="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
if [ -d "$SDK_DIR/platforms" ] || [ -d "$SDK_DIR/build-tools" ]; then
	ok "Android SDK: $SDK_DIR"

	APKSIGNER="$(find "$SDK_DIR/build-tools" -name apksigner -type f 2>/dev/null | sort | tail -1)"
	if [ -n "$APKSIGNER" ]; then
		ok "apksigner: $APKSIGNER"
	else
		bad "build-tools/*/apksigner"
		blocker "Android SDK has no build-tools with apksigner. Godot signs the APK
     with it and refuses to export without it:
         sdkmanager 'build-tools;$REQUIRED_BUILD_TOOLS'"
	fi

	if [ -d "$SDK_DIR/platforms/android-36" ]; then
		ok "platform: android-36 (compileSdk 36)"
	else
		bad "platforms/android-36"
		blocker "SDK platform 36 missing (Godot 4.7.2 compiles against it):
         sdkmanager 'platforms;android-36'"
	fi

	if [ -d "$SDK_DIR/ndk/$REQUIRED_NDK" ]; then
		ok "NDK: $REQUIRED_NDK"
	else
		note "NDK $REQUIRED_NDK not installed"
		warn "NDK $REQUIRED_NDK is absent. This is NOT a blocker for a plain APK
     export from the prebuilt template, which ships its own native libraries.
     It IS required the moment you turn on gradle_build/use_gradle_build (for a
     custom build or an Android plugin -- e.g. an Android speech plugin):
         sdkmanager 'ndk;$REQUIRED_NDK'"
	fi
else
	bad "Android SDK (looked in $SDK_DIR)"
	blocker "No Android SDK. Install the command-line tools and the packages
     Godot 4.7.2 needs:
         brew install --cask android-commandlinetools
         export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
         sdkmanager --licenses
         sdkmanager 'platform-tools' 'platforms;android-36' \\
                    'build-tools;$REQUIRED_BUILD_TOOLS' 'cmdline-tools;latest'
     (Android Studio also installs all of this, to ~/Library/Android/sdk.)"
fi

# -- 5. Debug keystore ---------------------------------------------------------

KEYSTORE_CANDIDATES=(
	"$EDITOR_SUPPORT/keystores/debug.keystore"
	"$HOME/.android/debug.keystore"
)
KEYSTORE=""
for CANDIDATE in "${KEYSTORE_CANDIDATES[@]}"; do
	if [ -f "$CANDIDATE" ]; then KEYSTORE="$CANDIDATE"; break; fi
done
if [ -n "$KEYSTORE" ]; then
	ok "debug keystore: $KEYSTORE"
else
	bad "debug keystore"
	blocker "No debug keystore. Without one Godot reports 'Could not find debug
     keystore, unable to export.' Generate the standard Android debug keystore
     (the password is literally 'android' by convention, and Godot's Editor
     Settings default to it):
         mkdir -p \"$EDITOR_SUPPORT/keystores\"
         keytool -keyalg RSA -genkeypair -alias androiddebugkey \\
           -keypass android -keystore \\
           \"$EDITOR_SUPPORT/keystores/debug.keystore\" \\
           -storepass android -dname 'CN=Android Debug,O=Android,C=US' \\
           -validity 9999 -deststoretype pkcs12
     A debug keystore is for local installs ONLY. It must never sign a Play
     Store build."
fi

# -- 6. Godot Editor Settings paths -------------------------------------------
#
# Godot does not read ANDROID_HOME or JAVA_HOME. It reads its OWN editor
# settings, which is why an export can fail on a machine where the shell
# environment is perfectly configured.

EDITOR_SETTINGS="$(find "$EDITOR_SUPPORT" -maxdepth 1 -name 'editor_settings-*.tres' 2>/dev/null | sort | tail -1)"
if [ -n "$EDITOR_SETTINGS" ]; then
	SETTINGS_SDK="$(sed -n 's|^export/android/android_sdk_path = "\(.*\)"$|\1|p' "$EDITOR_SETTINGS" | tail -1)"
	SETTINGS_JAVA="$(sed -n 's|^export/android/java_sdk_path = "\(.*\)"$|\1|p' "$EDITOR_SETTINGS" | tail -1)"

	if [ -n "$SETTINGS_SDK" ] && [ -d "$SETTINGS_SDK" ]; then
		ok "editor setting export/android/android_sdk_path = $SETTINGS_SDK"
	else
		bad "editor setting export/android/android_sdk_path (currently \"${SETTINGS_SDK:-}\")"
		blocker "Godot's Editor Settings > Export > Android > Android SdK Path is
     unset or points at a directory that does not exist. Godot ignores
     ANDROID_HOME entirely. Set it in the editor GUI, or edit:
         $EDITOR_SETTINGS
         export/android/android_sdk_path = \"$SDK_DIR\""
	fi

	if [ -n "$SETTINGS_JAVA" ] && [ -d "$SETTINGS_JAVA" ]; then
		ok "editor setting export/android/java_sdk_path = $SETTINGS_JAVA"
	else
		bad "editor setting export/android/java_sdk_path (currently \"${SETTINGS_JAVA:-}\")"
		blocker "Godot's Editor Settings > Export > Android > Java SdK Path is unset.
     Godot reports 'A valid Java SDK path is required in Editor Settings.' Set
     it in the editor GUI, or edit:
         $EDITOR_SETTINGS
         export/android/java_sdk_path = \"\$(/usr/libexec/java_home -v $REQUIRED_JAVA_MAJOR)\"
     Resolve the \$(...) to a literal path first -- the .tres file is not a shell
     script."
	fi
else
	note "no editor_settings-*.tres found under $EDITOR_SUPPORT"
	warn "Could not find Godot's editor settings file, so the Android SDK and Java
     SDK paths could not be checked. Open the editor once to create it."
fi

# -- 7. The export preset ------------------------------------------------------

if [ -f "$PRESETS" ]; then
	if grep -q '^platform="Android"' "$PRESETS" && grep -q "^name=\"$PRESET_NAME\"" "$PRESETS"; then
		ok "export preset \"$PRESET_NAME\" present in export_presets.cfg"
	else
		bad "export preset \"$PRESET_NAME\""
		blocker "game/export_presets.cfg has no Android preset. The exact block to add
     is written out in docs/ANDROID_READINESS.md section 1 -- paste it at the
     end of the file, or add it through Project > Export > Add > Android and
     then reconcile it against that document."
	fi
else
	bad "game/export_presets.cfg"
	blocker "game/export_presets.cfg does not exist at $PRESETS."
fi

# -- 8. adb, only if an install was asked for ---------------------------------

ADB=""
if command -v adb >/dev/null 2>&1; then
	ADB="$(command -v adb)"
elif [ -x "$SDK_DIR/platform-tools/adb" ]; then
	ADB="$SDK_DIR/platform-tools/adb"
fi

if [ "$DO_INSTALL" -eq 1 ]; then
	if [ -n "$ADB" ]; then
		ok "adb: $ADB"
		DEVICES="$("$ADB" devices 2>/dev/null | sed '1d' | grep -c "device$" || true)"
		if [ "${DEVICES:-0}" -ge 1 ]; then
			ok "adb sees $DEVICES device(s)"
		else
			bad "no Android device visible to adb"
			blocker "--install was requested but adb sees no device. Enable Developer
     Options and USB debugging on the tablet/phone, connect it, accept the
     'Allow USB debugging' prompt, then re-run. Check with:
         adb devices"
		fi
	else
		bad "adb"
		blocker "--install was requested but adb is not installed:
         sdkmanager 'platform-tools'
         export PATH=\"\$ANDROID_HOME/platform-tools:\$PATH\""
	fi
elif [ -z "$ADB" ]; then
	note "adb not found (only needed for --install)"
fi

# -- Report --------------------------------------------------------------------

echo ""
if [ "${#WARNINGS[@]}" -gt 0 ]; then
	echo "---- warnings (not blocking) ----"
	for W in "${WARNINGS[@]}"; do printf '  * %s\n' "$W"; echo ""; done
fi

if [ "${#BLOCKERS[@]}" -gt 0 ]; then
	echo "================================================================"
	printf '  ANDROID EXPORT IS BLOCKED -- %d thing(s) missing.\n' "${#BLOCKERS[@]}"
	echo "  NO APK WAS PRODUCED. Nothing below has been guessed at:"
	echo "  each item is a real check that just failed on this machine."
	echo "================================================================"
	echo ""
	INDEX=1
	for B in "${BLOCKERS[@]}"; do
		printf '  %d. %s\n\n' "$INDEX" "$B"
		INDEX=$((INDEX + 1))
	done
	echo "  Full runbook: docs/ANDROID_READINESS.md"
	echo ""
	exit 1
fi

echo "All preflight checks passed."
if [ "$CHECK_ONLY" -eq 1 ]; then
	echo "--check given; stopping before the export."
	exit 0
fi

# -- Export --------------------------------------------------------------------

case "$MODE" in
	debug)   EXPORT_FLAG="--export-debug" ;;
	release) EXPORT_FLAG="--export-release" ;;
esac

echo ""
echo "==> Exporting Android APK ($MODE)"
mkdir -p "$OUT_DIR"
rm -f "$OUT_APK"
# Force a rescan so GDExtension libraries are re-detected, exactly as the iOS
# script does and for the same reason.
rm -f "$GAME_DIR/.godot/extension_list.cfg"

if ! "$GODOT" --headless --path "$GAME_DIR" "$EXPORT_FLAG" "$PRESET_NAME" "$OUT_APK"; then
	echo "Godot export failed. Its last error above is the real one." >&2
	exit 1
fi

[ -f "$OUT_APK" ] || { echo "Godot reported success but $OUT_APK does not exist." >&2; exit 1; }

echo ""
echo "==> Built $OUT_APK ($(du -h "$OUT_APK" | cut -f1))"

# Show what the APK actually asks for. On a children's app the permission list
# is not a detail -- see docs/ANDROID_READINESS.md section 2.
if [ -n "$SDK_DIR" ]; then
	AAPT2="$(find "$SDK_DIR/build-tools" -name aapt2 -type f 2>/dev/null | sort | tail -1)"
	if [ -n "$AAPT2" ]; then
		echo ""
		echo "==> Permissions actually declared in the APK:"
		# Captured rather than piped straight to sed: `grep | sed` exits 0 even
		# when grep matched nothing, so the old `|| echo "(none)"` could never
		# fire and an empty permission list printed as silence. Silence and
		# "none" look identical but mean very different things when the question
		# is "what is this children's app asking for?", so say it explicitly.
		PERMS="$("$AAPT2" dump permissions "$OUT_APK" 2>/dev/null \
			| grep -E "^(uses-permission|permission)" || true)"
		if [ -n "$PERMS" ]; then
			printf '%s\n' "$PERMS" | sed 's/^/    /'
		else
			echo "    (none -- the APK declares no permissions at all)"
		fi
		if [ "$MODE" = "debug" ]; then
			echo ""
			echo "    NOTE: this is the $MODE APK. Godot CAN add INTERNET to a debug"
			echo "    export for the remote debugger, so a debug permission list is not"
			echo "    automatically the shipping one -- always re-check a release build."
		fi
	fi
fi

if [ "$DO_INSTALL" -eq 1 ]; then
	echo ""
	echo "==> Installing to device"
	"$ADB" install -r "$OUT_APK"
	echo "==> Installed. Launch it from the launcher, or:"
	echo "    $ADB shell monkey -p com.pointit.littlebuddy -c android.intent.category.LAUNCHER 1"
fi

echo ""
echo "==> Done."
