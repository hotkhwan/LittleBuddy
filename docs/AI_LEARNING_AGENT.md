# Aliz Learning Agent

## Purpose

The Aliz Learning Agent is a bounded English-learning coordinator, not a general chatbot or an autonomous game controller. It combines approved curriculum retrieval with deterministic planning and a small semantic tool surface. Local lessons remain the final fallback and do not require a network.

The implemented module is exported from `cloud/src/learning/index.ts`.

## Implemented state

`AlizLearningAgentState` contains only:

- `sessionId`
- `childProfileId`
- `lessonId`
- `currentObjective`
- `turn`
- bounded `masterySignals`
- bounded `recentResponses`
- `availableTools`

Construction or recovery validates that the lesson is active and approved, the objective exactly matches that lesson, and every available tool is on the fixed allowlist. Recent responses are capped at 8 and mastery signals at 20. Long-form conversation history and raw audio are not part of agent state.

The storage-key helper namespaces state by parent, child profile, and session:

```text
learning:{parentId}:{childProfileId}:{sessionId}
```

This prevents accidental state-key collisions. API authorization must still verify account and child ownership before loading the state.

## Planning boundary

`LearningPlanner` takes a minimal learning profile, parent settings, available activities, and a session-duration budget. It then:

1. Stops online planning when AI Learning is disabled or the requested language is not enabled.
2. Finds the weakest recorded skill deterministically.
3. Retrieves only active English curriculum for the child's grade and target skill.
4. Removes lessons whose activity is unavailable or whose duration exceeds the budget.
5. Scores mastery need, preferred activity, and recent use.
6. Selects at most one follow-up that fits in the remaining time.

An LLM may rank an already constrained candidate set in a later integration, but it must not invent lesson IDs or expand the eligible curriculum.

## Semantic tools

Only these tool names are accepted:

- `show_learning_card(assetId)`
- `show_prop(assetId)`
- `set_emotion(emotion, intensity)`
- `play_gesture(gesture, intensity)`
- `look_at(target)`
- `award_star(reason)`
- `start_minigame(activityId)`
- `suggest_activity(activityId)`
- `repeat_prompt()`
- `give_hint(hintLevel)`
- `complete_lesson(result)`

Every call requires an exact argument shape. Unknown fields, arbitrary URLs, unrecognized enum values, out-of-range intensity or hint levels, and non-allowlisted tool names are rejected. Learning-card and prop IDs must also belong to the current approved lesson. Accepted calls are limited to 8 per rolling minute by default.

Tools express intent only. The game remains responsible for mapping a validated semantic event to a known scene action. No shell, HTTP, filesystem, arbitrary script, or generic game-execution tool is exposed.

## Recovery and fallback

The intended service sequence is:

```text
Premium voice
  -> Standard AI voice
  -> Standard text tutor
  -> deterministic local lesson
```

Managed curriculum retrieval falls back to the bundled approved catalog if the search service fails. The planner returns an offline-continuation result when no eligible online lesson exists. Child-facing responses must use a short transition such as “Let’s keep learning together,” never an infrastructure error or quota message.

## Integration requirements

- Authenticate the parent session and authorize the child profile before state access.
- Persist snapshots in a session-scoped Durable Object or equivalent isolated store.
- Inject the managed-search adapter; do not grant the model direct search credentials.
- Validate every provider tool call with `validateToolCall` and the current agent instance.
- Record aggregate latency, provider, usage, rejection reason, and fallback level without raw child audio or unnecessary transcript text.
- Keep `LIVE_CHILD_AUDIO_ENABLED=false` until the privacy and legal gates are complete.

## Verification

Focused tests cover approved state recovery, bounded history, account/profile/session key separation, unknown tools, extra arguments, enum and range validation, lesson-owned assets, rate limiting, deterministic selection, duration limits, disabled AI, disabled languages, managed-search failure, and rejection of unapproved search results.
