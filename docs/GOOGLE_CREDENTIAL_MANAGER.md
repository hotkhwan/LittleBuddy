# Google Credential Manager production contract

Last verified: 2026-09-22

## Android application identity

- Package/application ID: `com.joinanny.littledays`
- Release version: `0.1.1` (`versionCode` 2)
- Credential Manager provider: Sign in with Google
- Backend identity key: verified Google `sub`; email is never an account key

No OAuth client IDs or credentials are committed. The app must request a Google
ID token using the backend/server OAuth client ID, include a fresh nonce, and
send the opaque ID token and nonce to `POST /v1/auth/link`. The backend verifies
signature, issuer, audience, expiry, nonce, and subject before mapping the
provider subject to a backend-owned account UUID.

## Candidate upload certificate

The signed release candidate uses this public certificate:

```text
SHA-1:   7A:35:AA:D0:4E:4B:62:61:BB:B5:0A:73:AA:54:E1:38:ED:59:A1:00
SHA-256: 75:44:F9:9C:14:09:9C:AB:59:4B:C2:0E:46:BA:DE:F9:BC:75:C5:DB:A7:77:12:70:50:CE:3D:56:62:E9:C7:EA
```

These are public certificate fingerprints, not secrets. The keystore password
must never be placed in Git, Gradle files, shell history, documentation, or CI
logs.

## Owner configuration steps

1. Move `/private/tmp/littledays-upload.jks` and its password out of temporary
   storage immediately. Keep encrypted, tested backups in separate locations.
2. Create the Play Console app with package `com.joinanny.littledays`, opt into
   Play App Signing, but do not publish publicly.
3. In Google Cloud Console, configure the OAuth consent screen and create:
   - an Android OAuth client for `com.joinanny.littledays` plus the candidate
     upload SHA-1 certificate, for direct/sideload QA where applicable;
   - an Android OAuth client for the same package plus the **Play app-signing**
     SHA-1 shown by Play Console after enrollment;
   - a Web/server OAuth client whose client ID is used by Credential Manager's
     server-client-ID option and accepted by the backend.
4. Put only the issued client IDs in the correct build/server configuration.
   Add accepted token audiences to server-side `GOOGLE_CLIENT_IDS`; never add a
   client secret to Godot.
5. Register both internal-track and release signing variants that will actually
   be installed. Play's app-signing certificate is normally different from the
   upload certificate; copy its SHA-1/SHA-256 from Play Console rather than
   assuming the fingerprints above apply to Play-delivered builds.
6. Configure the Google Play Developer API service account, RTDN, and products
   later under the same final package. Keep `BILLING_ENABLED=false` until a
   separate billing approval and end-to-end internal-track verification.

## Client and backend behavior

The Android adapter must use Credential Manager, request a Google ID token with
the configured server client ID and nonce, and surface cancellation without
blocking offline play. It must not trust profile email or display name as
identity. A successful backend response persists the parent bearer credential
in platform-secure storage and links the installation's guest progress exactly
once.

Guests cannot obtain purchase identity or paid entitlement. A linked parent can
request `GET /v1/me/purchase-identity`; the returned Google marker is a
server-derived HMAC suitable for `setObfuscatedAccountId`, contains no PII, and
must be matched against the verified Play purchase before entitlement changes.

Physical Android QA remains required for Credential Manager account selection,
cancel/error flows, token/nonce verification, process restart, secure session
persistence, guest linking, multi-device sign-in, and internal-track signing.
