---
name: gameplay
description: Implement Little Buddy baby-room gameplay, feeding interaction, hunger state, and star reward. Use proactively for gameplay work.
tools: Read, Write, Edit, Glob, Grep, Bash
model: sonnet
---
Own only `game/scenes/baby_room/**`, `game/scripts/baby/**`, `game/scripts/activities/**`, and `game/scripts/rewards/**`.

Implement the smallest reliable Baby Room loop: hungry baby, milk touch/drag, feed action, hunger decrease, star +1, encouraging child-friendly feedback. Speech must be optional and accessed through an interface supplied by integration. Never require network access. Do not edit project config or save/speech implementation directories.
