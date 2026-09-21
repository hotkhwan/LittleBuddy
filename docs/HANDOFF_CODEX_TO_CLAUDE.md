# Little Days — night visual production handoff

Branch: `feature/codex-ui-polish`.
Baseline: `345339e32482c55db59dcd493d272f8e834bd26c` (V3, app 0.1.1).
Final validated production/evidence commit SHA: `7fa15ba2785993a94023813846e7b0873d9a0187`.
This handoff is a subsequent documentation-only commit; its SHA is returned by
`git log -1 --format=%H -- docs/HANDOFF_CODEX_TO_CLAUDE.md` and is reported to the owner.
No merge into `feature/ui-meshy-cloud`. App version remains 0.1.1.

## What changed

- **Main menu:** welcome subtitle moved under the accepted logo, no longer across Bunny's face. Existing logo animation and accessible destination cards retained.
- **Activity picker:** nine cards form a balanced three-column grid; consistent shaded activity pictures, original approved destination artwork, a readable invitation and rounded backdrop. Card hit targets remain 240×240.
- **House feeding / bath / towel:** cream instruction card, mint feedback card, shared typography, framed human-baby illustration, smaller decorative activity art, rounded towel and a transparent render of the accepted bottle. Dark full-width cinema bars removed visually; mouth/scrub targets and progress logic unchanged. Texture lifetime explicitly retained to prevent white-box rendering.
- **Highchair / Baby Room:** approved Home picture replaces bespoke silhouette; smaller painted frames inside original 200×200 navigation and 240×240 microphone targets. Clear Home/Back captions, consistent prompt/helper/count roles and less bulky legacy controls. Same scene paths, signals and safe-area behavior.
- **Free Play / bedtime / tidy:** quiet read-only activity tags use existing director state, with no timers or new objectives. Tags are registered as visual keep-outs for interaction badges and disappear during care/chooser/pause. Pause card shares the rounded surface/button system.
- **Food chooser:** cream question header, softer shadows, colour-backed word labels, accepted live-mesh pictures and existing 260×300 targets. Actual staged fruit now matches kitchen/choice-card art.
- **Story missions:** cream instruction cards and a separate wrapping chapter capsule replace outlined text over room textures. Long bedtime title no longer extends beneath Home. Camera-dependent FEED layout remains left-aligned and off faces; care retains narration ownership.
- **Classroom:** glossy teaching illustrations and word bands, larger wide-screen answer cards with a group label, state emblems, speaker waves for speaking, shared exit/resume/break surfaces. Aliz's face and hands stay clear. Tutor conversation/session/cloud/mock wiring untouched.
- **Dress Up:** ribbon-shaped bows, stronger selected/feedback treatment, clearer colour-studio hierarchy and useful child instructions instead of roadmap copy. Still four existing colour choices, not invented clothing categories or rewards.
- **Typography/icons:** continued system-font/Thai fallback roles from V3. Added original shaded bath, bowl, brush, moon, sun and tidy SVGs and a bottle render; no new font, paid image generation, logo/app-icon concept or replacement character.

## Files changed

Complete exact manifest, including tests/source art/PNG evidence: [NIGHT_UI_FILES.txt](NIGHT_UI_FILES.txt).
Audit and per-route findings: [NIGHT_UI_AUDIT.md](NIGHT_UI_AUDIT.md).
No changes to Cloudflare, billing, speech recognition, tutor conversation logic,
navigation algorithms, iOS native framework or export scripts.

## Visual contracts to preserve

1. Use the **1024-high expanding design canvas** when judging layouts. A raw1334×750 SubViewport is not the shipped UI scale. Harnesses set `size_2d_override` and assert image dimensions.
2. Painted art may be smaller than a hit target. Do not reduce main/picker240×240, food260×300, legacy microphone240×240, legacy navigation200×200, Dress Up200×220 / Back280×160, or Classroom Talk200 / Repeat-Picture110 / Mute120 effective bounds. Preserve transparent-margin `_has_point` behavior and tests.
3. `storybook_chrome.gd` owns shared radius28, cream border, soft shadow, pressed/disabled/focus treatment. It must not change control sizes or eat input. Decorative panels/icons use `MOUSE_FILTER_IGNORE`.
4. Keep `typography.gd` roles and HelperFont fallback for Thai. Preserve natural line metrics, word-smart wrapping and chapter wrapping before Home. No percentage pronunciation scores, failure Xs or countdown pressure.
5. Care gesture geometry is unchanged: face190 radius, mouth offset/radius, target projection, hold durations, scrub distance and towel coverage. Never move those targets merely to align decoration. Keep `_bottle_art` referenced between draws.
6. House story narration and care narration must not overlap. `set_narration_covered()` hides the story card but not Home/Next escape controls. FEED is a left-side rail; do not put its prompt back across the face.
7. Free Play activity tags are **read-only presentation**. Do not let them start/end activities, change rewards, manipulate input or add timers. Keep their affordance keep-out rectangles.
8. All prop upgrades retain semantic IDs, base pivots, collider/grab envelopes and original presentation sizes. Kitchen/chooser/room fruit should share accepted GLBs. Highchair peel/liquid components are separate and were intentionally not swapped blindly.
9. Preserve accepted logo/characters/teddy/toy box/fruit/bottle. The night sprint generated no new Meshy assets. New block GLB is a normalized derivative of already accepted classroom blocks.

## Node names and API seams not to rename casually

- Main: `UI/SafeArea/{TitlePanel,PlayButton,FreePlayButton,DressUpButton,ParentButton,LearnWithAlizButton,SubtitleStrip}` and their existing icon/caption children.
- Activity picker: `Backdrop`, `TitleLabel`, `BackButton`, `Scroll/Centre/Cards`, `Card_<missionId>/{Picture,Caption,Stars}`; `activity_chosen(mission_id)`, `back_pressed`, `entries_for`, `get_cards`.
- Baby Room: `UI/SafeArea/TopStack/SpeechBubble/SpeechBubbleVBox/{PromptLabel,ThaiHintLabel}`, `ProgressDots`, `LevelChapterLabel`, `StarCounter/StarCountLabel`, `StickerButton`, `NextButton`, `MicButton`, `ListeningLabel`, `EncouragementLabel`. `room_ui_polish.gd` extends existing SafeArea behavior rather than replacing it.
- Activity staging: `ObjectAnchor`, `Spawn1`–`Spawn4`, `MouthDropZone`, `HugDropZone`, `DressDropZone`, `HandDropZone`, `BathDropZone` remain unchanged.
- Feeding HUD: `SafeArea`, `Overlay`, `PromptBar` and its `PromptLabel`/`HelperLabel` descendants, `StarCounter` and its `StarCountLabel`, `TaskStar`, `Hint`, `SubtitleStrip`, `Encouragement`/`EncouragementLabel`; keep every existing public method/signal and liquid/peel gameplay binding.
- House HUD: `Prompt`, `ThaiHint`, `Caption`, `StoryInstructionCard`, `ActivityTag/{ActivityIcon,ActivityLabel}`, existing Home/Next/Speak controls and all `set_*`, `get_*`, pause/settings signals.
- CareOverlay: `Scrim`, `BandTop`, `BandBottom`, `Face`, `Tool`, `Title`, `Helper`, `Hint`, `ChildLine`, `Progress`; new `InstructionCard/CareActivityIcon`, `CareFeedbackCard`; `begin`, `apply_hold`, `apply_stroke`, `complete_by_touch`, `care_completed`, `care_progress` unchanged.
- FoodChooser: `Cards`, `Title`, card `Picture`, `ObjectPreview`, `Word`; `picked(item_id)` and `dismissed` unchanged.
- TutorHud: `SafeArea`, `LearningShelf`, `Banner`, `Subtitle`, `Flashcard/Art`, `EndButton`, `MicIndicator`, `AnswerCards/Answer_<id>/Art`, `ResumeCard/Card/ContinueButton`; keep touch button APIs and all tutor signal names. New artwork/state glyphs are presentation only.
- Dress Up: `UI/SafeArea/{TitlePanel/TitleLabel,HintLabel,SwatchRow,BackButton/BackIcon,BackButton/BackCaption}`; `apply_swatch` and persisted IDs unchanged.

## Meshy / art integration

**0 credits spent, 0 new paid tasks, 0 rejected generations.** Balance was not
queried during this sprint; last verified ledger balance is3129 from V3, not a
claim about other agents' subsequent spending. See [shared ledger](MESHY_CREDIT_LEDGER.md).

- New runtime derivative: `game/assets/models/meshy-props/toyBlocks.glb`,2547tris, one surface,512 texture,0.26m, original0.34m grab envelope. Used by ObjectSpawner real `blocks` in Baby Room/house tidy. Original task IDs/provenance preserved; manifest cost0 records adaptation, not generation.
- Existing `apple.glb`/`banana.glb` now also used by ObjectSpawner real fruit IDs at0.19/0.25m. No duplicate fruit assets. Milk carton remains a carton; it was not wrongly substituted with an empty bottle.
- `care_bottle.png` is a transparent256px render of accepted `babyBottle.glb`, used in care and picker. Regenerate with `tests/render_care_bottle_icon.gd`.
- Refrigerator, accepted classroom furniture and wardrobe retained after review. No visual defect justified paid assembly replacement.

## Screenshots / comparison gates

All under `docs/shots/night/`; **25 required comparison pairs** validated at
exactly1334×750, with non-identical before/after pixels and visual review. These
are actual game renders, not concept mockups. Additional2340×1080 phone-like
captures cover menu/picker, classroom states, Dress Up, highchair, Baby Room,
legacy missions, care, bedtime, tidy, chooser and pause.

| Screen | Before → after filenames |
|---|---|
| Main / picker | `main_menu_{before,after}.png`, `activity_picker_{before,after}.png` |
| Classroom / Dress Up | `{before,after}_{classroom,dress}_1334x750.png` |
| Classroom states | `{before,after}_{answers,classroom_listening,classroom_thinking,classroom_speaking,classroom_success,classroom_thai}_*.png` |
| House feeding | `freeplay_feed_{before,after}.png` |
| Bath / towel | `bath_care_{before,after}.png`, `bath_dry_after*.png` |
| Bedtime / tidy | `freeplay_{bedtime,tidy}_{before,after}.png` |
| Baby Room / highchair | `{baby_room,feeding}_{before,after}_1334x750.png` |
| Legacy mission UI | `{bath_mission,bedtime_mission,tidy_mission}_{before,after}_1334x750.png` |
| Food chooser | `freeplay_chooser_{before,after}.png` |
| Reused props | `blocks_{before,after}.png`, `fruit_{before,after}.png` |
| All 9 current missions | `mission_<missionId>_{before,after}.png` |

Comparison caveat: dimensions and asserted task/route are fixed; some legacy
mission random objects, stars/progress, idle poses and recorded subtitles differ.
Do not interpret those differences as new gameplay/rewards. The bath baseline is
the original V3 CareOverlay source replayed through the real bathroom route,
without reverting working files. Optional reproduction is documented in the
night-house harness; the temporary baseline source is not shipped.

## Validation

Godot 4.7.2 on macOS/Metal. No physical-device PASS, no iOS export.

- Full `tests/run_tests.gd`: **171 cases,0 failures**, including layout, care gestures, feeding, prop provenance/budgets, wardrobe, frozen content, routing and UI contracts.
- Focused tutor suite: **16 cases,0 failures**. Transparent-margin clicks and responsive answer-card bounds checked by classroom harness.
- `tests/input_settings_harness.gd`: **INPUT SETTINGS OK**, actual taps/scroll/sliders/fixed footer at1334×750,2340×1080,1024×768.
- `shots_night_house.gd`: both aspects PASS; hunger100→30, chooser, tidy, bedtime, actual bathroom wash→towel gesture and touch fallback, pause.
- `shots_night_missions.gd`: **9 initial routes,0 failures**; actual requested mission, running director, current task and nonempty plan. Not nine full gameplay completions.
- Night activities / classroom / blocks / fruit harnesses: PASS. English/Thai and face/hand clearance visually reviewed.
- `check_night_evidence.gd`: **25 pairs,0 failures**.
- Editor import/scene parsing: complete, no script parse errors. `git diff --check`: clean.

Expected warnings remain: absent native speech framework, editor ADB warning,
pre-existing headless out-of-tree/cleanup resource messages. No attempt to repair
the native plugin; passing assertions do not imply a warning-free iOS build.

## Functional findings left for Claude / remaining visual limits

1. `goodMorningRoutine` can show a hungry child bubble and CARRY affordance while instructing wake-up. State/priority issue, not fixed in this visual branch.
2. `snackTime` can show a nearby bedroom ENTER affordance while telling the child to tap the fridge. Affordance priority/guidance issue; no pathfinding/routing changes made.
3. Frozen blocks metadata still says `colorWord: green`; no authored green-block lesson exists. Resolve before adding such a colour lesson. Content was not changed to disguise the pre-existing mismatch.
4. Separate highchair peelable banana/drainable bottle and the Say It milk carton remain older geometry. Any replacement must preserve peel/liquid behavior; do not merely swap shells and hide feedback.
5. Legacy nursery/world props and illustrated wash portrait remain simpler than the strongest 3D/illustrated assets. Dress Up still has only four accessory colours. No invented categories, wardrobe inventory or fake rewards.
6. Real iPhone/iPad safe areas, Thai reading comfort, audio/mic permissions and sustained performance still require owner testing. Desktop aspect renders are not physical-device certification.

The sprint stops here. No backend, speech, billing, native-framework, navigation
or state-machine work is implied by this handoff.
