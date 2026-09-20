# Little Days — final product playtest build, 2026-09-20 (evening)

Branch `feature/overnight-production-candidate`. **Final code commit `e52ed8b`**,
pushed to `origin` (fast-forward, no force). Start of this sprint: `180432e`.
34 commits, 346 files, from six workstream agents plus an independent QA agent,
merged one wave at a time by the lead and re-gated after every wave.

> Every PASS below is a command that ran on this MacBook against the real
> scenes, or a screenshot that was opened and looked at (owner design targets:
> `docs/designTargets/generatedArtManifest.md`). **Nothing here is a
> physical-device result.** The device sheet is `docs/IPAD_QUICK_CHECK.md`.

## 1. What changed, by subsystem

**Branding and shell.** Real app icons cut from the approved Aliz+Bunny render
(iOS 40–1024 opaque squares, Android adaptive layers, project icon); a branded
boot image and a splash scene (logo, three pastel dots, "Made with Godot
Engine", version) that hands over to the menu in 1.7 s and skips on tap; the
owner's logo as the title lockup; a reusable cream curtain transition.

**Home screen.** Storybook garden matching the concept: layered trees and a
blossom tree, a hanging "Welcome!" sign, a stump with a sleeping cat,
butterflies, a bluebird on the mailbox, seven flowerbeds, hills with far
cottages, clouds; everything sways, drifts or breathes. Start and Free Play play
a 2.5 s departure: Aliz walks to Bunny, lifts him to her carry socket, jogs to
the cottage door, the door swings open, the curtain closes. Dress Up is a real
screen (swatches recolour Aliz's bow, Back returns). Grown-ups no longer
freezes (root cause: the settings scene only knew how to be an overlay; as the
current scene it hid its own panel and had no way home). Version text only on
the title screen and splash.

**Guided feeding (Start).** New highchair minigame for apple, banana, milk and
water tasks in the Baby Room, matching the feeding concept: the real rigged
Bunny behind a tray, prompt bar with English and a helper line, star counter,
Home and Back. Apple is dragged to his mouth and he bites three times with
sparkles; banana must be peeled first; cup and bottle are held while he drinks
and the level drops. Wrong item: head turn, unhappy face, "Try the apple!", a
half star; a second mistake switches to a guided glow and arrow. Never a
tap-through (a plain tap does not deliver; a touch fallback appears after two
idle nudges). Glossy stars, "So close!" half-star row and sticker cards on the
summary. Half stars are honest: stars stay integers, a task finished after a
mistake pays 0 and still counts as completed.

**Free Play.** Badges shrunk to 12.8 % of screen height (96 px on iPad),
Aliz's face and any speech bubble are keep-outs. Click-to-move freezes fixed at
the root: off-navmesh taps walk to the nearest standable point, iPad's twin
touch/mouse events are latched, badge presses with nothing to do fall through,
pantomime actions no longer lock the movement machine, and a drop-zone wait
times out. Wardrobe and toy box open, shelf accepts a carried teddy, sofa SIT,
bed puts Bunny down lying, table seats him, sink and bath open the wash
close-up when he is carried, kitchen counter COOK. Bathroom and living room are
gated behind the Family Club flag with a "Soon! Ask a grown-up" sign, never a
kick-out. Landing-pad discs (the "shadow blobs") hidden in Free Play.

**Characters.** Aliz: warmer skin, brighter eye highlights, soft brows, fuller
smile; four texture moods and a blink; an authored idle (breath, head bob,
weight shift) and a head-bone hair sway. Bunny: hungry pout, sleepy, happy,
cute "hmph" with a foot stamp when ignored for 12 s, blink; urgency escalates
the bubble line and pose together. No neck seam found (measured). Soft contact
hints under both characters' feet (alpha 0.18), no blobs.

**Audio, settings, localization.** The title theme now also plays in the house
(−4 dB), the mission track in missions, one player, no restart on room change or
menu→house. Settings: music and voice sliders, voice practice on/off, speaking
speed, helper language (Off / ไทย / 中文 / العربية / हिन्दी / 日本語), Close
top-right, Done at the bottom, scrolls, gate passes with a 3 s hold, Back
always works. Localization service with five helper tables (105 keys each) and
a validated system-font chain (a script that cannot be drawn is offered as
unavailable, never tofu). Speech sessions end exactly once in success, retry or
unavailable with hard caps; Speak locks while live. Voice: best on-device voice;
a 36-line owner voice-asset request list and a drop-in path for recorded lines.

## 2. Meshy

| | |
|---|---|
| Balance at sprint start | 3184 |
| Balance at sprint end | **3184** |
| Credits spent | **0** — no paid call; all character work was local (texture and normals) |

## 3. Builds on `e52ed8b`

| Gate | Result |
|---|---|
| Godot clean import | exit 0, no script errors |
| Full suite | **PASS - 140 case(s), 0 failure(s)** (128 at sprint start; nothing weakened, deliberate expectation changes named in each agent's commit) |
| Mission 01 / Mission 02 walkthroughs | SMOKE PASS / SMOKE PASS |
| Audio shipping smoke | SMOKE PASS (menu + house theme, mission track, one player, no restart, duck, mute) |
| iOS export | exit 0, `build/ios/LittleBuddy.xcodeproj`, pck 12,058,248 B, new icons in the asset catalog, concept art excluded |
| arm64 Xcode build | `** BUILD SUCCEEDED **` (unsigned; owner's team signs in Xcode) |
| Android debug APK | `build/android/LittleDays-debug.apk`, 41,010,232 B, SHA-256 `4aad67a98c8a889845551f9794d249af01da4c795111d36252e00fde0e0513a7`, `apksigner verify` OK, targetSdk 36, arm64-v8a, adaptive icon, zero permissions |
| Release AAB | pipeline proven earlier today; **no release artefact** until the owner supplies an upload keystore |

## 4. Three-minute acceptance tests (independent QA on `cad57ef`, report `docs/QA_INTEGRATED_cad57ef.md`; the two commits after it change only the badge keep-out and a harness)

| Test | Result | Evidence |
|---|---|---|
| **AT1 Home screen** premium, colourful, animated; Start / Free Play / Dress Up / Grown-ups respond, none freeze; version only on the first screen; splash → menu in 1.72 s | **PASS** | `qa2_menu_*`, `qa2_settings_gate_*`, `qa2_dressup_*`, menu probe 60 fps |
| **AT2 Guided feeding** real learning flow; apple needs a drag to the mouth and Bunny bites; banana needs peel + give; cup/bottle needs a hold; wrong item → retry + half star; not a tap-through | **PASS** | `qa2_feeding_*`, `qa2_feeding_tap_no_complete_1334x750.png`, tap-through probe |
| **AT3 UI quality** polished readable buttons; upgraded stars/summary; settings opens/closes fast and never traps | **PASS** | `qa2_settings_*`, `feeding_summary_*` |
| **AT4 Free Play** move, carry Bunny, place on bed/table, wardrobe, fridge, toy box, sink; click-to-move never freezes | **PASS** | `fp_*`, `fp2_*`, `qa2_offmesh_*`, freeze regression suite |
| **AT5 Audio / voice / settings** music in menu and house; language + audio controls; speech resolves to success / retry / unavailable | **PASS** | audio smoke, `qa2_speech_*`, `house_helper_{th,ja,ar}_*` |
| **AT6 Build readiness** tests, Android APK, iOS export | **PASS** | §3 |

QA found no crash, freeze, tap-through, duplicate Bunny, floating object, tofu,
wrong-size frame or mock speech success. Two visible defects it raised:
the CARRY badge over Aliz's face (fixed in `e52ed8b`, `face_ipad_story_hug.png`)
and the wash close-up still using the illustrated face (see §5).

## 5. Known limitations

1. **No physical-device run.** Everything above is a macOS render or headless run. `docs/IPAD_QUICK_CHECK.md` is the owner's sheet.
2. **Wash / brush / dry close-ups** still use the illustrated face card; only the bottle shows the real Bunny. Same treatment as the feeding portrait is the next visual step.
3. **Voice** is the device's best built-in voice; a true child voice needs the 36 recorded lines listed in `docs/VOICE_ASSET_REQUEST.md` (drop into `res://audio/voice/<lineId>.ogg`).
4. **Aliz's mouth** keeps a small streak at the right corner from two sliver mouth islands; the clean fix is a mouth re-triangulation. Bunny's hungry/hmph brow has a small kink. Cosmetic.
5. **Chinese and Japanese helper text** rely on system fonts validating at runtime on the device (PingFang / Hiragino ship with iOS); if neither validates they are shown as unavailable rather than as tofu. Check Grown-ups once on the iPad.
6. **Bunny's seat at the table** is beside it on the floor (no highchair prop in the house yet); sofa/table sitting reuse his `carried` pose.
7. **Google Play**: no upload keystore, no Console app, no privacy-policy URL, no store graphics; a personal account may need 12 testers for 14 days. AAB comes back unsigned from Gradle and is re-signed by the script (verify with `jarsigner` before upload); AAB minSdk is 29 (Vulkan), APK 24.
8. Splash shows a ~0.4 s main-thread hitch while the menu resources arrive.

## 6. Install

```
open ~/Projects/LittleBuddy-latest/build/ios/LittleBuddy.xcodeproj
~/Library/Android/sdk/platform-tools/adb install -r ~/Projects/LittleBuddy-latest/build/android/LittleDays-debug.apk
```

## 7. Files changed (excluding images and .uid/.import sidecars)

- `docs/ALIZ_FACE_PASS.md`
- `docs/BUNNY_EMOTION_PASS.md`
- `docs/IPAD_QUICK_CHECK.md`
- `docs/MENU_HOME_PASS.md`
- `docs/MESHY_CREDIT_LEDGER.md`
- `docs/QA_INTEGRATED_cad57ef.md`
- `docs/THIRD_PARTY_NOTICES.md`
- `docs/VOICE_ASSET_REQUEST.md`
- `docs/designTargets/generatedArtManifest.md`
- `docs/patches/agentA_export_presets.diff`
- `docs/patches/agentA_project_godot.diff`
- `docs/patches/agentF_care_overlay.diff`
- `game/assets/characters/buddy/pinkGirl/pinkGirlBuddy_v01.glb`
- `game/assets/characters/buddy/pinkGirl/pinkGirlBuddy_v01_faces.json`
- `game/audio/voice/README.md`
- `game/content/audio/manifest.json`
- `game/content/localization/helpers_ar.json`
- `game/content/localization/helpers_hi.json`
- `game/content/localization/helpers_ja.json`
- `game/content/localization/helpers_th.json`
- `game/content/localization/helpers_zh.json`
- `game/content/localization/keys_en.json`
- `game/export_presets.cfg`
- `game/project.godot`
- `game/scenes/baby_room/baby_room.gd`
- `game/scenes/dress_up/dress_up.tscn`
- `game/scenes/feeding/feeding_table.tscn`
- `game/scenes/main/main.gd`
- `game/scenes/parent/parent_settings.gd`
- `game/scenes/parent/parent_settings.tscn`
- `game/scenes/progression/session_summary.gd`
- `game/scenes/progression/session_summary.tscn`
- `game/scenes/splash/splash.tscn`
- `game/scripts/audio/audio_director.gd`
- `game/scripts/audio/music_binder.gd`
- `game/scripts/branding/logo_title.gd`
- `game/scripts/branding/scene_transition.gd`
- `game/scripts/branding/splash.gd`
- `game/scripts/care/care_overlay.gd`
- `game/scripts/care/child_actor.gd`
- `game/scripts/care/child_life.gd`
- `game/scripts/care/child_needs.gd`
- `game/scripts/care/child_presentation.gd`
- `game/scripts/character/character_movement_controller.gd`
- `game/scripts/character/little_buddy_character.gd`
- `game/scripts/characters/buddy/buddy_face.gd`
- `game/scripts/characters/buddy/buddy_hair_sway.gd`
- `game/scripts/characters/buddy/buddy_life_clips.gd`
- `game/scripts/characters/buddy/pink_girl_buddy.gd`
- `game/scripts/characters/contact_shadow.gd`
- `game/scripts/characters/little_buddy/baby_face_moods.gd`
- `game/scripts/characters/little_buddy/baby_life_clips.gd`
- `game/scripts/characters/little_buddy/baby_little_buddy.gd`
- `game/scripts/feeding/feeding_hud.gd`
- `game/scripts/feeding/feeding_item.gd`
- `game/scripts/feeding/feeding_props.gd`
- `game/scripts/feeding/feeding_rules.gd`
- `game/scripts/feeding/feeding_table.gd`
- `game/scripts/gameplay/drop_zone.gd`
- `game/scripts/gameplay/house_freeplay_acts.gd`
- `game/scripts/gameplay/house_freeplay_director.gd`
- `game/scripts/gameplay/house_freeplay_words.gd`
- `game/scripts/gameplay/house_hud.gd`
- `game/scripts/gameplay/mission_runner.gd`
- `game/scripts/gameplay/mode_handler.gd`
- `game/scripts/house/house_layout.gd`
- `game/scripts/house/room.gd`
- `game/scripts/house/room_props.gd`
- `game/scripts/house/room_transition_controller.gd`
- `game/scripts/interaction/affordance_layer.gd`
- `game/scripts/interaction/affordance_rules.gd`
- `game/scripts/interaction/carry_controller.gd`
- `game/scripts/interaction/pose_modifier.gd`
- `game/scripts/localization/helper_font.gd`
- `game/scripts/localization/localization.gd`
- `game/scripts/menu/dress_up_screen.gd`
- `game/scripts/menu/menu_departure.gd`
- `game/scripts/menu/menu_garden.gd`
- `game/scripts/navigation/navigation_controller.gd`
- `game/scripts/parent_settings/parent_settings_model.gd`
- `game/scripts/progression/celebration.gd`
- `game/scripts/progression/sticker_cell.gd`
- `game/scripts/speech/speech_service.gd`
- `game/scripts/speech/tts_service.gd`
- `game/scripts/speech/voice_lines.gd`
- `game/scripts/ui/rating_star.gd`
- `game/scripts/ui/speech_feedback.gd`
- `game/tests/cases/test_affordance.gd`
- `game/tests/cases/test_aliz_life.gd`
- `game/tests/cases/test_audio_music_manifest.gd`
- `game/tests/cases/test_branding_assets.gd`
- `game/tests/cases/test_branding_splash.gd`
- `game/tests/cases/test_branding_transition.gd`
- `game/tests/cases/test_bunny_face.gd`
- `game/tests/cases/test_carry_bunny.gd`
- `game/tests/cases/test_click_to_move_freeze.gd`
- `game/tests/cases/test_feeding_table.gd`
- `game/tests/cases/test_freeplay.gd`
- `game/tests/cases/test_freeplay_acts.gd`
- `game/tests/cases/test_hud_helper_language.gd`
- `game/tests/cases/test_interaction_ux.gd`
- `game/tests/cases/test_localization.gd`
- `game/tests/cases/test_menu_wow.gd`
- `game/tests/cases/test_parent_settings_model.gd`
- `game/tests/cases/test_parent_settings_screen.gd`
- `game/tests/cases/test_speech_end_states.gd`
- `game/tests/cases/test_tts_service.gd`
- `game/tests/cases/test_tts_voice_lines.gd`
- `game/tests/cases/test_ui_contrast.gd`
- `game/tests/run_one.gd`
- `game/tests/shots_feeding.gd`
- `game/tests/shots_menu.gd`
- `game/tests/shots_settings.gd`
- `game/tests/shots_ux.gd`
- `tools/aliz_face_pass.py`
- `tools/aliz_face_sheet.py`
- `tools/aliz_face_strip.py`
- `tools/aliz_ortho_face.py`
- `tools/aliz_shots.gd`
- `tools/branding_icons.py`
- `tools/branding_logo.py`
- `tools/branding_shots.gd`
- `tools/branding_splash.gd`
- `tools/bunny_face_strip.py`
- `tools/bunny_shots.gd`
