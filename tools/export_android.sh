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
# 2026-09-20: `--aab` added. Google Play only accepts an Android App Bundle, and
# Godot can only produce one through the Gradle build, which needs the NDK and
# the Android build template on top of everything below. The committed preset
# stays a plain-template APK preset on purpose (that path needs neither); with
# `--aab` this script patches the two Gradle keys into a TEMPORARY copy of the
# preset for the duration of the export and restores the file afterwards, so
# `git diff game/export_presets.cfg` is clean whether the build succeeds or not.
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
#   tools/export_android.sh debug --aab       (Gradle build -> debug-signed .aab;
#                                              a pipeline proof, NOT uploadable)
#   tools/export_android.sh release --aab     (the Play upload artefact; needs the
#                                              owner's RELEASE keystore, supplied
#                                              ONLY via environment variables:
#                                                GODOT_ANDROID_KEYSTORE_RELEASE_PATH
#                                                GODOT_ANDROID_KEYSTORE_RELEASE_USER
#                                                GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
#                                              never in the repo, never in the preset)

set -uo pipefail

MODE="debug"
DO_INSTALL=0
CHECK_ONLY=0
AAB=0
for ARG in "$@"; do
	case "$ARG" in
		debug|release) MODE="$ARG" ;;
		--install)     DO_INSTALL=1 ;;
		--check)       CHECK_ONLY=1 ;;
		--aab)         AAB=1 ;;
		-h|--help)
			echo "usage: $0 [debug|release] [--install] [--check] [--aab]"
			exit 0 ;;
		*) echo "unknown argument: $ARG" >&2
		   echo "usage: $0 [debug|release] [--install] [--check] [--aab]" >&2
		   exit 2 ;;
	esac
done
if [ "$AAB" -eq 1 ] && [ "$DO_INSTALL" -eq 1 ]; then
	echo "--install needs an APK; an .aab cannot be adb-installed directly (bundletool builds APKs from it)." >&2
	exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME_DIR="$REPO_ROOT/game"
PRESETS="$GAME_DIR/export_presets.cfg"
PRESET_NAME="Android"
EXPECTED_PACKAGE="com.joinanny.littledays"
OUT_DIR="$REPO_ROOT/build/android"
# Mode-suffixed on purpose. A debug and a release APK are NOT interchangeable
# (the debug one is signed with a throwaway key and is android:debuggable), and
# a single filename lets one silently overwrite the other.
if [ "$AAB" -eq 1 ]; then
	OUT_APK="$OUT_DIR/LittleDays-$MODE.aab"
else
	OUT_APK="$OUT_DIR/LittleDays-$MODE.apk"
fi

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

FORMAT_LABEL="apk"; [ "$AAB" -eq 1 ] && FORMAT_LABEL="aab (Gradle build)"
echo "==> Little Buddy Android export preflight ($MODE, $FORMAT_LABEL)"
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
	elif [ "$AAB" -eq 1 ]; then
		bad "NDK $REQUIRED_NDK (required for the Gradle build behind --aab)"
		blocker "NDK $REQUIRED_NDK is absent. The Gradle build (the only way Godot
     produces an .aab) pins it in config.gradle. It is a ~1 GB download, ~3.1 GB
     installed, and needs no sudo:
         yes | \"$SDK_DIR/cmdline-tools/latest/bin/sdkmanager\" --sdk_root=\"$SDK_DIR\" 'ndk;$REQUIRED_NDK'"
	else
		note "NDK $REQUIRED_NDK not installed"
		warn "NDK $REQUIRED_NDK is absent. This is NOT a blocker for a plain APK
     export from the prebuilt template, which ships its own native libraries.
     It IS required for --aab (Gradle build) and the moment you turn on
     gradle_build/use_gradle_build (a custom build or an Android plugin -- e.g.
     an Android speech plugin):
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

# -- 4b. Android build template (Gradle build only) ---------------------------
#
# The Gradle build compiles Godot's Android Java/Kotlin project from source. That
# source ships inside the export templates as android_source.zip and has to be
# unpacked into res://android/build, with a version stamp at
# res://android/.build_version (NEXT TO build/, not inside it -- that is where
# Godot 4 reads it) and an empty res://android/build/.gdignore so the editor
# does not import the template's own assets. Project > Install Android Build
# Template does exactly this; the headless --install-android-build-template
# flag hangs in 4.7.2 (it waits for an editor dialog), so the steps are spelled
# out. game/android/ is git-ignored, so this is per-checkout.

BUILD_TEMPLATE_DIR="$GAME_DIR/android/build"
BUILD_VERSION_FILE="$GAME_DIR/android/.build_version"
if [ "$AAB" -eq 1 ]; then
	TEMPLATE_STAMP=""
	[ -f "$BUILD_VERSION_FILE" ] && TEMPLATE_STAMP="$(head -1 "$BUILD_VERSION_FILE" | tr -d '\r')"
	if [ -n "$TEMPLATE_STAMP" ] && [ "$TEMPLATE_STAMP" = "${TEMPLATE_VERSION:-}" ] \
			&& [ -x "$BUILD_TEMPLATE_DIR/gradlew" ] && [ -f "$BUILD_TEMPLATE_DIR/.gdignore" ]; then
		ok "Android build template: $BUILD_TEMPLATE_DIR (stamp $TEMPLATE_STAMP)"
	else
		bad "Android build template (stamp \"${TEMPLATE_STAMP:-none}\" at game/android/.build_version, need \"${TEMPLATE_VERSION:-?}\"; gradlew + build/.gdignore present?)"
		blocker "The Android build template is not installed in the project, is for a
     different Godot version, or is missing its .gdignore. Unpack it from the
     export templates (no sudo, ~220 MB, git-ignored):
         mkdir -p \"$BUILD_TEMPLATE_DIR\"
         unzip -q -o \"${TEMPLATE_DIR:-<editor data dir>/export_templates/<ver>}/android_source.zip\" -d \"$BUILD_TEMPLATE_DIR\"
         printf '%s\\n' '${TEMPLATE_VERSION:-<ver>}' > \"$BUILD_VERSION_FILE\"
         printf '\\n' > \"$BUILD_TEMPLATE_DIR/.gdignore\"
         printf 'build/\\n' > \"$GAME_DIR/android/.gitignore\""
	fi
fi

# -- 4c. RELEASE keystore (release mode only) ---------------------------------
#
# A release artefact is signed with the owner's upload key. That key is a
# credential: it is never generated here, never committed, and never written
# into export_presets.cfg. Godot 4.7 reads it from these environment variables
# whenever the preset's keystore/release* fields are empty (they are):
#   GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD
# Nothing below prints the password.

if [ "$MODE" = "release" ]; then
	RELEASE_KS="${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-}"
	PRESET_RELEASE_KS="$(sed -n 's|^keystore/release="\(.*\)"$|\1|p' "$PRESETS" 2>/dev/null | tail -1)"
	if [ -n "$PRESET_RELEASE_KS" ]; then
		bad "keystore/release is set INSIDE game/export_presets.cfg"
		blocker "game/export_presets.cfg carries a keystore/release path. Keystore
     material and passwords must never live in the repo -- clear the three
     keystore/release* fields (leave them as \"\") and supply the key through the
     environment instead (see below)."
	fi
	if [ -n "$RELEASE_KS" ] && [ -f "$RELEASE_KS" ] \
			&& [ -n "${GODOT_ANDROID_KEYSTORE_RELEASE_USER:-}" ] \
			&& [ -n "${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-}" ]; then
		ok "release keystore: $RELEASE_KS (alias ${GODOT_ANDROID_KEYSTORE_RELEASE_USER}, password: set, not shown)"
		case "$RELEASE_KS" in
			*debug.keystore) bad "release keystore IS the debug keystore"
			   blocker "GODOT_ANDROID_KEYSTORE_RELEASE_PATH points at a debug keystore. A
     debug key must never sign a Play build (Play rejects it, and if it did
     not, the app could never be updated)." ;;
		esac
		case "$RELEASE_KS" in
			"$REPO_ROOT"/*) bad "release keystore lives inside the repository"
			   blocker "The release keystore is inside the working tree. Move it outside the
     repo (e.g. ~/Library/Application Support/Godot/keystores/) -- .gitignore
     blocks *.keystore/*.jks, but a credential inside a checkout is one
     'git add -f' from disaster." ;;
		esac
	else
		bad "release keystore (GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER/_PASSWORD)"
		blocker "No release keystore supplied. A release build is refused rather than
     signed with the debug key. The owner creates the upload key ONCE, keeps it
     outside the repo, backs it up, and exports it in the shell that runs this
     script (nothing is written to disk by this script):
         keytool -genkeypair -v -keystore ~/Library/Application\\ Support/Godot/keystores/littledays-upload.jks \\
           -alias littledays-upload -keyalg RSA -keysize 2048 -validity 10000
         export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=\"\$HOME/Library/Application Support/Godot/keystores/littledays-upload.jks\"
         export GODOT_ANDROID_KEYSTORE_RELEASE_USER=littledays-upload
         read -s GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD && export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
     With Play App Signing (the default for new apps) this is the UPLOAD key;
     Google holds the app signing key. Losing the upload key is recoverable
     through Play Console support; a leaked one must be reset the same way."
	fi
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
	if grep -q "^package/unique_name=\"$EXPECTED_PACKAGE\"$" "$PRESETS"; then
		ok "Android package id: $EXPECTED_PACKAGE"
	else
		bad "Android package id is not $EXPECTED_PACKAGE"
		blocker "Set package/unique_name=\"$EXPECTED_PACKAGE\" in the Android export preset before building or uploading."
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
echo "==> Exporting Android $( [ "$AAB" -eq 1 ] && echo AAB || echo APK ) ($MODE)"
mkdir -p "$OUT_DIR"
rm -f "$OUT_APK"
# Force a rescan so GDExtension libraries are re-detected, exactly as the iOS
# script does and for the same reason.
rm -f "$GAME_DIR/.godot/extension_list.cfg"

# An .aab only comes out of the Gradle build, and Godot decides the format from
# the preset, not from the output filename. Rather than commit a second preset
# (or flip the APK preset and break the no-NDK path), patch the two keys into
# the preset for the duration of this one export and put the original back --
# on success, on failure, and on Ctrl-C alike.
PRESETS_BACKUP=""
restore_presets() {
	if [ -n "$PRESETS_BACKUP" ] && [ -f "$PRESETS_BACKUP" ]; then
		cp -p "$PRESETS_BACKUP" "$PRESETS"
		rm -f "$PRESETS_BACKUP"
		PRESETS_BACKUP=""
	fi
}
if [ "$AAB" -eq 1 ]; then
	PRESETS_BACKUP="$(mktemp "${TMPDIR:-/tmp}/export_presets.cfg.XXXXXX")"
	cp -p "$PRESETS" "$PRESETS_BACKUP"
	trap restore_presets EXIT INT TERM
	sed -i '' \
		-e 's|^gradle_build/use_gradle_build=false$|gradle_build/use_gradle_build=true|' \
		-e 's|^gradle_build/export_format=0$|gradle_build/export_format=1|' \
		"$PRESETS"
	if ! grep -q '^gradle_build/use_gradle_build=true$' "$PRESETS" \
			|| ! grep -q '^gradle_build/export_format=1$' "$PRESETS"; then
		echo "Could not switch the Android preset to Gradle/AAB (expected the two gradle_build keys at their APK defaults)." >&2
		exit 1
	fi
	# Godot launches gradlew itself and passes java_sdk_path as JAVA_HOME, but
	# gradlew also honours the caller's JAVA_HOME; make them agree.
	export JAVA_HOME="${JAVA_HOME:-$(dirname "$(dirname "$JAVA_BIN")")}"
fi

PRESETS_SUM_BEFORE="$(shasum -a 256 "${PRESETS_BACKUP:-$PRESETS}" | cut -d' ' -f1)"
EXPORT_OK=1
"$GODOT" --headless --path "$GAME_DIR" "$EXPORT_FLAG" "$PRESET_NAME" "$OUT_APK" || EXPORT_OK=0
restore_presets
if [ "$(shasum -a 256 "$PRESETS" | cut -d' ' -f1)" != "$PRESETS_SUM_BEFORE" ]; then
	echo "WARNING: game/export_presets.cfg is not byte-identical to what it was before the export -- run 'git diff game/export_presets.cfg' before committing." >&2
fi
if [ "$EXPORT_OK" -ne 1 ]; then
	echo "Godot export failed. Its last error above is the real one." >&2
	exit 1
fi

[ -f "$OUT_APK" ] || { echo "Godot reported success but $OUT_APK does not exist." >&2; exit 1; }

echo ""
echo "==> Built $OUT_APK ($(du -h "$OUT_APK" | cut -f1))"

if [ "$AAB" -eq 1 ]; then
	# An .aab is JAR-signed (v1 only); apksigner does not apply. jarsigner ships
	# with the JDK found above.
	#
	# MEASURED 2026-09-20: Godot 4.7.2 passes -Pperform_signing=true and the
	# keystore to Gradle, Gradle runs :signStandardDebugBundle, and the bundle
	# that comes out is STILL unsigned (no META-INF/*.SF, no signing block;
	# `jarsigner -verify` says "jar is unsigned"). Godot does not sign the
	# bundle itself after Gradle either (export_plugin.cpp returns right after
	# copyAndRenameBinary). Play rejects an unsigned bundle. So: verify, and if
	# it is unsigned, sign it here with jarsigner -- the same tool Google's own
	# docs name for signing a bundle. The password reaches jarsigner through
	# -storepass:env, never on the command line.
	JARSIGNER="$(dirname "$JAVA_BIN")/jarsigner"
	if [ ! -x "$JARSIGNER" ]; then
		echo "jarsigner not found next to $JAVA_BIN; cannot verify or sign the bundle." >&2
		exit 1
	fi
	if "$JARSIGNER" -verify "$OUT_APK" 2>&1 | grep -q "jar verified"; then
		echo "    bundle already signed by Gradle"
	else
		echo "    Gradle left the bundle UNSIGNED -- signing with jarsigner ($MODE key)"
		if [ "$MODE" = "debug" ]; then
			SIGN_KS="$KEYSTORE"
			SIGN_ALIAS="$(sed -n 's|^export/android/debug_keystore_user = "\(.*\)"$|\1|p' "${EDITOR_SETTINGS:-/dev/null}" | tail -1)"
			SIGN_ALIAS="${SIGN_ALIAS:-androiddebugkey}"
			LB_STOREPASS="$(sed -n 's|^export/android/debug_keystore_pass = "\(.*\)"$|\1|p' "${EDITOR_SETTINGS:-/dev/null}" | tail -1)"
			LB_STOREPASS="${LB_STOREPASS:-android}"
		else
			SIGN_KS="$GODOT_ANDROID_KEYSTORE_RELEASE_PATH"
			SIGN_ALIAS="$GODOT_ANDROID_KEYSTORE_RELEASE_USER"
			LB_STOREPASS="$GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD"
		fi
		export LB_STOREPASS
		if ! "$JARSIGNER" -keystore "$SIGN_KS" -storepass:env LB_STOREPASS \
				-sigalg SHA256withRSA -digestalg SHA-256 "$OUT_APK" "$SIGN_ALIAS" 2>&1 \
				| grep -v -i "self-signed\|^Warning:\|^$" | sed 's/^/    /'; then :; fi
		unset LB_STOREPASS
	fi
	echo ""
	echo "==> Bundle signature (jarsigner -verify):"
	VERIFY_OUT="$("$JARSIGNER" -verify -verbose:summary -certs "$OUT_APK" 2>&1)"
	printf '%s\n' "$VERIFY_OUT" | grep -E "jar verified|Signed by|unsigned|error" | sort -u | sed 's/^/    /' | head -4
	if ! printf '%s\n' "$VERIFY_OUT" | grep -q "jar verified"; then
		echo "Bundle is not signed after all attempts; do not upload it." >&2
		exit 1
	fi
	echo "    SHA-256: $(shasum -a 256 "$OUT_APK" | cut -d' ' -f1)"
	echo "    size:    $(stat -f %z "$OUT_APK") bytes"
	if [ "$MODE" = "debug" ]; then
		echo ""
		echo "    NOTE: this .aab is DEBUG-signed. It proves the Gradle/AAB pipeline"
		echo "    works on this machine; Play Console will reject it. The upload"
		echo "    artefact is 'tools/export_android.sh release --aab' with the"
		echo "    owner's release keystore in the environment."
	fi
	echo ""
	echo "==> Done."
	exit 0
fi

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
	echo "    $ADB shell monkey -p $EXPECTED_PACKAGE -c android.intent.category.LAUNCHER 1"
fi

echo ""
echo "==> Done."
