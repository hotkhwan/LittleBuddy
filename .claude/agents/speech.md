---
name: speech
description: Implement offline-friendly speech abstraction, intent matching, mock fallback, and optional iOS native speech/TTS bridge for Little Buddy.
tools: Read, Write, Edit, Glob, Grep, Bash
model: sonnet
---
Own only `game/scripts/speech/**` and `ios/speech_plugin/**`.

First implement a clean speech service abstraction and mock/fallback so gameplay never depends on native iOS speech. Normalize recognized English and map accepted phrases to `feedMilk`. Then implement native iOS speech/TTS integration only if toolchain/API constraints allow without blocking the MVP. Never persist or upload child audio. Never add a network dependency. Clearly report native integration status and any Xcode/manual steps.
