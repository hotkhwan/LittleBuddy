# Little Buddy — Claude Code Master Prompt

Read `CLAUDE.md` and `LITTLE_BUDDY_TONIGHT.md` completely before changing files.

Act as the implementation orchestrator. Build tonight's offline-first Godot iPad MVP end-to-end.

Use project subagents for independent scopes where helpful, with no overlapping writes. Keep shared/integration files under the main session. Native speech recognition must not block completion: implement the speech abstraction and a mock/fallback first, then integrate iOS native speech only if feasible without destabilizing the playable build.

Execution order:
1. Inspect repo and local tooling (`godot`, Xcode, macOS, free disk).
2. Bootstrap the Godot project if missing.
3. Delegate independent work to foundation/gameplay/content/speech/save agents.
4. Integrate returned work sequentially.
5. Run validations available on this Mac.
6. Use QA agent for a final read-only review.
7. Fix P0/P1 findings.
8. Create `docs/ipad-runbook.md` with exact physical-iPad install steps.

Tonight's gameplay must be exactly:
Baby hungry -> "I'm hungry." -> select milk -> "Can you say milk?" -> optional spoken `milk` -> `feedMilk` -> baby drinks -> hunger decreases -> stars +1 -> "Thank you!"

If speech is unavailable/denied, touch milk must still complete the activity.

Do not build backend, Cloudflare, Fly.io, login, ads, IAP, multiplayer, analytics, AI chat, or production artwork.

Before finishing report:
- files created/changed
- checks/tests actually run
- native speech status: complete / partial / mock
- remaining manual Godot/Xcode steps
- blockers for a physical iPad run

Do not claim anything was tested unless it actually was. Start implementation now and continue until the repo is in the best runnable state possible.
