# Content packs

A content pack is a **catalogue**, never a program. It lists ids. It cannot add a mission, a
rule, a mini-game or a line of behaviour — that logic ships in the build and is tested there.

Packs are **local files inside the build**, under `res://content/packs/`. Nothing is
downloaded, ever. There is no downloader, no cache directory and no URL anywhere in this
layer, and the validator refuses any pack whose values contain one.

---

## The metadata, exactly nine fields

```json
{
  "packId": "farmFriends",
  "version": 3,
  "requiredGameVersion": "0.2.0",
  "missions": ["feedTheDucks"],
  "rooms": ["barn"],
  "characters": ["duck"],
  "outfits": ["raincoat"],
  "audio": ["quack"],
  "entitlementId": "familyClub"
}
```

| Field | Rules |
| --- | --- |
| `packId` | camelCase, unique, stable forever (it is how a pack is referred to and replaced) |
| `version` | whole number, `>= 1`, this pack's own revision |
| `requiredGameVersion` | `MAJOR.MINOR.PATCH`, the **oldest** build that can run the pack |
| `missions` | mission ids that **already exist in the build** |
| `rooms` / `characters` / `outfits` / `audio` | plain ids (letters, digits, underscore) |
| `entitlementId` | `freeStarter` or `familyClub` — see `docs/FAMILY_CLUB.md` |

JSON keys are camelCase, per `CLAUDE.md`. Unknown fields are ignored with a warning, not a
rejection: a pack authored for a later build may carry a field this one has no use for.

---

## Logic vs. catalogue — the point of the exercise

| Ships in the build, in code, tested | Ships in a pack, as data |
| --- | --- |
| mission templates and state machines | which missions a pack delivers |
| mini-game rules, star rules, drop zones | which rooms, characters, outfits, audio it names |
| speech intents, TTS prompts | which entitlement unlocks it |
| everything a child interacts with | nothing executable, ever |

A weekly content drop is therefore a **data drop against logic that already shipped**. That is
what makes weekly cadence survivable: a pack cannot break the game because there is no
mechanism by which it could.

---

## The validator

`scripts/content_packs/content_pack_validator.gd`. Returns the list of what is wrong, in
human words. Empty means acceptable.

Rejections:

1. **`requiredGameVersion` is newer than this build** — rejected *whole*, never half-loaded.
   Half-loading a pack authored against logic this build does not have is how a four-year-old
   reaches a mission with no ending. Ship the build first, then the pack.
2. **A mission id the build does not implement** — rejected. The logic has to exist before the
   pack may name it.
3. An unknown `entitlementId` — a pack gated behind a right that can never be granted is
   content nobody would ever see, so it is refused loudly rather than shipped dark.
4. No payload at all (nothing in any of the five list fields).
5. A malformed `packId` or `version`.
6. **Any value containing a URL, a `res://`/`user://` path, `..`, or a file extension**
   (`.gd`, `.tscn`, `.pck`, `.zip`, `.dylib`, …). A pack may only ever be a list of ids, so
   "no remote or executable content" is a property of the FORMAT rather than a promise in a
   document.

The build version it compares against is `GameVersion.BUILD` in
`scripts/content_packs/game_version.gd`, which `test_content_pack_validator.gd` asserts equals
the `VERSION` file at the repository root — the same technique `test_version.gd` uses for
`export_presets.cfg` and `CHANGELOG.md`.

**Bumping the release means bumping `GameVersion.BUILD` too.** The suite says so out loud.

---

## The shelf

`scripts/content_packs/content_pack_catalog.gd` reads `res://content/packs/index.json`, which
names its pack files explicitly (the same pattern `content/index.json` already uses):

```json
{ "contentVersion": 1, "packFiles": ["res://content/packs/free_starter.json"] }
```

* every path must sit under `res://content/packs/`;
* each file is read with `FileAccess` + `JSON.parse_string()` — **never `load()`, never
  `ResourceLoader`** — so a pack file cannot be a scene, a script or a resource with a script
  attached. `test_content_pack_catalog.gd` scans the source of this layer to keep it that way;
* a rejected pack is **kept, with its reasons**, not dropped. A build one release behind the
  content drop must be able to say *why* it refused a pack: on a device with no console, a
  silent disappearance is the one failure nobody can diagnose;
* duplicate `packId`s are rejected rather than allowed to shadow each other.

### What ships today

One pack: `free_starter.json`, the free tier (see `docs/FAMILY_CLUB.md`). It is an ordinary
pack and passes the ordinary validator — the free set is not a special case in the code.

### Gating

`entitled_packs(service)` and `entitled_missions(service)` are **queries**. No gameplay code
calls them, nothing is gated on them today, and a mission that appears in no pack is **not
locked** — it is simply not pack content. A catalogue that answered "locked" for everything it
had never heard of would close the shipped game the first time it loaded.

Nothing in this layer is child-facing. There is no "locked" badge, no teaser and no preview of
a pack a family does not have. A child sees the game they have.

---

## Authoring a weekly pack (procedure)

1. Implement and test the mission/mini-game logic **first**, in code.
2. Add its id to `missions.json` (content owner's file).
3. Write `res://content/packs/<name>.json` with the nine fields; set
   `requiredGameVersion` to the build that contains the logic from step 1.
4. Add the path to `res://content/packs/index.json`.
5. Run the suite. A pack that names something that does not exist fails
   `test_content_pack_catalog.gd` immediately, on your machine, not on a child's iPad.
