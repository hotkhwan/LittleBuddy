# Feeding close-up — the real Bunny, 2026-09-20

**Zero Meshy credits. No new asset. No scene file changed.** Four scripts and
one harness.

## What was wrong

The `giveBottle` act opened `care_overlay.gd`, which drew a flat pink disc with
dot eyes over the whole screen and asked the child to hold the bottle at the
disc's mouth. The rigged Bunny — with a real `drink` clip and a real `mouth`
socket on the head bone — was right behind it, dimmed by the scrim and hidden
by the disc. The character on the rug and the character being fed did not look
like the same child (`docs/shots/macbook_rc_feed.png`).

The overlay's own doc explained the disc: the rig has no facial animation, so
the brushing/washing/drying acts are honestly illustrated. That reasoning is
right for those acts and wrong for the bottle, which is the one act whose
subject can be shown as himself.

## What changed

| File | Change |
|---|---|
| `camera_framing.gd` | `portrait_framing()`: same pitch, yaw and clamps as `focus_framing()`, fitted to a 0.42 m box with the room's 1.0 m corner headroom capped at 0.45 m and a 1.2 m standoff floor. Measured: the headroom on the box corners, not Bunny, was what bound the shot (1.80 m → 1.40 m). `focus_framing()` behaviour is unchanged; both call one `_fit_framing()`. |
| `room_camera.gd` | `focus_portrait()`, released by the existing `restore_room_frame()`. |
| `house_level_director.gd` | For `giveBottle` only: `_begin_portrait()` aims the portrait at the mouth socket's world position, hands the overlay a `Callable` that re-asks for it every frame, and suspends the per-frame two-shot re-aim (`_portrait_on`). `_on_care_completed()` and `_release_focus()` both undo it. Bunny's own need line is suppressed while any care overlay is open (guarded call, lands with the bubble pass). |
| `care_overlay.gd` | `FEED` draws no face. Full scrim → two bands (176 px top, 196 px bottom) so the copy stays readable and Bunny stays lit. `get_mouth_target()` projects the socket through the live camera into overlay coordinates; the hold test, the guidance ring, the progress arc and the milk drops all use it. `MOUTH_OFFSET` remains the fallback with no camera or socket. |
| `smoke_mission01.gd` | Aims the bottle at `get_mouth_target()` instead of a constant. |
| `shots_rc.gd` | Also captures the beat half-played and finished. |

Gameplay logic is untouched: same hold, same leak, same `care_completed`,
same `satisfy("hungry", 70)`, same star, same `Next` fallback. Mission 01 and
Mission 02 walkthroughs pass; suite 122/122.

## Evidence (real game, SubViewport, dimensions asserted)

| | |
|---|---|
| `docs/shots/feed_portrait_ipad.png` | 1334×750, opening frame |
| `docs/shots/feed_portrait_iphone.png` | 2340×1080, opening frame |
| `docs/shots/feed_portrait_mid_ipad.png` | half fed: arc filling on his face, drops, bar at 50% |
| `docs/shots/feed_portrait_done_ipad.png` | finished: overlay gone, Bunny celebrating, star +1, need line gone |

Camera at the beat, iPad: distance **1.40 m**, binding `vertical` on the near
floor corner, focus at his mouth (0.48, 0.52, 1.02).

## Honest limits

- Bunny's mouth does not open for the bottle; the rig has no jaw. The drink
  clip (hands up, head tipped) and the ring on his face are the reaction.
- Aliz is cropped at the left edge of the portrait. She is behind the camera
  in the fiction; her hair and dress edge are what is visible.
- The "I'm hungry!" 3D line overprints the title until the actor's
  `set_bubble_suppressed()` (bubble pass) is merged; the director already calls it.
- The joystick ring is faintly visible through the bottom band, as it was
  through the old full scrim.
