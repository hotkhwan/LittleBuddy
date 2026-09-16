# Placeholder Art

These are throwaway, project-owned SVG placeholders for the MVP. They are hand-written flat
shapes with soft child-friendly colors, kept small (well under 4 KB each) so they stay
lightweight on a low-spec Mac and an iPad. No copyrighted or traced third-party art was used.

Gameplay only uses these files if present (checked with `ResourceLoader.exists`) and otherwise
falls back to Godot-drawn primitive shapes, so every file here is a genuinely optional drop-in
replacement, not a hard dependency.

## Files and intended usage size

| File | Native size | Used at (approx) | Purpose |
|---|---|---|---|
| `baby.svg` | 200x200 | ~200x200 | Baby character face in the Baby Room |
| `milk_bottle.svg` | 120x200 | ~120x200 | Milk bottle the child taps/drags to feed the baby |
| `star.svg` | 100x100 | ~48x48–64x64 | Reward star icon in the stars counter |
| `mic.svg` | 100x140 | ~80x110 | Microphone button glyph for the speak prompt |
| `room_bg.svg` | 1366x1024 | full-screen background, landscape iPad | Baby Room backdrop |

SVGs import natively in Godot 4 and scale cleanly, so the "used at" sizes above are
approximate on-screen targets, not fixed constraints.

## Swapping for production art later

1. Replace the file at the same path with the same filename (or update the reference in the
   owning gameplay script if the filename changes).
2. Keep the same aspect ratio noted above so existing layout/anchors do not need rework.
3. Keep file sizes small (prefer optimized SVG or compressed PNG) to preserve performance on
   low-spec devices.
4. Re-run the game and confirm `ResourceLoader.exists` still finds the new file at the same
   `res://assets/placeholders/...` path, or update the path in gameplay code if it moved.
5. Nothing here should ever include scary iconography (no red X, no error imagery) per the
   Child UX rules in `LITTLE_BUDDY_TONIGHT.md`.
