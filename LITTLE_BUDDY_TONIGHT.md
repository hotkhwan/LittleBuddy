# Little Buddy — Offline iPad MVP Plan

> Goal: get the first playable version onto a physical iPad as fast as possible, with the core game playable offline.

## 1. Does the Mac mini need to be powerful?

Not for this MVP.

This is a small 2D Godot project. The main bottleneck is more likely to be **Xcode disk/RAM pressure** than Godot itself.

Godot's current documentation lists roughly:

- 4 GB RAM minimum for the native editor
- 8 GB RAM recommended for a smoother simple project
- Apple Silicon M1 as an example baseline on modern macOS
- export templates add storage usage

For this project:

- use **2D only**
- use the **Compatibility renderer**
- use a **physical iPad** instead of keeping an iOS Simulator running
- close Chrome tabs / Docker / local Kubernetes / heavy IDEs while Xcode archives
- keep at least ~25–40 GB free if possible because Xcode + SDKs + DerivedData can become large

### Check your Mac now

Run:

```bash
system_profiler SPHardwareDataType
sw_vers
df -h /
xcodebuild -version || true
```

Useful summary:

```bash
system_profiler SPHardwareDataType | egrep 'Model Name|Model Identifier|Chip|Processor Name|Processor Speed|Total Number of Cores|Memory'
```

If the machine has 8 GB RAM, it is still reasonable for this small 2D project. Avoid running Docker/Kubernetes at the same time.

## 2. Important 2026 Xcode constraint

Apple currently requires App Store Connect uploads to be built using Xcode 26 or later with the appropriate modern SDK.

However, **tonight we do not need TestFlight**.

For the first build, connect the iPad by cable/Wi-Fi and install directly from Xcode.

Even without paid Apple Developer Program membership, a normal Apple Account can use Xcode Personal Team to install/test on personal devices. Personal Team provisioning is temporary and must be renewed periodically.

That is the fastest route to "ลูกได้เล่นคืนนี้".

## 3. Tonight's scope — do not expand it

Build exactly this:

```text
Little Buddy v0.0.1

Baby Room
│
├── Baby character placeholder
├── Milk bottle
├── Hunger state
├── Tap/drag Milk
├── English TTS
├── Microphone button
├── speech intent: feedMilk
├── ⭐ reward
└── local save
```

No backend.
No Cloudflare.
No Fly.io.
No ads.
No IAP.
No login.
No multiplayer.

## 4. Core gameplay loop

```text
Launch
  ↓
Baby Room
  ↓
Baby becomes hungry
  ↓
"I'm hungry."
  ↓
child selects milk
  ↓
"Can you say milk?"
  ↓
🎤
  ↓
child says "Milk"
  ↓
feedMilk intent
  ↓
Baby drinking animation
  ↓
Hunger -50
⭐ +1
  ↓
"Thank you!"
```

### Mandatory fallback

Voice recognition must **never block the game**.

If Speech Recognition is unavailable or permission is denied:

```text
Touch Milk
→ Baby drinks
→ ⭐ +1
```

The child can still play the game completely offline.

## 5. Offline architecture

```text
Physical iPad
│
├── Godot 4.x
│   ├── Baby Room
│   ├── Baby State
│   ├── Activity Engine
│   ├── Intent Matcher
│   ├── Reward Manager
│   └── Local Save
│
├── iOS local services
│   ├── Text-to-Speech
│   ├── Microphone
│   └── Speech Recognition
│
└── Bundled Content
    └── feeding.json
```

No component in the critical path requires the internet.

## 6. Recommended repository

```text
little-buddy/
├── AGENTS.md
├── LITTLE_BUDDY_TONIGHT.md
├── CODEX_MASTER_PROMPT.md
├── game/
│   ├── project.godot
│   ├── scenes/
│   │   ├── main/
│   │   └── baby_room/
│   ├── scripts/
│   │   ├── baby/
│   │   ├── activities/
│   │   ├── speech/
│   │   ├── rewards/
│   │   └── save/
│   ├── content/
│   │   └── feeding/
│   ├── assets/
│   │   └── placeholders/
│   └── tests/
└── ios/
    └── speech_plugin/
```

## 7. Minimum data model

### Baby state

```gdscript
var hunger: float = 80.0
var happiness: float = 50.0
var energy: float = 70.0
var cleanliness: float = 70.0
```

MVP only needs hunger to affect the screen.

### Feeding content

Create `game/content/feeding/feed_milk.json`:

```json
{
  "activityId": "feedMilk",
  "category": "feeding",
  "prompt": "I'm hungry.",
  "instruction": "Give the baby some milk.",
  "repeatPrompt": "Can you say milk?",
  "targetWords": [
    "milk"
  ],
  "acceptedCommands": [
    "milk",
    "give milk",
    "give baby milk",
    "give the baby milk",
    "give the baby some milk",
    "baby wants milk"
  ],
  "reward": {
    "stars": 1
  }
}
```

## 8. Speech abstraction

Do this before writing iOS-native details.

```text
SpeechService
│
├── isAvailable()
├── requestPermission()
├── startListening()
├── stopListening()
└── recognized(text)
```

Implement:

```text
MockSpeechService
```

first.

The game scene must depend on `SpeechService`, not directly on native iOS code.

Then implement:

```text
IosSpeechService
```

when the native bridge is ready.

## 9. Intent matcher

Normalize:

```text
"Give the baby some MILK!"
```

to something equivalent to:

```text
give the baby some milk
```

Then map accepted variants to:

```text
feedMilk
```

Do not require perfect sentence recognition.

For MVP, if the normalized transcript contains the target keyword `milk`, allowing it to pass is acceptable.

## 10. TTS

Prefer local system TTS.

MVP prompts:

```text
I'm hungry.
Can you say milk?
Great!
Thank you!
Try again!
```

If native TTS integration becomes a blocker, use Godot's available platform TTS interface where supported and keep the implementation behind `TtsService`.

## 11. UI layout

Target: landscape iPad.

Suggested layout:

```text
┌─────────────────────────────────────────┐
│ ⭐ 0                                    │
│                                         │
│             👶 Baby                     │
│                                         │
│        "I'm hungry."                    │
│                                         │
│                                         │
│     🍼 Milk                🎤 Speak      │
│                                         │
└─────────────────────────────────────────┘
```

Use large touch targets.
Minimum button dimension should feel comfortable for a child.

Do not spend tonight on final artwork.

## 12. Save format

Use Godot `user://`.

```json
{
  "profileVersion": 1,
  "stars": 0,
  "completedActivities": [],
  "settings": {
    "speechLocale": "en-US",
    "speechEnabled": true,
    "thaiHints": true
  }
}
```

No cloud sync.

## 13. iOS permissions

The exported Xcode project will need usage descriptions for microphone and speech recognition.

Expected Info.plist concepts:

```text
NSMicrophoneUsageDescription
NSSpeechRecognitionUsageDescription
```

Use child-friendly/parent-readable wording.

Example intent:

```text
Microphone is used only when the child taps the speak button to practice English words.
```

Do not record or upload audio.

## 14. Tonight agent split

### Agent A — Foundation

Owns:

```text
game/project.godot
game/scenes/main/**
```

Deliverables:

- bootable Godot project
- landscape-oriented project settings
- simple main scene
- Compatibility renderer
- navigation into Baby Room

### Agent B — Gameplay

Owns:

```text
game/scenes/baby_room/**
game/scripts/baby/**
game/scripts/activities/**
game/scripts/rewards/**
```

Deliverables:

- Baby Room
- hunger state
- milk interaction
- feed activity
- simple animation/state feedback
- star reward

### Agent C — Content

Owns:

```text
game/content/**
game/assets/placeholders/**
```

Deliverables:

- feed milk JSON
- placeholder visuals
- English prompt text
- accepted speech phrases

### Agent D — Speech/iOS

Owns:

```text
game/scripts/speech/**
ios/speech_plugin/**
```

Deliverables in priority order:

1. `SpeechService` abstraction
2. mock implementation
3. intent matcher
4. microphone permission interface
5. iOS native speech bridge if practical
6. document any remaining manual Xcode step

Do not make gameplay dependent on item 5.

### Agent E — Local Save

Owns:

```text
game/scripts/save/**
```

Deliverables:

- local JSON save
- safe defaults
- star persistence
- corrupt-save recovery

### Agent F — QA / iPad Export

Read-only initially.

Deliverables:

- verify references/paths
- identify Godot parse errors
- verify offline assumptions
- prepare `docs/ipad-runbook.md`
- exact Xcode steps for physical iPad
- list blockers instead of hiding them

## 15. Integration order

The orchestrator should integrate in this order:

```text
Foundation
   ↓
Gameplay + Content + Save
   ↓
Mock Speech
   ↓
Run locally in Godot
   ↓
Native iOS Speech
   ↓
Export Xcode
   ↓
Physical iPad
```

Do NOT wait for native speech before proving the core gameplay.

## 16. Physical iPad path

Tonight's preferred route:

```text
Godot
  ↓
Export iOS project
  ↓
Open generated Xcode project
  ↓
Signing & Capabilities
  ↓
Select your Apple Account / Personal Team
  ↓
Set unique Bundle Identifier
  ↓
Connect iPad
  ↓
Trust developer if prompted
  ↓
Run ▶
```

If Developer Mode is required on the iPad, enable it in iPadOS settings and reconnect.

## 17. Test checklist

### Offline

- [ ] Enable Airplane Mode
- [ ] Launch app
- [ ] Baby Room appears
- [ ] Milk interaction works
- [ ] Stars work
- [ ] Save/relaunch preserves stars
- [ ] Game does not hang waiting for network

### Child UX

- [ ] Buttons are large
- [ ] No scary/error UI
- [ ] No debug text on child-facing screen
- [ ] Sound isn't excessively loud
- [ ] Repeated tapping cannot crash the scene

### Speech

- [ ] Permission denied does not break gameplay
- [ ] Permission granted enables microphone button
- [ ] `milk` maps to `feedMilk`
- [ ] wrong speech offers `Try again!`
- [ ] microphone stops after recognition/timeout/cancel

## 18. After tonight — NOT part of MVP

Next milestones:

```text
v0.0.2
├── Bath
├── Dress
├── Play
└── Sleep

v0.0.3
├── stickers
├── more words
└── daily routine

v0.1
├── TestFlight
└── parent settings

later
├── downloadable content packs
├── optional Cloudflare R2
├── IAP
└── Android
```

Fly.io is not needed until there is a true server workload such as realtime multiplayer or authoritative game logic.

## 19. Official references checked

- Godot system requirements: https://docs.godotengine.org/en/latest/about/system_requirements.html
- Apple Xcode system requirements: https://developer.apple.com/xcode/system-requirements/
- Apple developer account / Personal Team: https://developer.apple.com/help/account/basics/about-your-developer-account
- Apple programs overview: https://developer.apple.com/help/account/membership/programs-overview
- App Store SDK requirements: https://developer.apple.com/news/upcoming-requirements/
- Codex repository: https://github.com/openai/codex

