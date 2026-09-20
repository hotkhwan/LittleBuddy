# MacBook Handoff — updated 2026-09-20

Supersedes the 2026-09-17 handoff (that one targeted `mac-mini-handoff-20260917`
and expected a 30-case suite; both are out of date).

| | |
|---|---|
| **Branch** | `feature/overnight-production-candidate` |
| **Commit** | **`87408c1`** — *feat(visual): Aliz repaired locally, Bunny expressive, four rooms dressed*. Pushed and verified on the remote. |
| **Version** | `0.1.0` |
| **Remote** | `https://github.com/hotkhwan/LittleBuddy.git` |
| **Expected suite** | `PASS - 122 case(s), 0 failure(s)` |

A fresh clone of this branch was made into a temp directory and run end to end
before this was written — the suite is green there, and both characters load.
The numbers below are measured on that clone, not assumed.

---

## 1. Copy-paste: get the code

```bash
git clone https://github.com/hotkhwan/LittleBuddy.git
cd LittleBuddy
git checkout feature/overnight-production-candidate
git pull

# first command to run — proves the checkout is sound
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/run_tests.gd
```

Expected: `PASS - 122 case(s), 0 failure(s)`.

If that passes, the project is sound and you can open it in the editor. **You do
not need to build the speech plugin to run, edit, test or export the game** — see
§4 for what you lose without it.

---

## 2. Environment

| Tool | Version here | Notes |
|---|---|---|
| **Godot** | `4.7.2.stable.official` | Must match. The project is `config_version=5`, Mobile renderer. |
| **Godot export templates** | `4.7.2.stable` | Required for any iOS export. Install via *Editor → Manage Export Templates*. |
| **Xcode** | `27.0` (build `27A266a`) | Used for the arm64 device build. |
| **macOS** | `26.6.2` | |
| **Python** | 3 (system) | The asset tools are stdlib-only — no pip install needed. |
| **sips** | built in | Used by the icon and texture tools. |

Optional, only if you want to regenerate art:

* **Blender — NOT installed here.** Nothing in the current pipeline needs it. It
  would only be needed to bake a normal map. `brew install --cask blender`.

---

## 3. iOS export and device build

```bash
# from the repo root
./tools/export_ios.sh debug          # or: release

cd build/ios
xcodebuild -project LittleBuddy.xcodeproj -scheme LittleBuddy \
  -configuration Debug -destination 'generic/platform=iOS' build
```

`export_ios.sh` wraps Godot's exporter and then strips two Info.plist keys Godot
hardcodes (`NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`) that this
app does not use — **run the script rather than `--export-debug` directly, or the
keys come back**.

To build without a signing identity (compile check only), add:

```bash
CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

For a real device install you need your own signing identity selected in Xcode.
`application/app_store_team_id` is already set in `game/export_presets.cfg`; the
code-sign identity and provisioning-profile UUID fields are deliberately **empty**
and are filled in by Xcode, not committed.

Expected: `** BUILD SUCCEEDED **`, binary architecture `arm64`, `.pck` ≈ **5.0 MB**.

---

## 4. The speech plugin — the one real rebuild step

**Source is tracked. Compiled binaries are not.**

| Path | In git? | Size |
|---|---|---|
| `ios/speech_plugin/src/`, `SConstruct`, `build_*.sh` | **yes** | small |
| `ios/speech_plugin/godot-cpp/` | no | 609 MB |
| `ios/speech_plugin/bin/` | no | 776 MB |
| `game/ios/speech_plugin/bin/` | no | 233 MB |

Without rebuilding, the game **still runs, exports and builds**. `SpeechService`
selects a fallback backend and the new speech UI reports *"Voice is not ready —
you can tap it instead!"*. Touch play is unaffected. What you lose is real
on-device speech recognition.

To rebuild (from `ios/speech_plugin/README.md`, verified there):

```bash
git clone -b 4.5 --depth 1 https://github.com/godotengine/godot-cpp \
  ios/speech_plugin/godot-cpp

export PATH="$HOME/Library/Python/3.9/bin:$PATH"   # wherever your scons lives

cd ios/speech_plugin
./build_xcframeworks.sh      # iOS device arm64 + simulator -> bin/*.ios.*.xcframework
./build_macos_framework.sh   # macOS arm64 .framework (editor-load only)
```

Then copy the outputs to `game/ios/speech_plugin/bin/`. The macOS framework is
**not cosmetic**: without a library matching the editor's own OS/arch, Godot never
opens the extension, and therefore never bundles the iOS library into the exported
Xcode project. That is root-caused in the plugin README under *"Why a macOS
build"*.

---

## 4b. Android — toolchain is NOT in the repo either

An Android debug APK builds here, but **none of the toolchain comes from Git**.
A fresh MacBook needs all of it:

| Needed | Version here | Where |
|---|---|---|
| JDK | **Temurin 17.0.20.1 (arm64)** | `~/Library/Java/JavaVirtualMachines/temurin-17.jdk` |
| Android SDK | cmdline-tools 19.0, platform-tools 37.0.1 | `~/Library/Android/sdk` |
| Build tools / platform | `build-tools;36.1.0`, `platforms;android-36` | same |
| Debug keystore | generated locally | `~/Library/Application Support/Godot/keystores/debug.keystore` — **outside the repo, never committed** |

⚠️ `/usr/bin/java` on a clean macOS is a **stub** — `which java` finds it and it
prints *"Unable to locate a Java Runtime"*. Do not take its presence as a JDK.
Install Temurin 17 (the version Godot 4.7.2's own `config.gradle` pins). The
`brew install --cask temurin@17` route runs a `.pkg` that prompts for an admin
password; unpacking the Adoptium tarball into
`~/Library/Java/JavaVirtualMachines/` works identically with no sudo.

Godot's Editor Settings must point at both (`java_sdk_path`, `android_sdk_path`)
— a GUI export fails with a confusing path error otherwise.

Godot's **Android export templates are a separate download** from the iOS ones.

## 4c. Audio — the tracks ship, and are silent on purpose

Both of Anny's tracks **are tracked** and come with the clone
(`game/audio/music/*.ogg`, 2.3 MB). A normal build plays **no music**, and that
is correct, not a bug: `commercialUse: "pending"`, `licenseEvidence: "OWNER TO
CONFIRM"`, and the licence gate fails closed.

To resolve, complete `docs/MUSIC_RIGHTS_CHECKLIST.md` with Anny. The deciding
fact is **which Suno plan was active at the moment of generation**, and it cannot
be recovered later.

The master WAVs are **not** in the repo (they live in `~/Music/LittleDays/masters/`
on the Mac Mini). Copy them across separately if you want them; nothing in the
build needs them.

## 4d. Exact commands

```bash
# tests — the first thing to run after cloning
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/run_tests.gd

# the two mission walkthroughs (real game, not unit tests)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/smoke_mission01.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/smoke_mission01.gd -- snackTime

# audio: a normal build must be SILENT (this passing means the gate works)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/smoke_audio_silent_build.gd

# iOS export -> build/ios/LittleBuddy.xcodeproj
./tools/export_ios.sh

# arm64 device build (no signing needed to prove it compiles)
cd build/ios && xcodebuild -project LittleBuddy.xcodeproj -scheme LittleBuddy \
  -sdk iphoneos -configuration Release -arch arm64 CODE_SIGNING_ALLOWED=NO build

# Android debug APK -> build/android/LittleDays-debug.apk
./tools/export_android.sh debug
```

⚠️ `tools/export_ios.sh` does `rm -rf build/ios` first, so a signing team set
inside Xcode is destroyed by the next export. Set it in the preset, not the IDE.

## 5. What will NOT come from Git

All of this is intentional and none of it blocks development.

| Path | Size | Do you need it? |
|---|---|---|
| `build/` | 558 MB | No — regenerated by `export_ios.sh`. |
| `game/.godot/` | 195 MB | No — Godot rebuilds the import cache on first open (slow once). |
| `ios/speech_plugin/godot-cpp/`, `bin/` | 1.4 GB | Only to rebuild the speech plugin (§4). |
| `game/assets_source/meshy/**` | 92 MB | **No.** High-res Meshy masters. Never loaded by a shipping scene. |
| `game/assets/characters/**/baby_standing_v01*`, `baby_sitting_v01*`, `baby_sleeping_v01*`, `pinkGirl_v01*` | 63.6 MB | **No.** Raw exports; superseded by the runtime models, and excluded from the `.pck` too. |

**The runtime character models ARE tracked** and come with the clone (3.7 MB):

```
game/assets/characters/littleBuddy/baby/babyLittleBuddy_{v01,walk_v01,run_v01}.glb
game/assets/characters/buddy/pinkGirl/pinkGirlBuddy_{v01,walk_v01,run_v01}.glb
```

This was **broken until 2026-09-19** — `game/assets/characters/**/*.glb` caught the
runtime derivatives as well as the raw masters, so a clone had no characters at
all. Fixed in `587d4bd`; the raw masters stay excluded.

### If you ever need a raw master back

They are regenerable from Meshy, not lost. Task IDs, the credit ledger and the
exact commands are in `docs/MESHY_CREDIT_LEDGER.md` and
`docs/MESHY_CHARACTER_AUDIT.md`. Regenerating a runtime model from a master:

```bash
python3 tools/build_runtime_character.py     # the baby: weights, normals, material, texture
python3 tools/optimize_runtime_glb.py <in.glb> <out.glb> --texture 512
```

Both are local-only and cost no Meshy credits.

---

## 6. Meshy, if you continue asset work

`MESHY_API_KEY` must be exported in your shell. **It is not in the repo**, has
never been committed, and must not be — verified against the full branch history.

```bash
export MESHY_API_KEY='...'      # do not commit, do not paste into a file
```

Spend is capped by the owner and recorded in `docs/MESHY_CREDIT_LEDGER.md` **before**
each operation. Current balance: **3054**. The overnight pass used 10 of its
30-credit ceiling.

`tools/meshy_rig.sh` now requires an explicit output stem and refuses to overwrite
an existing file — it previously had the baby's paths hardcoded and silently
destroyed three paid-for assets when run for a second character.

---

## 7. First-day checklist on the MacBook

1. `git clone` … `git checkout feature/overnight-production-candidate` (§1).
2. Run the suite — expect **97/0**.
3. Install Godot **4.7.2** and its **4.7.2 export templates**.
4. Open `game/project.godot` once and let the import finish (a few minutes; it is
   rebuilding the 195 MB `.godot` cache that does not clone).
5. `./tools/export_ios.sh debug`, then the `xcodebuild` line in §3.
6. *Optional:* rebuild the speech plugin (§4) if you want real speech on device.
7. **Open Parent Corner → "Check speech" on the device first.** It names the root
   cause of any speech problem in one line. Speech has never been validated on a
   physical device and nothing in the repo claims it has.

---

## 8. Where to pick up

`docs/OVERNIGHT_WOW_PASS_REPORT.md` §9 lists what was deliberately left undone.
The shortest list:

* The tidy-up activity has a complete, tested domain and working cabinets, but no
  mission drives it yet — nothing scatters items and walks a child through it.
* Kitchen, bathroom and living room got the stage backdrop and door signs but no
  new hero props.
* No launch/opening sequence.
* Little Buddy is still 14,406 triangles against a 4,000 budget. Fixing it needs
  another remesh **and** rig (10 credits); 20 remain of the overnight ceiling.
* Interaction smoothness (joystick, tap-to-walk, drag) was not audited — unchanged,
  but unreviewed.
