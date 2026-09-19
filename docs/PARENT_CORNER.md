# Parent Corner

Everything a grown-up can do, and nothing a child can reach.

Scene: `game/scenes/parent/parent_settings.tscn` + `game/scenes/parent/parent_settings.gd`.
Gate: `game/scripts/parent_settings/parental_gate.gd`.

---

## The gate

While locked, Parent Corner renders **one small, dull gear in a corner** and passes every other
touch straight through to the game underneath. Opening it needs a continuous
**3.0-second press-and-hold** — long enough that a toddler's tap, drag or double-tap cannot do
it, with no numbers to read and no maths puzzle.

Destructive actions get a second gate of their own: "Reset progress" reveals a confirmation
that itself needs a full 3-second hold.

The gate has not been weakened, shortened or bypassed. `test_parent_gate.gd` pins the timing
behaviour; `test_entitlement_no_purchase_guard.gd` additionally asserts the 3.0-second default,
that both gates in the scene still carry it, and that the panel still shows its gate by default.

---

## What is behind it

| Section | What it does |
| --- | --- |
| Thai hints | on / off |
| Voice (speech) | on / off — the game is fully playable by touch either way |
| Speaking speed | slow / normal |
| Stars earned | read-only count |
| Check speech | collapsed by default; on-device speech diagnostics in plain words |
| Replay Mission 01 | clears **one** level's completion and rating; never touches stars or settings |
| Reset progress | two-step, second step is a 3-second hold |
| **Family Club** | informational pricing. **Nothing can be bought.** |
| **Songs for Fun** | the one external link in the product, shown as text to copy |
| Done | closes the panel |

Sections built in code rather than in the `.tscn` (the speech check, Replay Mission 01, Family
Club) are built that way on purpose: the copy, the prices and the rules about them live in one
file that can be reviewed as a whole, instead of being split between a script and a scene where
the two can drift.

---

## Family Club section

Displays: Free Starter (free forever), Family Club **USD 2.99 / month**, Thailand
**THB 99 / month**, and the plain statement that **annual pricing is not decided yet, so there
is none to show**.

It also says, in the UI and not only in a comment: *"Nothing can be bought in this app. This
build has no payment of any kind; these prices are information only."*

There is no payment SDK, no product id, no receipt and no purchase path anywhere in the
repository. Full detail and the list of what is intentionally not implemented:
**`docs/FAMILY_CLUB.md`**.

The "what you already have" line is generated from the Free Starter data
(`free_starter.gd`), so the screen cannot describe an offer different from the one the game
grants.

### Copy rules, enforced by test

* no urgency or scarcity: "hurry", "limited time", "today only", "last chance", "countdown",
  "expires" are all rejected;
* **Buddy is never sad, needy or disappointed about money** — "buddy is sad", "buddy misses",
  "buddy needs", "unlock me" are rejected;
* no invented annual price ("/ year", "per year", "annually", any number for it);
* no percentages;
* nothing child-facing may mention paying, subscribing, a price or an outside service. The
  guard sweeps every child-facing script and scene for the link, the price fragments and that
  vocabulary.

---

## Songs for Fun

<https://www.youtube.com/@Songsforfun-1> — a free YouTube channel, for a parent.

How it behaves, and why:

1. It lives **inside the gated panel**, so a child never reaches it.
2. It is **hidden until a grown-up taps "Songs for Fun"**. A parent adjusting Thai hints never
   has an external link sitting open on the screen their child is about to be handed back.
3. It is **shown as text**, with a **"Copy link"** button that needs a **second, confirming
   tap** ("Tap again to copy the link"). Even copying gets a confirm step, so a mis-tap cannot
   do it.
4. **This build never calls `OS.shell_open()`.** The game cannot hand anybody — least of all a
   child — to a browser, an autoplaying video or a recommendation feed. A parent opens the link
   themselves, on their own device, in their own time. The status line says so:
   *"Link copied. Open it in your own browser, not here."*
5. It is **never autoplayed, never spoken, never animated** and never offered during play.
6. Closing the panel puts it away; re-opening does not remember that it was revealed.
7. The URL is the plain channel address: no `?`, no `&`, no `autoplay`, no `embed`, no
   `watch?v=`.
8. The link exists in **exactly one file** (`parent_settings.gd`) and in no scene file, so
   there is no second copy to be surfaced somewhere a child can reach.

Points 1-8 are all asserted in `game/tests/cases/test_entitlement_no_purchase_guard.gd`, which
drives the real panel: locked → opened → revealed → armed → copied → closed → re-opened.

---

## Offline and private

Local settings only, via the `SaveService` autoload (looked up defensively — the panel works in
a scene preview and a test run with no autoloads at all). No analytics, no account, no network
call, and no child microphone audio or transcript is ever persisted or uploaded
(`docs/SPEECH_DEVICE_VALIDATION.md`, `test_speech_privacy_guard.gd`).
