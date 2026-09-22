# AI Curriculum Schema

## V1 scope

Only English (`en`) and the `english` subject are enabled. The schema declares future values so interfaces can remain stable, but declaration does not enable content or routing.

Roadmap languages: `zh`, `ja`, `ko`.

Roadmap subjects: `mental_math`, `mathematics`, `science`, `general_knowledge`, `dance`, `vocal`, `music`, `creative_play`.

## Lesson record

All JSON keys use camelCase.

| Field | Type | Rule |
|---|---|---|
| `id` | string | Immutable lowercase identifier |
| `version` | integer | At least 1; increment for reviewed revisions |
| `publishedAt` | ISO timestamp | Required for the approved version |
| `active` | boolean | Only `true` records are eligible |
| `language` | enum | `en` only in V1 |
| `subject` | enum | `english` only in V1 |
| `ageBand` | string | Non-identifying range, not exact DOB |
| `grade` | enum | `prek`, `kindergarten`, `grade1` through `grade4` |
| `skill` | string | Stable curriculum skill identifier |
| `difficulty` | enum | `beginner`, `developing`, `secure`, `stretch` |
| `lessonType` | enum | vocabulary, phonics, listening, speaking, reading, comprehension, or sentence building |
| `learningStandard` | string | Little Days-owned internal alignment code |
| `learningObjective` | string | Observable, age-appropriate outcome |
| `prerequisites` | string[] | Required prior capability |
| `targetVocabulary` | string[] | Approved target words or phrases |
| `teacherPrompts` | string[] | Short Aliz prompts |
| `expectedResponses` | object[] | Prompt ID plus accepted response variants |
| `hints` | string[] | Graduated, encouraging support |
| `successCriteria` | string[] | Observable completion evidence |
| `commonMistakes` | string[] | Teaching misconceptions, not child labels |
| `activityRecommendation` | enum | Known application activity type |
| `learningProps` | string[] | Allowlisted asset IDs |
| `difficultyVariants` | object[] | Difficulty plus deterministic adaptation |
| `durationMinutes` | integer | 1–15 minutes per lesson |
| `content` | string | Original controlled lesson material |

The implementation rejects missing core fields, empty instructional arrays, invalid durations, duplicate IDs, disabled languages/subjects, and common prompt-injection forms. Loaded lessons are deeply frozen.

## Student learning profile

The planner accepts only minimal progress information:

```json
{
  "childProfileId": "opaque-id",
  "ageBand": "6-7",
  "gradeLevel": "grade1",
  "language": "en",
  "skills": [{ "skill": "simple_sentences", "mastery": 0.4, "attempts": 3 }],
  "recentLessons": ["en-grade1-everyday-sentences-v1"],
  "preferredActivityTypes": ["prop_play"],
  "difficultyHistory": ["beginner", "developing"]
}
```

Do not add legal name, exact date of birth, school name, address, precise location, contact information, or raw voice data.

Mastery values are deterministic progress signals, not psychological assessments. They should be bounded to 0–1 at the API boundary and derived from completed learning interactions.

## Parent settings

The planner contract includes:

- `aiLearningEnabled`
- `voiceEnabled`
- `dailyLearningTargetMinutes`
- `difficultyPreference`: `supportive`, `balanced`, or `challenging`

Pricing and product names do not belong in curriculum records or planning logic.

## Versioning and compatibility

- Never mutate the meaning of an active lesson ID in place.
- Use `version` for reviewed revisions and retain the version used by a session snapshot.
- `publishedAt` records editorial publication, not index time.
- `active=false` excludes drafts and retired lessons.
- Client-facing actions refer to stable semantic activity and asset IDs.
- Legacy internal identifiers may remain for compatibility, but new user-facing text uses Aliz or Baby as appropriate.

## Search indexing

The record retains all metadata, while the current AI Search integration can allocate at most five filter fields. The selected filter fields are `active`, `language`, `subject`, `grade`, and `skill`. Lesson type, difficulty, version, and other attributes remain available for post-retrieval validation and deterministic ranking.
