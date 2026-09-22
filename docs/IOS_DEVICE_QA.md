# iOS Device Audio QA

Status: **physical device required; not passed by automation**.

Use a clean install on the affected iPad first. Keep music playing, enter Learn
with Aliz, grant microphone permission, complete at least 50 adult-operated
Tutor turns, exit, and re-enter. Repeat with permission already granted and
permission denied. Then run music alone; music + SFX; music + TTS; music +
recognition; recognition + TTS; barge-in; rapid room navigation; 20 Classroom
entry/exit cycles; 40 background/foreground cycles; lock/unlock; and available
wired/Bluetooth route changes.

For every run record duration, turn/cycle counts, audio glitches, silence,
route/sample-rate transitions, and the local diagnostic snapshot. If a crash
occurs, export the complete device crash report (exception, termination reason,
crashed thread, audio threads, binary UUID) and correlate its timestamp with
the local telemetry. Never retain or upload raw child audio; use an adult
operator and synthetic lesson content.

Pass requires a signed physical-device build, the microphone permission path,
Tutor speech/TTS/music/SFX, background/foreground and lock/unlock, exit/re-entry,
and review of telemetry. Simulator or headless success is not a substitute.
