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
| 1 | Launch, hold landscape | Cream boot image with the logo, then the splash (logo + three dots) hands over to the menu within 3 s. No crash, no sideways UI | ☐ |
| 1b | Menu | Storybook cottage garden, trees/flowers/clouds gently moving, Aliz and Bunny centred, the Little Days logo on top, four pastel buttons. Tap **Dress Up**: swatches recolour Aliz's bow, Back returns. Tap **Grown-ups**: a gate card with a 3 s hold, Back returns. Nothing freezes | ☐ |
| 1c | Start | Aliz walks to Bunny, picks him up, carries him to the door, the door opens, a cream curtain, then the game. A tap skips it | ☐ |
| 2 | Listen | **Music plays**: the Little Days theme on the menu AND in the house (a little quieter), the I'm Hungry! track in the mission. Effects and the spoken prompt too. It must not restart when Aliz changes room or when you go from the menu into the house | ☐ |
| 3 | Look at Aliz | Pink hair, striped dress, on screen, not in the floor. Her rough hair and chin are already known. | ☐ |
| 4 | Look at Bunny | A clearly different, smaller character, upright, "I'm hungry, Aliz!" in a cream speech bubble that never covers a face | ☐ |
| 5 | Read the room signs | KITCHEN / BATHROOM readable from arm's length | ☐ |
| 6 | Walk, then run | Tap the floor to walk. Push the joystick past its inner ring: she **runs clearly faster** (about 1.5x). Legs match the pace, no sliding | ☐ |
| 6b | Badges | Near the fridge, a door, the toy box, the wardrobe, the sofa, the bed or Bunny a small round badge appears (OPEN / ENTER / TAKE / HUG / CARRY / SIT / WASH / COOK). Tapping it acts. It never covers the joystick, Home, Next or Bunny's speech bubble | ☐ |
| 6e | Free Play furniture | Wardrobe doors swing open; toy box lid opens and a carried teddy goes in; carry Bunny to the bed and tap PLACE: he lies down; carry him to the sink and tap WASH: the wash close-up opens; the bathroom and living-room doors show a "Soon! Ask a grown-up" sign and nothing kicks you out | ☐ |
| 6f | Tap to walk | Tap the floor anywhere, even the edge in front of the room: Aliz walks to the nearest spot and never freezes; one tap = one walk | ☐ |
| 6c | Carry Bunny | Near Bunny, tap CARRY: she picks him up and holds him in front of her body; walk a few steps; tap PLACE: he stands where you put him. Exactly one Bunny at all times | ☐ |
| 6d | Carry a toy | TAKE the teddy (or a bottle), see it in her hand, PLACE it on its spot | ☐ |
| 7 | Camera | Room framed, nothing important off the edge or under the rounded corners | ☐ |
| 8 | Open the fridge, take the bottle | Door swings, bottle appears in her hands, not floating | ☐ |
| 9 | Prepare the milk | Hold, then shake. Bar fills, liquid changes | ☐ |
| 10 | Carry it back | Bottle stays in her hands through the door | ☐ |
| 11 | Feed Bunny | Bottle at his mouth, he reacts, progress visible | ☐ |
| 12 | Mission complete | Reward shown, Bunny happy and his line is "Thank you, Aliz!" | ☐ |
| 12b | Home | Tap the round Home button (top right): "Take a break?" card with Continue / Home / Grown-ups. Continue resumes exactly; Home returns to the title and "Continue" brings you back to the same room | ☐ |
| 12c | Version | Tiny "v0.1.0" bottom-right on the TITLE screen and splash only, never in the rooms | ☐ |
| 12d | Highchair feeding (Start on a normal profile) | Prompt bar "Give the baby the apple." with the helper line under it. Drag the apple to his mouth: he bites three times with sparkles. Banana: tap to peel first, then drag. Cup: drag up and hold while he drinks. Bring the wrong one: he turns away with a pout, "Try the apple!", the star turns half. Bunny smiles at the end | ☐ |
| 12e | Grown-ups settings | Opens fast; music and voice sliders change the sound at once; Helper language buttons (Off / ไทย / 中文 / العربية / हिन्दी / 日本語) change the second line under the English immediately; Close top-right and Done at the bottom both leave; scrolling works | ☐ |
| 13 | Reward once | Stars go up **once**. Leave and come back: they must not go up again | ☐ |
| 14 | Snack Time | Fridge → banana → counter → spoon → mash → feed | ☐ |
| 15 | HUD | Text never covers Bunny's face; every word readable | ☐ |
| 16 | **Speech** | Tap Speak, say "milk". You should see "I hear: milk" then Great!, and the task completes. Or it honestly says voice is not ready and you can tap instead. The spoken voice is the device's best English voice (download "Zoe (Premium)" or "Samantha (Enhanced)" under Settings → Accessibility → Spoken Content → Voices for a warmer one). | ☐ |
| 17 | **Silent test** | Tap Speak and say nothing. The task must **not** complete by itself. If it does, that is a hard FAIL. | ☐ |
| 18 | Touch fallback | Parent Corner (Grown-ups) → Voice off. Every task still finishable by touch | ☐ |
| 19 | Save, soft | Swipe the app away, relaunch. Stars and progress return | ☐ |
| 20 | Save, cold | Reboot the iPad, relaunch. Same | ☐ |
| 21 | **Learn with Aliz** | Menu top-left book card → the classroom (Aliz at a round table, cards, board, cat and dog). She says hello and asks what to learn; say "animals" (or tap the cat card). No mic prompt anywhere before this screen | ☐ |
| 22 | Hands-free | Aliz asks "What is this?" with the cat on the board. Say "cat" without touching anything: "I hear you!", then Great! and the next question. A cough or "um" must not be judged; a 3 s silence makes her ask again | ☐ |
| 23 | Barge-in | While Aliz is still talking, say "Wait! I want the dog!". She stops mid-sentence within a beat, the board shows the dog and she asks about the dog. If she talks over you, write it down | ☐ |
| 24 | Wrong answer | Say "dog" to the cat. A kind "Try again", a hint, then she says it together with you. No red, no score | ☐ |
| 25 | Echo | With the speaker loud, Aliz's own voice must never count as your answer or interrupt her. If she interrupts herself, that is a hard FAIL | ☐ |
| 26 | Background | Press the Home button mid-lesson, come back. The lesson resumes on the same question and the mic indicator is off until she asks again | ☐ |
| 27 | Mic denied | Settings → Little Days → Microphone off → relaunch → Learn with Aliz. A Tap-to-talk button and answer cards appear; the whole lesson is finishable by tap; nothing says "error" | ☐ |
| 28 | Five minutes | After about five minutes of lessons in one day: "Great job today!" card at the end of a question, never mid-sentence. Continue Playing returns to Free Play; Home returns to the menu. Nothing is locked, nothing is sold | ☐ |
| 29 | Grown-ups → Aliz | Hands-free off makes the classroom tap-to-talk; Delete learning history clears Aliz's progress and today's minutes but not the stars; the privacy text says the online tutor is switched off | ☐ |

Stop and write it down if: it crashes, Aliz gets stuck, anything is unreadable,
the iPad gets hot, a reward is granted twice, progress is lost, or the classroom
mic is ever on outside a lesson (the indicator at the bottom says so).

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
| Passed | ___ / 33 (iPad) · ___ / 35 (iPhone) |
| Speech heard "milk"? | ☐ Yes ☐ Unavailable ☐ Accepted a word I did not say |
| **Ship the Founder Preview to the family?** | ☐ Yes ☐ No ☐ Fix first |
