# Little Days Learning Roadmap

## Enabled now

Production V1 focuses on English learning for Pre-K, Kindergarten, and Grades 1–4. The foundation includes 12 reviewed representative lessons, controlled retrieval, deterministic planning, bounded Aliz state, and semantic learning tools.

Local lessons remain deterministic and offline-first. AI can extend an approved lesson but cannot replace curriculum authority or make unavailable subjects appear enabled.

## Near-term English expansion

- Expand each grade with reviewed vocabulary, phonics, listening, speaking, reading, and comprehension sequences.
- Add explicit prerequisite graphs and mastery thresholds.
- Validate Thai-parent/English-child instructions without turning Thai into an additional curriculum language.
- Add parent-facing deterministic learning summaries from progress signals.
- Improve activity and prop coverage using only accepted application assets.
- Evaluate quality, safety, latency, fallback, and cost before increasing online availability.

## Future languages

The contracts reserve:

- Chinese (`zh`)
- Japanese (`ja`)
- Korean (`ko`)

They are disabled. Enabling one requires native-language curriculum review, child-safety evaluation, speech evaluation, locale-specific privacy review, retrieval tests, and a deliberate deployment configuration change. Machine translation alone is not publication approval.

## Future learning domains

The schema reserves mental math, mathematics, science, general knowledge, dance, vocal, music, and creative play. Only English is enabled.

### Mental math

Potential activities include visual arithmetic, number blocks, fruit counting, abacus-style interaction, short speed drills, and adaptive difficulty. Early design should favor understanding and encouragement over time pressure. This sprint does not implement the subject.

### Mathematics and science

Future material should use owned learning objectives, concrete props, deterministic answer rules where possible, and reviewed explanations. It must not copy textbooks or let an LLM invent a standards alignment.

### Dance

Aliz may demonstrate simple movements for a child to follow. Future pose evaluation would require camera collection and a separate privacy, safety, consent, retention, and on-device-versus-cloud review. Camera collection is not enabled.

### Vocal and music

Possible activities include sing-after-Aliz, pitch or rhythm imitation, and call-and-response. Audio evaluation requires additional privacy and child-safety review. It must not be inferred from the current speech permission or voice prototype.

### Creative play and general knowledge

Activities should remain bounded to reviewed prompts and props. Open internet retrieval is not an acceptable child-facing knowledge source.

## Release gates for any new domain or language

1. Owned objectives and representative curriculum are reviewed by an appropriate educator or language specialist.
2. Data collection, retention, deletion, consent, and regional requirements are documented.
3. Deterministic eligibility and fallback rules exist.
4. Search indexes only approved active content and negative tests exclude drafts.
5. Safety and prompt-injection tests pass.
6. Quality and age-fit evaluation passes for every target band.
7. Parent controls and child-friendly failure behavior are verified.
8. Physical-device testing is completed for any new sensor or real-time modality.

Roadmap declarations are compatibility contracts, not promises that features are active.
