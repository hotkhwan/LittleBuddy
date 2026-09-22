# Post-Codex integration — final report (2026-09-22)

Branch `feature/ui-meshy-cloud`. Codex branch `feature/codex-ui-polish` merged
at its tip **`0f1bc51`** (merge `abd61b0`, tagged `codex-final-merge-2026-09-22`;
the state before it is tagged `pre-codex-final-merge-2026-09-22` = `c1dd76d`).
**Final integrated SHA: see §8.** Nothing here is a physical-device result.

## 1. Branch divergence at the start
24 Codex commits ahead (closed production platform, production D1 through 0007,
guest → parent identity, Workers AI provider stack, AI Search curriculum,
Learning Agent, Voice Agent foundation, Android `com.joinanny.littledays`
release pipeline, UI work), 27 of ours ahead (tutor speech quality, gestures,
navigation, room transitions, free chat, QA fixes, iOS dyld fix). Common base
`143dba5`. Three files conflicted, all in the Worker.

## 2. Conflicts resolved by hand (both sides preserved)
| File | Resolution |
|---|---|
| `cloud/src/tutor/provider_registry.ts` | union: Codex's `workers_ai` routed provider AND our OpenAI turns factory; the fourth argument accepts either the `AI` binding or the OpenAI extras (`isAiBinding` discriminates); the mock still serves when neither is configured |
| `cloud/src/do/tutor_session_do.ts` | the Durable Object passes both (`{ai, baseUrl, maxOutputTokens}`) |
| `cloud/.dev.vars.example` | both blocks kept (our chat vars + Codex's provider secrets) |
Preserved and verified after the merge: the native iOS speech plugin binaries
(`game/ios/speech_plugin/bin` is a real folder, untracked, arm64), the dyld
crash fix and its export guards, gameplay/navigation/tutor/room-transition
fixes, Codex's UI node contracts, the production Cloudflare configuration
(`api.littledays.joinanny.com` custom domain, production D1 `88f3043d…`,
**not deployed by us**), and the guest/account identity schema.

## 3. Post-merge regressions, each classified
| Failure after the merge | Kind | Action |
|---|---|---|
| Worker `chat.test.ts` "gate is OFF by default" 201 ≠ 403 | environment-only (dev env now sets `FREE_CHAT_ENABLED=1`) | test pins the flag absent |
| Worker "production-shaped env refuses chat" 503 ≠ 403 | real, by design (Codex's closed-production gate answers first) | test asserts 503 closed, then 403 with production open |
| Worker "OpenAI through the DO" model label / cost | environment-only (dev `TUTOR_MODEL` is a Workers AI id, no OpenAI price row) | test pins the provider path, not the model id |
| Prototype backend: 5 gesture fixtures | real (validator lacked the five new gestures) | enum extended, tests updated |
| Godot `test_android_platform_guards` versionCode | real (our bump to 3) | pin made monotonic (`>= 2`) |
| `cloud/src/billing/test/handlers.test.ts` Apple/Google end to end | **pre-existing on Codex's own branch** (memory rig has no `installations` table for the new parent-account check) | recorded, not fixed |

## 4. Godot → AI end to end (`docs/AI_E2E_VERIFICATION.md`)
Verified against the live dev Worker with `tests/smoke_ai_classroom.gd`:
`AI-SMOKE: PASS` — 17 turns, 6 server-authored, 0 invalid raw turns, Aliz's
expression and gesture change per turn (pool overrides on answer turns), lip
sync > 0.97 while the voice plays, the recogniser is closed and the VAD gated
while she speaks, the session ends with `serverAck: true`.
- AI Search retrieval: **PASS** live (`/v1/dev/learning/search` returns a
  scored lesson id in ~1.5 s).
- Learning Agent / planner on the turn path: **NOT WIRED** — the agent is
  reachable only from `cloud/src/routes/dev.ts`; a tutor turn never retrieves
  or plans. Same for the client Expression Director / cue contract / tool
  router (test-only; the live path is `tutor_scene` + the gesture pool).
- Workers AI: the complex route (gpt-oss) produced a **model-authored,
  validated** turn; the standard route timed out at the 6 s default. Fixed on
  dev: `PROVIDER_TIMEOUT_MS=12000`, and a dev-only client arg
  `--tutor-timeout=<s>` widens the client's patience (product defaults
  unchanged). Chat is mock-only: the Workers AI provider has no
  `generateChatTurn`.
- Offline: with the flag off the classroom is the scripted tutor with no
  network class loaded; with the flag on and the backend unreachable it falls
  back quietly and never dies. Both asserted in `test_ai_e2e_offline_fallback`.
- OpenAI: wired but unused (`TUTOR_PROVIDER=workers_ai`, no key). **No OpenAI
  call was made.**

## 5. Identity end to end (`docs/IDENTITY_E2E_VERIFICATION.md`)
First install → guest (UUID only, no hardware ids, no personal data in
`installations`/`guest_accounts`), guest = FREE + local learning + AI trial +
**purchase blocked at every layer**, guest → parent link with progress
migration (once, replay refused), entitlement follows the account, restore on
a second installation and after a reinstall never duplicates rows, and
apple/google sign-in answers **501** until the audiences are configured.
Fixed during integration: the client rejected the Worker's replies because it
read `sessionToken`; `account_state.gd` now reads `guestToken` / `parentToken`.
Open gaps recorded (not fixed): the guest credential cannot itself open a
tutor session (the trial is charged through a parent child), `guest_ai_usage`
stays empty, the account layer is not yet called from any scene, and the
billing module's own schema (`subject_id`) does not match migration 0002
(`parent_id`), so `GET /v1/billing/entitlement` 500s.

## 6. Gates on the final code
| Gate | Result |
|---|---|
| Godot suite | **PASS - 188 case(s), 0 failure(s)** (168 at the start of the night, 183 right after the merge) |
| Mission 01 / Snack Time / audio / settings harness | SMOKE PASS ×3, INPUT SETTINGS OK |
| AI classroom smoke vs live dev Worker | AI-SMOKE: PASS |
| Cloudflare Worker | **254 passed**, typecheck clean |
| Prototype backend | 137 pass |
| Billing module | 34 pass, **2 fail (pre-existing on Codex's branch)** |
| Website | 12 pass |
| Live dev health | `/healthz?db=1` 200, `provider: workers_ai`, `migrations: 7` |

## 7. Cloudflare
Development Worker `little-days-api-dev` redeployed from the merge
(`https://little-days-api-dev.hotkhwan.workers.dev`), D1 `little-days-dev`
with migrations 0001–0007, `AI` and `AI_SEARCH` bindings live. **Production was
not deployed and no production resource was touched.**

## 8. Builds, versions and the remaining device list

**Final code commit `3b3bec4`**; the commits after it are this report only.

| Artefact (from `3b3bec4`) | Path | Facts |
|---|---|---|
| iOS Xcode project + pck | `build/ios/LittleBuddy.xcodeproj`, `build/ios/LittleBuddy.pck` (17,238,384 B) | export preflight PASS (plugin folder real, untracked, arm64), post-export PASS (extension bundled), `CFBundleShortVersionString` 0.1.1, bundle id `com.pointit.littlebuddy` (Apple id deliberately unchanged) |
| iOS arm64 compile | unsigned, `generic/platform=iOS` | `** BUILD SUCCEEDED **`, **0 undefined `little_buddy_speech` symbols**, 73 defined, binary arm64 |
| Android App Bundle | `build/android/LittleDays-debug.aab` (45,940,102 B) | `jar verified`, SHA-256 `04a366013750a1310ad7d5392a87be0c77c4fd49b6ccc6228d7793ae9823421a`, package **`com.joinanny.littledays`**, version 0.1.1 (**versionCode 3**, up from Codex's RC 2), no permissions in the bundle manifest, 15 Meshy prop files, 0 concept-art files. **Debug-signed pipeline proof, not uploadable.** |
| Android universal APK (for device installs) | `build/android/LittleDays-debug.apk` (98,019,248 B) | SHA-256 `4f89b2aed4e7654b4997a02ae8dd2fb4e9ffaeeacb2301fbabeea32513082ac7`, derived from the AAB with bundletool, debug-signed |

**The uploadable release AAB was NOT built.** `tools/export_android.sh release --aab`
requires `GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER/_PASSWORD`; the keystore is
at `~/Documents/LittleDays-Secure/littledays-upload.jks` (Codex's candidate
upload key, certificate `CN=Little Days Upload, O=Join Anny`) but its password
is not in the environment or the keychain, and nothing was uploaded. To
produce it:
```sh
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$HOME/Documents/LittleDays-Secure/littledays-upload.jks"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=littledays-upload
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD='…'      # or store it in the keychain first
tools/export_android.sh release --aab
```
versionCode 3 is monotonic over Codex's signed RC (2), which was never uploaded.

### Remaining native sign-in work
- **Apple:** no `AuthenticationServices` / `ASAuthorizationAppleIDProvider`
  adapter exists in the game; `ParentAccountUx` offers a button that cannot yet
  produce an `identityToken`. Needs the native plugin plus `APPLE_BUNDLE_ID`
  and a Services ID (`APPLE_SERVICE_ID`) on the Worker; nonce handling is not
  implemented in `identity_api.gd`.
- **Google:** no Credential Manager adapter (`GetGoogleIdOption` /
  `GoogleIdTokenCredential`); needs the Android plugin plus `GOOGLE_CLIENT_IDS`
  on the Worker. Codex's `docs/GOOGLE_CREDENTIAL_MANAGER.md` has the plan.
Until both exist, `POST /v1/parents` and `/v1/auth/link` answer 501 for
apple/google, which is the honest state.

### Physical-device QA list (owner)
1. iPhone launch of the new build and the Learn with Aliz flow: microphone and
   speech prompts, hands-free answers heard, **no doubled praise, no cut
   words** (both were fixed at the source this night and last).
2. Android install of the universal APK: launch, menu, a mission, Free Play.
3. Click-to-walk around bed / wardrobe / bath / table / fridge / toy box /
   doors; room transitions both ways with no bounce.
4. Gestures at phone size (thumbs up, celebrate, thinking, encourage) and the
   new Codex layouts in real safe areas; Thai reading comfort.
5. Settings scrolling with real fingers; the Baby Room highchair Home button.
6. Cloud AI is dev-only and not reachable from the shipped build; nothing to
   test on the device for AI, identity or billing.
