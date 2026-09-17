# MacBook Handoff — 2026-09-17

Development is moving from the Mac mini to a MacBook. This is a **safe checkpoint**, not a
finished milestone: the visual overhaul is deliberately incomplete.

**Handoff tag:** `mac-mini-handoff-20260917`

---

## Clone and first run

```bash
git clone https://github.com/hotkhwan/LittleBuddy.git
cd LittleBuddy

# first command to run — proves the checkout is sound
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/run_tests.gd
```

Expected: `PASS - 30 case(s), 0 failure(s)`.

---

## Environment

| Requirement | Version / note |
|---|---|
| **Godot** | **4.7.2 stable** — `brew install --cask godot`. The project declares `config/features=PackedStringArray("4.7", "Mobile")`; do not open it in an older 4.x. |
| Godot export templates | 4.7.2, incl. `ios.zip`. Godot → Editor → Manage Export Templates, or drop the `.tpz` into `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`. |
| **Xcode** | **26+ (built and verified on 27.0).** Full Xcode, not just Command Line Tools — the iOS SDK and device provisioning are required. |
| Xcode licence | `sudo xcodebuild -license` **must be accepted**, or `xcodebuild`, `xcrun` *and* `git` all fail (macOS `git` is an Xcode wrapper). This bit us once already. |
| `xcode-select` | must point at `/Applications/Xcode.app/Contents/Developer` |
| scons (only to rebuild the speech plugin) | `python3 -m pip install --user scons`, then `export PATH="$HOME/Library/Python/3.9/bin:$PATH"` |

### Apple Team ID

`game/export_presets.cfg` has `application/app_store_team_id="JZDAUN45CF"` **committed**.

Godot refuses to generate the Xcode project at all without it — this cannot be deferred to
Xcode. If the MacBook signs in with a different Apple ID, change that one value. Signing itself
is automatic (`CODE_SIGN_STYLE = Automatic`, `DEVELOPMENT_TEAM = JZDAUN45CF`).

---

## Commands you will actually need

```bash
# Test suite (30 cases)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/run_tests.gd

# Project load / parse check — expect zero output beyond the version banner
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --quit

# iOS export -> Xcode project.  USE THIS SCRIPT, not --export-debug directly.
./tools/export_ios.sh debug          # or: release

# Build the generated project (unsigned, for CI-style verification)
cd build/ios
xcodebuild -project LittleBuddy.xcodeproj -scheme LittleBuddy -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/lb_dd \
  CODE_SIGNING_ALLOWED=NO build
```

**Why `tools/export_ios.sh` and not raw Godot:** Godot's iOS template hardcodes
`NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` into the Info.plist. The app
uses neither, and filling them with dummy text would be a false privacy declaration, so the
script deletes them after export. Call Godot directly and the keys come back, along with two
Xcode warnings. The script also `rm -rf`s `build/ios` first — **never run it if `build/ios`
holds a build you still need.**

### Rebuilding the ignored iOS speech-plugin binaries

`game/ios/speech_plugin/bin/` is **gitignored** (see `.gitignore`), so a fresh clone has no
compiled plugin and **an iOS export will silently ship without speech**. The GDScript side
degrades safely to touch-only, so nothing crashes — but the mic will never work.

To rebuild:

```bash
export PATH="$HOME/Library/Python/3.9/bin:$PATH"
cd ios/speech_plugin

# godot-cpp is also gitignored; vendor it (branch 4.5 — no 4.6/4.7 branch exists upstream)
git clone -b 4.5 --depth 1 https://github.com/godotengine/godot-cpp godot-cpp

./build_xcframeworks.sh      # device arm64 + simulator arm64/x86_64, debug + release
./build_macos_framework.sh   # macOS variant — REQUIRED, see below

# copy the artifacts the export actually consumes
cp -R bin/liblittle_buddy_speech.ios.*.xcframework        ../../game/ios/speech_plugin/bin/
cp -R bin/liblittle_buddy_speech.macos.*.framework        ../../game/ios/speech_plugin/bin/
rm -f ../../game/.godot/extension_list.cfg   # force Godot to rescan extensions
```

**The macOS variant is not optional.** Godot's iOS exporter only bundles a GDExtension that the
running editor has successfully *loaded*. Without a macOS build the extension fails to load on
the host, so its iOS artifacts are never packaged — the `.gdextension` just gets copied into
the `.pck` as an inert text file. This cost a full debugging cycle to find.

Verify afterwards:
```bash
grep -oE '(Speech|AVFoundation)\.framework' build/ios/LittleBuddy.xcodeproj/project.pbxproj | sort -u
nm /tmp/lb_dd/Build/Products/Debug-iphoneos/LittleBuddy.app/LittleBuddy | grep -c little_buddy_speech_library_init
```

---

## What is finished

- **Offline-first architecture**, Godot 4.7.2, Mobile renderer, Universal iPhone + iPad
  (`UIDeviceFamily = 1,2`), iOS 15.0 min, both landscape rotations, safe-area aware.
- **Content/mission system**: 5 categories, 43 tasks, 46 vocabulary words, 270 phrase variants,
  7 missions, 16 stickers, 28 objects — all data-driven and validated (0 validator problems).
- **Interaction**: reusable drag system, multi-touch safe, tap fallback everywhere,
  `RewardLedger` guaranteeing no double-award, no dead-end states.
- **Save/progression**: stars, stickers, missions persist; corrupt-save recovery.
- **Parent settings** behind a 3-second press-and-hold gate.
- **Audio**: 8 original procedurally-generated SFX (zero third-party audio licence surface).
- **App icon**: originally authored baby bottle, 1024×1024 opaque, regenerable via
  `tools/generate_icon.gd`, verified compiling into `Assets.car`.
- **Assets**: all third-party assets are **CC0**; attribution required for nothing. See
  `docs/ASSET_MANIFEST.md`.
- **Build pipeline**: export + arm64 Xcode build both green.

## What is partially finished

- **Visual overhaul — the reason this is a checkpoint.** Props, nursery, baby and UI were all
  upgraded, but see "known issues" below.
- **Nursery** is Kenney Furniture Kit retinted to pastel. Silhouettes are still harder-edged
  than the rounded props and baby. Intended upgrade is **Tiny Treats "Playful Bedroom"**
  ($7.95, CC0) — **needs a human purchase**. Swap procedure and an enforcing test are in
  `docs/NURSERY_SWAP_CONTRACT.md`.
- **Baby** is procedural and deliberately temporary. Commission spec ready at
  `docs/CUSTOM_BABY_SPEC.md`. Kenney Mini Characters was tried and rejected — its arms import
  broken in Godot 4.7.2 before any modification.

## Known issues / bugs

| Severity | Issue |
|---|---|
| ~~Blocking~~ **RESOLVED 2026-09-17** | **Speech is now proven working on a physical iPhone 14 Pro Max (iOS 26.6.2).** Device telemetry: a listen session recognised twice and added zero new failures; stars went 46 -> 64 with sayPillow/sayBanana/sayTowel completed. Two device-only bugs were fixed to get there - see the speech section below. |
| ~~Medium~~ **RESOLVED** | The 5 remaining polygon stickers (banana, soap, towel, toothbrush, pillow) now use authored glyphs in the same visual language; all 16 read as one set. Polygon fallbacks kept as a safety net. |
| Medium | **`shoes` is the weakest 3D object** — "two brown pebbles" cold. Best candidate for a commissioned asset. |
| Low | Sticker-button icon is a treasure chest — a compromise; no real sticker-sheet glyph exists in the pack. |
| Low | `"1 / 16"` on the sticker book is a fraction on a pre-reader's screen. Deliberate (collection progress, not a score) but worth a decision. |
| Low | Speak button's `round_mint` frame is a single stretched texture, not a nine-patch; will distort if made non-square. |
| Low | Nursery: floor lamp nearly disappears at phone aspect; bookcase shelves empty; wall art low-contrast; bed reads as a daybed, not a cot. |
| Low | Bowl rim is visibly hexagonal; `water` reads as "blue cup" in isolation. |
| **Unverified** | Nothing has been run on physical hardware. Both landscape rotations and notch-side safe-area flip are **untested on a real device**. |

## Next recommended task

~~Run the app on a physical iPhone and validate speech end-to-end.~~ **Done 2026-09-17 —
speech is proven working on device.**

Next: the remaining visual polish in `docs/ART_UPGRADE_REPORT.md` — the `shoes` model is the
weakest object, and the nursery would benefit from the Tiny Treats swap (needs a purchase).

1. Rebuild the speech plugin (above) — **a fresh clone has no binaries**.
2. `./tools/export_ios.sh debug`
3. Open `build/ios/LittleBuddy.xcodeproj`, confirm the team resolves.
4. iPhone → Settings → Privacy & Security → Developer Mode → On, reboot, unlock.
5. Run; Trust the developer cert; Run again.
6. Work the checklist in `docs/OVERNIGHT_BUILD_REPORT.md` §9, speech items first.

## Assets still needing download / purchase

| Asset | Status |
|---|---|
| **Tiny Treats "Playful Bedroom"** ($7.95, CC0) | **Needs human purchase.** Best style match for the nursery. Once bought, itch.io's download API *is* scriptable — see `docs/ASSET_MANIFEST.md`. |
| `godot-cpp` (branch 4.5) | gitignored; re-clone when rebuilding the speech plugin. |
| Godot export templates 4.7.2 | not in the repo; install via the editor. |
| Tiny Treats "Bubbly Bathroom" (free, CC0) | evaluated and **deliberately not used** — covers only towel/toothbrush/duck, has no bar of soap, and those already read well procedurally. |

## Active art-direction decisions

1. **One coherent family: Kenney** (CC0, shared 512×512 colormap atlas). Do not mix in another
   3D style without a deliberate decision.
2. **Quaternius is excluded** even though it looks like a natural fit. Their licence page
   changed to QAL v1.0 on 2026-08-28; §3(a) forbids redistributing assets *"regardless of how
   much the Assets have been modified"*, which makes committing them here risky. Search engines
   and their own FAQ still say CC0 — **the site contradicts itself**. Do not re-add on the
   strength of a web search.
3. **CC0 only, zero CC-BY.** Every CC-BY asset adds a perpetual attribution obligation.
4. **Blocks are procedural on purpose** — Kenney Brick Kit's studded variants are visually LEGO
   and LEGO has litigated brick trade dress. Owner decision.
5. **Objects must read as the word they teach.** Never substitute a "similar" model: a chick is
   not a duck, a soap dish is not soap, a ketchup bottle is not soap. An honest procedural shape
   beats a wrong-but-similar sourced model.
6. **Procedural is a first-class answer**, not a fallback — it needs no licence, no download and
   no repo bytes.
7. **Palette:** warm cream `#FFF4E0`, dusty blue, soft pink `#F8BFD1`, mint `#9EDCC3`, peach,
   lavender.
8. **Audio stays original.** Kenney's CC0 packs measured worse for a small child (peaks to
   −1.4 dBFS, first sample at 0.86 full scale = an audible snap).

## Repo conventions worth knowing

- `game/` is the Godot project root (`res://` == `game/`).
- Tests: one file per case in `game/tests/cases/test_*.gd`, `extends RefCounted`, `test_name()`
  and `run() -> Array` (failure strings; empty == pass). **No autoload dependencies** — the
  runner uses `--script`, which does not load them.
- The runner fails loudly on a case that won't parse *or* whose `run()` aborts. Both holes were
  real and previously made red builds look green.
- **Kenney GLBs are not self-contained** — they reference `Textures/colormap.png` relatively.
  Copy the texture folder alongside, and if you import before it exists, delete `.godot/` and
  the `.import` files (Godot caches the failure).
- Prefer rendering a PNG and *looking at it* over trusting tests for anything visual. A camera
  bug once put every object off-screen with the whole suite green.
