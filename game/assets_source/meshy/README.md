# `assets_source/` — high-resolution masters, never loaded by a shipping scene

Owner policy, 2026-09-18:

    source/   original Meshy GLB        never loaded by shipping scenes
    runtime/  optimized, retopologised  mobile-safe, what the game actually uses

Runtime assets live in `game/assets/characters/` and `game/assets/props/`.

Raw Meshy exports are **gitignored** — four of them are 63.6 MB plus ~20 MB of
extracted textures, against a 33 MB repository with no git-lfs, for assets that
cannot ship without retopology. Adding them to git later is one command;
removing them later means rewriting published history, which this project
forbids. Provenance and restore steps: `docs/MESHY_CHARACTER_AUDIT.md`.
