#!/usr/bin/env bash
# Creates the one-time Google Play upload key outside the repository and prints
# only public certificate fingerprints. The passphrase is read from the
# existing release environment variable and is never echoed or written here.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEYSTORE_PATH="${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-}"
KEY_ALIAS="${GODOT_ANDROID_KEYSTORE_RELEASE_USER:-littledays-upload}"
KEY_PASSWORD="${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-}"

if [ -z "$KEYSTORE_PATH" ] || [ -z "$KEY_PASSWORD" ]; then
	echo "Set GODOT_ANDROID_KEYSTORE_RELEASE_PATH and GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD." >&2
	exit 2
fi
case "$KEYSTORE_PATH" in
	"$REPO_ROOT"/*)
		echo "Refusing to create a credential inside the repository." >&2
		exit 2 ;;
esac
if [ -e "$KEYSTORE_PATH" ]; then
	echo "Refusing to overwrite existing keystore: $KEYSTORE_PATH" >&2
	exit 2
fi

mkdir -p "$(dirname "$KEYSTORE_PATH")"
keytool -genkeypair -v -keystore "$KEYSTORE_PATH" -storetype PKCS12 \
	-storepass "$KEY_PASSWORD" -keypass "$KEY_PASSWORD" -alias "$KEY_ALIAS" \
	-keyalg RSA -keysize 4096 -validity 10000 \
	-dname "CN=Little Days Upload, OU=Mobile, O=Join Anny, C=TH"
chmod 600 "$KEYSTORE_PATH"

echo "Created upload keystore: $KEYSTORE_PATH"
echo "Alias: $KEY_ALIAS"
keytool -list -v -keystore "$KEYSTORE_PATH" -storepass "$KEY_PASSWORD" -alias "$KEY_ALIAS" \
	| grep -E 'SHA1:|SHA256:'
echo "Back up the keystore and passphrase separately before the first Play upload."
