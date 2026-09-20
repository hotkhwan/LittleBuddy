# Third-party notices

## Code adapted: RestaurantGame3DUnity

* **Project** — `KaganAyten/RestaurantGame3DUnity`
* **Licence** — MIT (verified 2026-09-19 via the GitHub API: `license.spdx_id == "MIT"`,
  `fork == false`)
* **What we took** — *mechanics, not code*. The project is Unity/C# and this one is
  Godot 4/GDScript, so nothing was copied or transliterated. Four design ideas were
  adapted, and they are worth naming precisely because they are the good part:

  1. **An item is a TYPE, and preparing it is a type-to-type mapping.** The reference
     has `ItemType.TOMATO -> ItemType.SLICEDTOM`. Ours is
     `scripts/kitchen/kitchen_items.gd`, as data rather than an enum, so content can
     add an ingredient without touching code.
  2. **Stations declare what they accept** (`IGetItem` / `IPutItem*` there;
     `accepts()` / `result_of()` here). A station that cannot take a thing says so,
     rather than the player being told off for trying.
  3. **One hand, one item.** The reference's `Inventory` holds a single `currentType`
     and refuses a second. Ours does the same, for the same reason: it is the rule
     that makes "where is the tomato?" answerable by looking at the room.
  4. **The visual is pre-placed children, toggled.** `Inventory.TakeItem()` activates
     the one child mesh matching the held type. This is why the reference's world
     visibly changes without spawning anything, and it is the trick this project
     needed most.

  Three things were deliberately **not** taken: the customer/order manager, the
  `UITimer` countdown, and the failure states that go with them. This is a game for
  a small child, and `CLAUDE.md` bans timers and failure pressure outright.

* **Attribution** — MIT requires the copyright notice be preserved with any copied
  source. No source was copied, so the obligation does not attach; this notice is
  recorded anyway because the design debt is real.

### Bundled third-party assets in that repository — NOT used

The reference repo's own MIT licence does not cover everything inside it. Checked
separately, as required, and **none of it is in this project**:

| Bundled | Location in reference | Status |
|---|---|---|
| DOTween (Demigiant) | `Assets/Plugins/Demigiant/DOTween/` | Own licence, not MIT. Not used — Godot has `Tween` built in. |
| TextMesh Pro | `Assets/TextMesh Pro/` | Unity Companion Licence. Not used. |
| EmojiOne sprites | `Assets/TextMesh Pro/Sprites/` | Carries its own `EmojiOne Attribution.txt`. Not used. |

No art, model, texture, font, sound, prefab, scene or UI layout was taken from the
reference project. Every kitchen prop in this game is either procedural geometry
built in `scripts/house/` or an asset this project generated for itself.

## Fonts for the helper line (2026-09-20)

No font file was added for the helper-language work. The helper line
(Thai / Chinese / Arabic / Hindi / Japanese) is drawn with Godot's default font
plus **system fonts already installed on the device** -- PingFang / Hiragino
(Apple, shipped with iOS and macOS), Thonburi, Geeza Pro, Kohinoor Devanagari --
resolved and validated at runtime by `game/scripts/localization/helper_font.gd`.
System fonts are used under the operating system's own licence and are not
redistributed with the app, so no notice is required here. A language whose
script no installed font can draw is shown as unavailable in Grown-ups rather
than rendered as boxes. Should a Noto subset ever be bundled instead, its
SIL Open Font License 1.1 text must be added to this file alongside it.
