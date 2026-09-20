# iPad quick check — Little Days Founder Preview

One page for Khwan. Ten minutes on the real iPad, no coaching. Full sheet with
every step and the sign-off block: `docs/DEVICE_QA_CHECKLIST.md`. This card only
adds what the MacBook found on 2026-09-20.

## Before you can install

**Signing is now set up** (checked 2026-09-20 midday): one identity,
`Apple Development: hotkhwan@gmail.com`, team **`YZSLV4272S`**. The iPhone 14
Pro Max is connected. No iPad has been seen by this Mac yet.

**One thing to expect in Xcode.** The exported project carries
`DEVELOPMENT_TEAM = JZDAUN45CF` from `game/export_presets.cfg` (the Mac Mini's
setting). If your Apple ID is a member of that team, Xcode will be quiet. If it
is not, Signing & Capabilities shows a red "No account for team JZDAUN45CF":
pick **your** team from the Team dropdown and carry on. That choice lives in
`build/ios`, which `tools/export_ios.sh` deletes on every export, so after any
re-export you pick it again, or tell me to change `application/app_store_team_id`
in the preset to `YZSLV4272S`. Nothing here was changed for you.

Then: unlock the device, tap Trust, and turn on Settings → Privacy & Security →
**Developer Mode** (it restarts).

Then:

```sh
open ~/Projects/LittleBuddy-latest/build/ios/LittleBuddy.xcodeproj
```

Pick the iPad in the run-destination menu, ⌘R. First launch stops on
"Untrusted Developer": Settings → General → VPN & Device Management → trust
your Apple ID, then tap the **Little Days** icon.

`tools/export_ios.sh` deletes and recreates `build/ios`, so choose the team in
Xcode **after** the last export, or set it once in `game/export_presets.cfg`.

## iPhone 14 Pro Max first — same build, same steps

The iPhone that is already plugged in is a valid first device: the export
targets iPhone + iPad (`TARGETED_DEVICE_FAMILY 1,2`), iOS 15+, landscape only.
Pick "iPhone" in the run-destination menu instead of the iPad and ⌘R. Developer
Mode and the "Untrusted Developer" trust step are identical.

Two things to judge on the phone that the iPad cannot show you, then carry on
with the same table below:

| # | On the iPhone | PASS looks like | ☐ |
|---|---|---|---|
| P1 | Notch / Dynamic Island side | No text or button under the island or the rounded corners; the star count and the `Grown-ups` chip are fully visible | ☐ |
| P2 | Home indicator | The progress bar and `Next` sit above it, not under it | ☐ |

Everything else on the phone is the iPad list. The layout was designed for the
4:3 iPad; note anything that looks cramped, it is useful information, not a FAIL.

## The walk — expected flow

Launch → Main Menu → Aliz & Bunny → **I'm Hungry!** → Kitchen → Prepare Milk →
Feed Bunny → Mission Complete → **Snack Time**.

| # | Do this | PASS looks like | ☐ |
|---|---|---|---|
| 1 | Launch, hold landscape | No crash, no black frame, no sideways UI | ☐ |
| 2 | Listen | **Music now plays**: the Little Days theme on the menu, the I'm Hungry! track in the mission (owner cleared the rights 2026-09-20). Effects and the spoken prompt too. Music stops on mute; it must not restart when Aliz changes room. | ☐ |
| 3 | Look at Aliz | Pink hair, striped dress, on screen, not in the floor. Her rough hair and chin are already known. | ☐ |
| 4 | Look at Bunny | A clearly different, smaller character, upright, "I'm hungry, Aliz!" in a cream speech bubble that never covers a face | ☐ |
| 5 | Read the room signs | KITCHEN / BATHROOM readable from arm's length | ☐ |
| 6 | Walk, then run | Tap the floor to walk. Push the joystick past its inner ring: she **runs clearly faster** (about 1.5x). Legs match the pace, no sliding | ☐ |
| 6b | Badges | Near the fridge, a door, the toy box or Bunny a round coloured badge appears (OPEN / ENTER / TAKE / HUG / CARRY). Tapping it acts. It never sits on the joystick, Home or Next | ☐ |
| 6c | Carry Bunny | Near Bunny, tap CARRY: she picks him up and holds him in front of her body; walk a few steps; tap PLACE: he stands where you put him. Exactly one Bunny at all times | ☐ |
| 6d | Carry a toy | TAKE the teddy (or a bottle), see it in her hand, PLACE it on its spot | ☐ |
| 7 | Camera | Room framed, nothing important off the edge or under the rounded corners | ☐ |
| 8 | Open the fridge, take the bottle | Door swings, bottle appears in her hands, not floating | ☐ |
| 9 | Prepare the milk | Hold, then shake. Bar fills, liquid changes | ☐ |
| 10 | Carry it back | Bottle stays in her hands through the door | ☐ |
| 11 | Feed Bunny | Bottle at his mouth, he reacts, progress visible | ☐ |
| 12 | Mission complete | Reward shown, Bunny happy and his line is "Thank you, Aliz!" | ☐ |
| 12b | Home | Tap the round Home button (top right): "Take a break?" card with Continue / Home / Grown-ups. Continue resumes exactly; Home returns to the title and "Continue" brings you back to the same room | ☐ |
| 12c | Version | Tiny "0.1.0" bottom-right, not under Next or the joystick | ☐ |
| 13 | Reward once | Stars go up **once**. Leave and come back: they must not go up again | ☐ |
| 14 | Snack Time | Fridge → banana → counter → spoon → mash → feed | ☐ |
| 15 | HUD | Text never covers Bunny's face; every word readable | ☐ |
| 16 | **Speech** | Tap Speak, say "milk". You should see "I hear: milk" then Great!, and the task completes. Or it honestly says voice is not ready and you can tap instead. The spoken voice is the device's best English voice (download "Zoe (Premium)" or "Samantha (Enhanced)" under Settings → Accessibility → Spoken Content → Voices for a warmer one). | ☐ |
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
| Device (iPad / iPhone 14 Pro Max) + OS version | |
| Passed | ___ / 26 (iPad) · ___ / 28 (iPhone) |
| Speech heard "milk"? | ☐ Yes ☐ Unavailable ☐ Accepted a word I did not say |
| **Ship the Founder Preview to the family?** | ☐ Yes ☐ No ☐ Fix first |
