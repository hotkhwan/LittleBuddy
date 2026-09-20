# iPad quick check — Little Days Founder Preview

One page for Khwan. Ten minutes on the real iPad, no coaching. Full sheet with
every step and the sign-off block: `docs/DEVICE_QA_CHECKLIST.md`. This card only
adds what the MacBook found on 2026-09-20.

## Before you can install — two things only you can do

1. **Sign in to Xcode.** On this MacBook Xcode has **no Apple ID, no signing
   certificate and no provisioning profile** (`security find-identity` reports
   zero identities). Xcode → Settings → Accounts → **+** → your Apple ID. Then
   open the project, select the LittleBuddy target → Signing & Capabilities,
   and pick your team. Xcode creates the certificate and profile itself.
2. **Plug in the iPad.** Only an iPhone 14 Pro Max was attached when this was
   written; no iPad has been seen by this Mac yet. Unlock it, tap Trust, and
   turn on Settings → Privacy & Security → **Developer Mode** (restart).

Then:

```sh
open ~/Projects/LittleBuddy-latest/build/ios/LittleBuddy.xcodeproj
```

Pick the iPad in the run-destination menu, ⌘R. First launch stops on
"Untrusted Developer": Settings → General → VPN & Device Management → trust
your Apple ID, then tap the **Little Days** icon.

`tools/export_ios.sh` deletes and recreates `build/ios`, so choose the team in
Xcode **after** the last export, or set it once in `game/export_presets.cfg`.

## The walk — expected flow

Launch → Main Menu → Aliz & Bunny → **I'm Hungry!** → Kitchen → Prepare Milk →
Feed Bunny → Mission Complete → **Snack Time**.

| # | Do this | PASS looks like | ☐ |
|---|---|---|---|
| 1 | Launch, hold landscape | No crash, no black frame, no sideways UI | ☐ |
| 2 | Listen | **No music is correct.** Effects and the spoken prompt still play. Music playing is a FAIL. | ☐ |
| 3 | Look at Aliz | Pink hair, striped dress, on screen, not in the floor. Her rough hair and chin are already known. | ☐ |
| 4 | Look at Bunny | A clearly different, smaller character, upright, "I'm hungry!" shown | ☐ |
| 5 | Read the room signs | KITCHEN / BATHROOM readable from arm's length | ☐ |
| 6 | Walk Aliz to the kitchen | Tap the floor or use the joystick. Legs move, no sliding, goes through the door | ☐ |
| 7 | Camera | Room framed, nothing important off the edge or under the rounded corners | ☐ |
| 8 | Open the fridge, take the bottle | Door swings, bottle appears in her hands, not floating | ☐ |
| 9 | Prepare the milk | Hold, then shake. Bar fills, liquid changes | ☐ |
| 10 | Carry it back | Bottle stays in her hands through the door | ☐ |
| 11 | Feed Bunny | Bottle at his mouth, he reacts, progress visible | ☐ |
| 12 | Mission complete | Reward shown, Bunny happy | ☐ |
| 13 | Reward once | Stars go up **once**. Leave and come back: they must not go up again | ☐ |
| 14 | Snack Time | Fridge → banana → counter → spoon → mash → feed | ☐ |
| 15 | HUD | Text never covers Bunny's face; every word readable | ☐ |
| 16 | **Speech** | Tap Speak, say "milk". Either it hears you, **or** it says voice is not ready and you can tap instead. | ☐ |
| 17 | **Silent test** | Tap Speak and say nothing. The task must **not** complete by itself. If it does, that is a hard FAIL. | ☐ |
| 18 | Touch fallback | Parent Corner (Grown-ups) → Voice off. Every task still finishable by touch | ☐ |
| 19 | Save, soft | Swipe the app away, relaunch. Stars and progress return | ☐ |
| 20 | Save, cold | Reboot the iPad, relaunch. Same | ☐ |

Stop and write it down if: it crashes, Aliz gets stuck, anything is unreadable,
the iPad gets hot, a reward is granted twice, or progress is lost.

## Speech evidence to send back

Parent Corner → **Check speech** names the root cause in one line. Then, from
the Mac:

```sh
xcrun devicectl device copy from --device <UDID> \
  --domain-type appDataContainer --domain-identifier com.pointit.littlebuddy \
  --source Documents/speech_diag.json --destination ./speech_diag.json
```

`backend` should read `ios`. `mock` on a device is a bug, not a result.

## Sign-off — Khwan only

| | |
|---|---|
| Date | |
| iPad model + iPadOS | |
| Passed | ___ / 20 |
| Speech heard "milk"? | ☐ Yes ☐ Unavailable ☐ Accepted a word I did not say |
| **Ship the Founder Preview to the family?** | ☐ Yes ☐ No ☐ Fix first |
