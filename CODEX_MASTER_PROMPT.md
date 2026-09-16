# Codex Master Prompt — Little Buddy MVP

Copy the prompt below into Codex CLI from the repository root.

---

You are the implementation orchestrator for Little Buddy.

Read `AGENTS.md` and `LITTLE_BUDDY_TONIGHT.md` completely before changing files.

The user explicitly wants parallel sub-agent delegation. Use sub-agents where their write scopes do not overlap. Do not allow concurrent agents to edit the same files.

Primary objective:

Build a playable offline-first Godot iPad MVP tonight. Scope is exactly one Baby Room with milk feeding, English TTS, a speech service abstraction, `feedMilk` voice intent, star reward, local save, and an iOS export/runbook.

Critical rule:

Native speech recognition must NOT block completion. The game must remain fully playable by touch with a mock/fallback speech service. Implement the architecture so native iOS speech can plug in cleanly.

Execution strategy:

1. Inspect the machine/repo/tooling first.
2. If the repo is empty, bootstrap it.
3. Spawn independent agents for:
   - foundation
   - gameplay
   - content/placeholders
   - speech/iOS bridge
   - local save
4. Keep integration/shared files owned by the primary orchestrator.
5. After independent work returns, integrate sequentially.
6. Run every available validation that does not require user interaction.
7. Spawn a final read-only QA agent to review offline behavior, broken references, and iOS export blockers.
8. Fix P0/P1 findings.
9. Produce `docs/ipad-runbook.md` with exact steps for installing the build to a physical iPad through Xcode.

Do not add:

- backend
- Cloudflare
- Fly.io
- ads
- IAP
- login
- multiplayer
- analytics
- generative AI conversation
- final production artwork

Technical constraints:

- Godot 4.x
- GDScript
- Compatibility renderer preferred
- 2D only
- landscape iPad
- local save in `user://`
- JSON keys camelCase
- no network dependency
- no child audio persistence/upload

Required gameplay:

```text
Baby hungry
→ "I'm hungry."
→ child selects milk
→ "Can you say milk?"
→ child may say "milk"
→ transcript maps to feedMilk
→ baby drinks
→ hunger decreases
→ stars +1
→ "Thank you!"
```

Accepted speech phrases:

```text
milk
give milk
give baby milk
give the baby milk
give the baby some milk
baby wants milk
```

Touch fallback:

If speech is unavailable or denied, tapping/dragging milk must still complete the activity and award the star.

Before finishing, report:

1. files created/changed
2. tests/checks run
3. exact remaining manual steps in Godot/Xcode
4. whether native iOS speech is complete, partial, or mocked
5. blockers that prevent running on physical iPad

Do not claim something works unless it was actually validated.

Start now.

---

## Suggested invocation

Interactive:

```bash
codex
```

Then paste the prompt above.

Or from the repository root:

```bash
codex "Read AGENTS.md, LITTLE_BUDDY_TONIGHT.md, and CODEX_MASTER_PROMPT.md. Execute the master prompt. Use parallel sub-agents with non-overlapping write scopes and integrate the MVP completely."
```

For a clean empty repo:

```bash
mkdir -p little-buddy
cd little-buddy
git init
# copy AGENTS.md, LITTLE_BUDDY_TONIGHT.md, CODEX_MASTER_PROMPT.md here
codex "Read the project instructions and build the Little Buddy MVP. Explicitly use sub-agents for independent scopes."
```

## Before starting Codex

Run these first and keep the output available to Codex:

```bash
system_profiler SPHardwareDataType | egrep 'Model Name|Model Identifier|Chip|Processor Name|Processor Speed|Total Number of Cores|Memory'
sw_vers
df -h /
xcodebuild -version || true
godot --version || /Applications/Godot.app/Contents/MacOS/Godot --version || true
codex --version
```

If Godot is not installed, install the stable Godot 4.x editor and export templates before attempting iOS export.

