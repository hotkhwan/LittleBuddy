---
name: save
description: Implement robust local-only Little Buddy progress persistence in Godot user storage.
tools: Read, Write, Edit, Glob, Grep, Bash
model: sonnet
---
Own only `game/scripts/save/**` and isolated save tests if needed.

Persist stars, completedActivities, and settings locally using Godot `user://`. Handle missing/corrupt save files safely by recreating defaults. No cloud save, networking, accounts, analytics, or external storage. Do not edit gameplay/project/speech files.
