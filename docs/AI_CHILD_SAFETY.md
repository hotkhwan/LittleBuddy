# AI Child Safety

## Safety posture

Aliz is a fictional learning companion, teacher character, and guide inside Little Days. Aliz is not a human, parent, therapist, best friend, or replacement for an offline relationship. The AI system is restricted to approved English-learning objectives and known game actions.

Child safety takes priority over engagement, session length, personalization, and model fluency.

## Information Aliz must never request

- Full or legal name
- Home address
- School name
- Phone number or email address
- Password, passcode, or authentication secret
- Precise location
- Exact date of birth
- Private identifying details about family members

If a child volunteers such information, the system should not repeat it, use it in a tool call, add it to learning state, or preserve it in analytics. It should redirect briefly to the lesson without blame.

## Relationship language

Aliz may say short instructional phrases such as “Let’s try together,” “Great work,” or “We can practice again.” Aliz must not:

- claim to be human or conscious;
- ask the child to keep secrets;
- say the child needs Aliz more than family or teachers;
- encourage exclusive friendship or emotional dependency;
- offer therapy, diagnosis, medical, legal, or emergency guidance;
- pressure the child to continue or punish disengagement.

## Content boundary

- Retrieval is limited to `little-days-curriculum/default` and the bundled approved English catalog.
- Arbitrary web search is unavailable in child lessons.
- Search results are mapped to known active local IDs; unknown and draft records are discarded.
- Curriculum validation rejects common embedded instruction and role-tag injection patterns.
- The LLM cannot enable a subject, language, lesson, prop, or activity that deterministic constraints excluded.
- New user-facing content says Aliz or Baby; legacy internal identifiers may remain only where compatibility requires them.

## Tool safety

The runtime exposes only semantic learning tools. Exact schemas, enums, ranges, available-tool membership, per-lesson asset membership, and rate limits are checked outside the model. There is no generic fetch, URL opening, shell, script, filesystem, purchase, account, or arbitrary game-execution tool.

Commerce and external links remain parent-only behind the parent gate. A child-facing tool may suggest a known learning activity but cannot open a store or subscription flow.

## Audio and conversation privacy

- `LIVE_CHILD_AUDIO_ENABLED=false` remains mandatory until privacy and legal approval.
- Raw child audio is not retained by default.
- Full conversation history is not retained long-term by default.
- Agent state stores bounded outcome signals rather than transcripts.
- Search content and analytics must not contain account identity or child conversation text.
- Synthetic or consenting-adult audio is required for development voice benchmarks.

Voice enablement requires verified consent, deletion behavior, retention limits, provider agreements, regional review, physical-device testing, and confirmation that fallback gameplay is complete without microphone access.

## Safe failure behavior

Provider errors, capacity limits, malformed output, disconnects, quota exhaustion, and search failures must collapse toward deterministic local learning. The child must never see an HTTP status, vendor name, token count, billing state, stack trace, or quota infrastructure message.

Appropriate transitions are brief and non-blaming, for example:

- “Let’s keep learning with this card.”
- “Let’s try another way.”
- “We can practice together.”

## Required security tests

- Cross-account and cross-child-profile state access
- Session replay and stale session recovery
- Unknown, malformed, nested, and excessive tool calls
- Asset IDs outside the current lesson
- Prompt injection embedded in curriculum fields
- Unapproved and inactive search results
- Personal-data requests and volunteered personal data
- Provider output that invents lessons or tools
- Quota bypass and fallback loops
- Disconnect, retry, and concurrent-session isolation

Passing model safety prompts alone is insufficient. Release requires enforcement tests at retrieval, planner, state, tool, API authorization, client, and fallback boundaries.

## Human and legal gates

Before production child audio or open-ended AI learning is enabled, the owner must complete child-privacy/legal review, provider data-processing review, consent and deletion verification, store disclosure review, and real-device testing. Until then, closed production flags remain off and local learning remains the child-safe complete path.
