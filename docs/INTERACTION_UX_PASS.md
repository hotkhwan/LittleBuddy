# Interaction UX pass (Agent B, 2026-09-20)

Owner feedback from the first cold playtest, and what changed. Branch `wt/ux`.

## 1. Home / pause

`house_hud.gd` gains a round peach **Home** button top-right (the title screen's
own house on it). It opens `scripts/ui/pause_menu.gd`: a cream card, *Take a
break?*, with **Continue** (mint, biggest, first), **Home** (peach) and
**Grown-ups** (lavender, smaller, last). While the card is up the room's taps,
the character and the affordance badges are held, and Continue gives back
exactly what was there (a character the summary had disabled stays disabled).

- Home flushes `SaveService.save_profile()` and calls
  `HouseWorld.leave_to_home()` through `has_method()`. No hook -> the card
  closes and play carries on; the HUD never swaps scenes itself and never
  terminates the app. Stars are persisted as they are awarded by the reward
  manager, so leaving mid-mission loses nothing and double-awards nothing.
- Grown-ups instantiates the existing `parent_settings.tscn` (gate on) over the
  running world; Done returns to the room.
- The card is not offered while the play chrome is off (summary open).

## 2. Version label

Bottom-right, 16 pt, text is exactly `GameVersion.BUILD`.
`HouseHud.version_label_rect(viewport, insets)` keeps it out from under Next
and moves it above Next when a bottom safe inset (home indicator) would push it
up; `SafeArea.insets_for()` is now static so the HUD can ask without being under
a `SafeArea` node. Asserted at 1366x1024, 1334x750, 2340x1080, 1180x820.

## 3. Tap indicator

`gesture_hint.gd`: the cream hand is gone. A peach arrow with an ink edge
bounces down onto a mint ring with gold sparkles; the drag demo carries a peach
token with a dotted trail. Same public API (`show_tap/show_ring/show_drag/
hide_hint/step`).

## 4. Icons

`icon_glyph.gd` gains an opt-in `backing_color` pastel disc (off by default,
so no existing scene changes). Next and Speak in the house HUD now carry the
pack's arrow and mic glyphs beside their words.

## 5. Proximity affordances

`scripts/interaction/affordance_layer.gd` (a `Control` overlay the HUD mounts
under its chrome) polls the `affordable` group every frame:

```
get_affordance(actor: Node3D) -> Dictionary   # {} or
  {"verb", "anchor": Vector3, "radius": float, "priority": int, "target": Node,
   optional "targetId", "extent"}
perform_affordance(actor: Node3D) -> bool     # optional; false = fall through
```

`affordance_rules.gd` (pure) picks one offer: mission target first (read from
the level director's plan), then priority, then distance. The badge is a
160 px verb-coloured disc with a drawn picture, a word pill, a 240 px hit box
and a pulsing ring on the object. It sits above the object, or beside it (away
from Aliz) when the top is taken by the prompt band. A tap falls through to
`NavigationController.apply_tap` so arrival behaviour is unchanged.

`ActivityTarget` implements the read half: doors -> ENTER; `open` -> OPEN;
`pickUp` -> TAKE; kitchen stations read live `KitchenState` (shut fridge OPEN,
open fridge TAKE, holding an item PLACE where it can go); storages OPEN. Agent
C's Bunny supplies `character: {canHug, canCarry, canFeed}` context or its own
`get_affordance()`.

## Evidence

`docs/shots/ux_{ipad,iphone}_{fridge_open,fridge_take,door_enter,pause,
tap_hint,home_version}.png`, produced by `tests/shots_ux.gd` at 1334x750 and
2340x1080 with the verb asserted before each frame and the PNG size asserted
after. Tests: `test_affordance.gd`, `test_interaction_ux.gd` (suite 124).

## For the lead

`docs/patches/agentB_house_world.gd.diff` (optional): mount the layer from the
world so first run has it too; the HUD stands its own copy down when it finds
one.
