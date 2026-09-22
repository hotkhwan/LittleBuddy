# AI Search Curriculum

## Actual resource

| Field | Value |
|---|---|
| AI Search instance | `little-days-curriculum` |
| Namespace | `default` |
| Storage | Cloudflare built-in storage |
| Indexed corpus | 12 approved English lessons |
| Managed R2 source | Owner-disabled; not the active source |

The active resource uses AI Search built-in storage. The code also has a provider-neutral managed-search interface so a reviewed R2 source can be connected later without changing the planner. No R2 source should be described as active until the owner enables it and an index run is verified.

## Source of truth

The reviewed source corpus is:

```text
cloud/curriculum/english/corpus.json
```

It contains two active lessons for each of Pre-K, Kindergarten, Grade 1, Grade 2, Grade 3, and Grade 4. Topics include colors, numbers, animals, food, family-safe fictional roles, everyday objects, body parts, actions, sentences, phonics, listening, speaking, reading, and comprehension.

AI Search is retrieval infrastructure, not curriculum authority. Results are mapped back to locally approved lesson IDs. Unknown IDs, drafts, inactive entries, disabled languages, and disabled subjects are dropped even if the managed index returns them.

## Retrieval flow

```text
profile + deterministic constraints
  -> query little-days-curriculum/default
  -> metadata filter
  -> map result IDs to approved local catalog
  -> discard unknown or inactive results
  -> deterministic planner ranking
  -> selected lesson/activity
```

If managed search throws, times out, or returns no usable result, `ApprovedCurriculumRetriever` searches the same approved bundled corpus. Arbitrary internet search is not part of child learning.

## Metadata and filter allocation

Every lesson stores the full curriculum metadata described in `AI_CURRICULUM_SCHEMA.md`. The current managed index supports a maximum of five filter fields, so the production filter allocation is:

1. `active`
2. `language`
3. `subject`
4. `grade`
5. `skill`

Other metadata remains stored and is applied after retrieval by trusted application code when needed. Changing this allocation requires a retrieval regression run and reindex; it must not silently broaden lesson eligibility.

The current adapter always sends `active=true`, `language=en`, and `subject=english`, plus grade when present. Skill-level constraints are applied by the local approved-catalog boundary and planner; the deployment adapter should add the fifth indexed filter where supported by the query.

## Example

For:

> English lesson for a child who knows red and blue but struggles with green

the caller supplies the authoritative grade from the profile. The approved fallback retrieval matches the green vocabulary and returns the Pre-K colors lesson only when its grade filter is `prek`. Free-form text cannot override profile metadata.

## Publishing procedure

1. Author original Little Days content with a new immutable lesson ID or higher version.
2. Keep `active=false` during editorial, pedagogy, safety, and asset review.
3. Run schema and prompt-injection validation.
4. Confirm every learning prop is an accepted application asset.
5. Set `publishedAt`, approve the exact version, and set `active=true`.
6. Upload/index the approved record in `little-days-curriculum/default`.
7. Verify ID count, metadata filters, known queries, negative queries, and draft exclusion.
8. Deploy only after the local approved catalog contains the same active ID/version.

An unfinished draft must never become active as a side effect of upload or indexing.

## Privacy and observability

Search analytics should retain normalized lesson intent and non-sensitive metadata rather than raw child conversation. Do not index profile data, names, exact birth dates, schools, locations, audio, transcripts, or account identifiers. Personalized child conversation must not be cached.
