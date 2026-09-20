# MacBook — Founder Preview validation, 2026-09-20

Branch `feature/overnight-production-candidate`. Base commit verified on this
MacBook: **`3999ff1`** (pulled fast-forward from `origin`; the local clone was
29 commits behind and had no uncommitted work). Every claim below is a command
run on this machine today, or is marked BLOCKED / NOT RUN.

**Verdict: the build is sound on the MacBook and an installable Xcode project
exists. The Founder Preview is still NOT device-validated.** Two things only
Khwan can do stand between here and the first iPad launch: sign in to Xcode
with an Apple ID, and plug in the iPad. See §7.

---

## 1. Environment (actual)

| | MacBook (this machine) | Mac Mini (handoff) |
|---|---|---|
| macOS | 26.5.2 (25F84) | 26.6.2 |
| Xcode | **26.6** (17F113), iOS SDK 26.5 | 27.0 |
| Godot | `4.7.2.stable.official.ed1daf0bf` | same |
| Godot export templates | 4.7.2.stable — `ios.zip`, `android_debug.apk`, `android_release.apk` present | same |
| godot-cpp (vendored, not in git) | branch **4.5** (`Godot Engine v4.5.stable.official`, commit `27d9dd2`) | 4.5 |
| Checkout | `~/Projects/LittleBuddy-latest` (the old `~/Projects/LittleBuddy` tracks `main` only and is not used) | `~/Projects/little-buddy` |
| Signing identities | **0 valid** (`security find-identity -v -p codesigning`) | not recorded |
| Apple ID in Xcode | **none** (no `IDEProvisioningTeams`, no provisioning profiles on disk) | — |
| Devices seen by Xcode | **iPhone 14 Pro Max** (`0D1FB697-5B4D-5E5D-94E6-48ED43109DE1`), connected. **No iPad.** | — |
| JDK / Android SDK | **absent** (see §8) | Temurin 17, SDK 36 |

Godot was not migrated. Renderer and import settings were not touched.

## 2. Native iOS speech plugin

Nothing needed rebuilding: the binaries were built on this MacBook on
2026-09-19 (gitignored, `game/ios/speech_plugin/bin/`, built against the
vendored godot-cpp 4.5 the handoff specifies) and no tracked source under
`ios/speech_plugin/src/` or `SConstruct` is newer than them.

Verified today, not assumed:

| Check | Result |
|---|---|
| `liblittle_buddy_speech.ios.{debug,release}.xcframework` | present, slices `ios-arm64` + `ios-arm64_x86_64-simulator` |
| Device slice | `arm64` only, `LC_BUILD_VERSION` platform iOS, `minos 15.0` |
| macOS editor-load framework | present, `arm64` (needed so the editor loads the extension at all) |
| Godot discovers the extension | `game/.godot/extension_list.cfg` lists `res://ios/speech_plugin/littlebuddyspeech.gdextension` after a fresh `--import` |
| Exported Xcode project references it | `project.pbxproj` file ref to the `.ios.debug.xcframework`; `OTHER_LDFLAGS` carries `-Wl,-U,_little_buddy_speech_library_init` |
| Entry symbol registered | `build/ios/LittleBuddy/dummy.cpp` registers `little_buddy_speech_library_init` |
| System frameworks linked | `Speech.framework`, `AVFoundation.framework` both in the pbxproj (from the export addon) |
| Symbol actually in the arm64 binary | `nm` finds `little_buddy_speech_library_init` and `_OBJC_CLASS_$_SFSpeechRecognizer` in the built `LittleBuddy` |

**This proves the plugin compiles, links and is packaged. It does not prove
on-device recognition works.** That remains an iPad test (§7, step 16–17).

## 3. Tests (MacBook)

```
Godot --headless --path game --import                      exit 0
Godot --headless --path game --script res://tests/run_tests.gd
  PASS - 122 case(s), 0 failure(s)                         exit 0
smoke_mission01.gd            SMOKE PASS, 3/3 stars, replay re-armed   exit 0
smoke_mission01.gd -- snackTime  SMOKE PASS, 3/3 stars                 exit 0
smoke_audio_silent_build.gd   SMOKE PASS — normal build plays NO music exit 0
```

Identical to the Mac Mini baseline (122). No test was edited. The only stderr
noise is the headless dummy renderer's RID-leak-at-exit report, which is not a
test failure.

## 4. iOS export

`./tools/export_ios.sh debug` → exit 0. Inspected in `build/ios/`:

| Item | Value |
|---|---|
| Display name | **Little Days** (`INFOPLIST_KEY_CFBundleDisplayName`), product `LittleBuddy` |
| Bundle id | `com.pointit.littlebuddy` |
| Version | `0.1.0` |
| Deployment target | iOS 15.0, device family iPhone + iPad |
| Orientation | `LandscapeLeft`, `LandscapeRight` only, for iPhone and `~ipad` |
| Signing | `CODE_SIGN_STYLE = Automatic`, `DEVELOPMENT_TEAM = JZDAUN45CF`, Debug = *Apple Development*, Release = *Apple Distribution*. Not customised. |
| Privacy strings | `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` only. Camera and photo-library keys stripped by the wrapper. |
| Runtime assets | `LittleBuddy.pck` **8,297,596 bytes** (larger than the handoff's ≈5 MB: music OGGs and both runtime characters are now inside) |
| Speech plugin | bundled, see §2 |

## 5. arm64 build

```
xcodebuild -project build/ios/LittleBuddy.xcodeproj -scheme LittleBuddy \
  -sdk iphoneos -configuration Debug -arch arm64 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
** BUILD SUCCEEDED **
```

Product: `LittleBuddy.app`, binary `arm64` (non-fat), `MinimumOSVersion 15.0`,
display name *Little Days*, 108 MB unsigned Debug bundle. Built with Xcode 26.6
rather than the Mac Mini's 27.0; no source change was needed.

## 6. Visual review — current build only

Evidence used: the shots committed **at `87408c1`** (`alt_*_ipad.png`,
`aliz_after_*.png`) plus one fresh render from this MacBook,
`docs/shots/macbook_rc_feed.png` (real `SubViewport`, 1334×750 read back from
the PNG). Nothing from `b53e01e` was used.

Confirmed fixed and not re-reported: Aliz's open mouth is closed, the fringe is
continuous, rooms are lit from above, room signs are present, Bunny is the
rigged runtime model.

Remaining defects, in the brief's priority order:

| Where | Defect | Severity |
|---|---|---|
| Opening impression (main menu) | At menu distance Aliz's repaired mouth/chin patch reads as a **dark smudge on the chin** — the first thing a parent sees. Fine at gameplay distance. | Visible, cosmetic |
| Aliz, every room | A **stray pink hair chip** floats beside her right eye (visible in bedroom, kitchen and focus shots). One or two detached hair polygons. | Visible, cosmetic |
| Bunny | His "I'm hungry!" line is **bare text with no bubble backing**, low contrast on the cream wall. | Readability |
| Milk mini-game / feeding | The feeding close-up shows a **flat 2D placeholder face** (pink disc, dot eyes) instead of Bunny, and the bottle is barely visible in it. The character on the rug and the character being fed do not look like the same Bunny. | The largest remaining gap between "works" and "reads" |
| Feeding HUD | A small pink/blue fragment sits in the **extreme top-left corner** during the feed beat (`macbook_rc_feed.png`), likely a clipped bubble or icon. | Minor |
| Kitchen | Aliz stands in front of the KITCHEN door sign at spawn, hiding it. | Minor |
| Snack Time | Not separately photographed on this machine; the walkthrough passes. | Not reviewed |

No production scene was edited for this report. Fixing any of the above is a
separate, owned change.

## 7. Physical iPad QA — BLOCKED, owner only

Not run. No device claim is made. What blocks it today, in order:

1. **Xcode has no Apple ID and no signing certificate on this MacBook.** Until
   Khwan signs in (Xcode → Settings → Accounts) and picks the team on the
   LittleBuddy target, nothing can be installed on any device.
2. **No iPad has been connected to this Mac.** An iPhone 14 Pro Max is
   connected; it is a valid secondary test device once signing exists, but the
   layout target is the iPad.
3. Developer Mode on the iPad, and trusting the profile after first launch.

The one-page card to follow on the device is **`docs/IPAD_QUICK_CHECK.md`**
(20 steps, sign-off block). The full sheet remains `docs/DEVICE_QA_CHECKLIST.md`.
Note the install guide's absolute paths are the Mac Mini's
(`~/Projects/little-buddy`); on this machine the repo is
`~/Projects/LittleBuddy-latest`.

## 8. Android readiness — toolchain absent, no APK

| Requirement | MacBook |
|---|---|
| JDK 17 | **absent** — `/usr/bin/java` is the macOS stub |
| Android SDK, platform-tools, build-tools 36.1.0, platform 36 | **absent** (`~/Library/Android/sdk` does not exist) |
| Debug keystore | **absent** |
| Godot Android export templates | **present** (4.7.2) |
| `[preset.1]` Android preset | present in `game/export_presets.cfg` |
| `tools/export_android.sh --check` | fails on JDK, SDK, keystore and both editor-settings paths, and prints the fixes |

No APK was produced on this machine and none is claimed. The Mac Mini's APK is
not in git. The sudo-free install plan is already written and was the one that
worked on the Mac Mini: **`docs/ANDROID_READINESS.md` §7** (Temurin 17 tarball
into `~/Library/Java/JavaVirtualMachines`, cmdline-tools into
`~/Library/Android/sdk`, `sdkmanager` for `platform-tools`, `platforms;android-36`,
`build-tools;36.1.0`, then `keytool` for a debug keystore and the two Godot
editor-settings paths). Roughly 1 GB of downloads; not started today because it
does not gate the iPad preview. The Android speech backend remains
*unavailable* by design (`SpeechService` guards on `OS.has_feature("mobile")`,
never the mock); touch fallback is mandatory and tested.

## 9. Music licence status

Unchanged. `game/content/audio/manifest.json` still reads
`commercialUse: "pending"`, `licenseEvidence: "OWNER TO CONFIRM"` for both
tracks. The silent-build smoke passes on this machine, so a normal build plays
no music. No override flag was armed, no rights evidence was invented, nothing
was regenerated. Resolution: `docs/MUSIC_RIGHTS_CHECKLIST.md` with Anny.

## 10. Meshy

Zero-credit pre-flight only. `MESHY_API_KEY` is present in this shell (never
printed or written). `GET /openapi/v1/balance` → HTTP 200, **balance 3134**
(the ledger's last recorded figure was 3054; the difference is an increase, so
nothing was spent between the two readings). Founder Preview sprint ceiling:
**100 credits authorised, 0 spent, 100 remaining.** No paid call was made, and
Aliz was not regenerated: the current Aliz is the approved fallback.

## 11. Git

| | |
|---|---|
| Base commit verified | `3999ff1` |
| This report's commit | `6836f36` |
| Pushed to | `origin/feature/overnight-production-candidate`, fast-forward, no force |
| Pre-push checks | tracked tree grepped for API keys, private keys and keystore/profile files: none; `build/` and plugin binaries confirmed gitignored; suite 122/122 |

## 12. Commit SHAs

| | |
|---|---|
| Base (from Mac Mini) | `3999ff1` |
| Report + iPad card + MacBook render | `6836f36` |
| This SHA line | the commit that follows `6836f36`; `git log -2 --oneline` shows both |
| Remote | `origin/feature/overnight-production-candidate` at the same SHA as local HEAD after `git push` (fast-forward, verified with `git status -sb`) |

## 13. Remaining blockers, in order

1. **Owner:** sign in to Xcode, connect the iPad, run `docs/IPAD_QUICK_CHECK.md`.
2. **Owner:** decide on Anny's music rights (`MUSIC_RIGHTS_CHECKLIST.md`).
3. Engineering, if wanted before Monday: the feeding close-up placeholder face,
   the menu-distance chin smudge, the stray hair chip, a backing for Bunny's line.
4. Android toolchain install on this MacBook (plan in `ANDROID_READINESS.md` §7),
   then a debug APK; only if an Android tester exists.
5. Aliz regeneration via Meshy stays optional and gated; 100 credits are
   authorised and the tooling is ready, but it is not required for the preview.
