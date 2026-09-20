# Aliz Tutor Mode — privacy, child-safety and compliance review (gate document)

Owner: Agent G. Date: 2026-09-20. Status: **GATE CLOSED — the cloud tutor may
not be enabled in any build.** The local scripted tutor may ship (§E).

This is a gate, not a checklist of hopes. Every "TRUE" below is backed by a
file, a test, or a fetched source quoted with its URL and the date it was
read. Every "FALSE" is a thing that does not exist yet. Where a source could
not be fetched, that is stated, and nothing is quoted from memory as if
verified.

Reviewed code: this worktree at `4fa1f47` plus (read-only) the sibling
worktrees `backend` (`1ec9cbc`, source; `19210b3` docs), `classroom`,
`lesson`, `quota`, `face`, `meshy`, `voice` as they stood on 2026-09-20.
Related: `docs/ALIZ_TUTOR_SECURITY_FINDINGS.md` (backend, by file:line),
`docs/ALIZ_TUTOR_PARENT_INFO.md` (in-app text),
`game/tests/cases/test_tutor_privacy_guards.gd` (enforcement).

---

## A. Data inventory

### A1. What exists on the device today (all builds)

| Store | Path | Keys | Contains child words or audio? | Leaves device? |
| --- | --- | --- | --- | --- |
| Profile | `user://profile.json` (`game/scripts/save/profile_store.gd:125-150`) | `profileVersion`, `stars`, `completedActivities`, `currentChapter`, `currentLevel`, room/spawn ids, `starsByLevel`, `levelCompleted`, `unlockedChapters`, `unlockedLevels`, `unlockedRooms`, `settings{speechLocale, speechEnabled, thaiHints, soundEnabled, ttsSpeed}` | No | No |
| Tutor progress (lesson worktree, not yet merged) | `settings.tutorProgress[lessonId]` in the same file (`lesson_engine.gd:51-52`) | `{stepIndex, stepCount, correctFirstTry, completed, rewardGranted}` | No — counts only, never the transcript | No |
| Tutor local quota (classroom worktree, not yet merged) | `settings.tutorLocalQuota` (`tutor_local_quota.gd:23,139`) — note the contract names it `tutorQuota`; Agent F/B should reconcile | `{utcDate, usedSeconds}` | No | No |
| Speech diagnostics | `user://speech_diag.json` (`speech_service.gd:42`) | exactly the allowlist in `test_speech_privacy_guard.gd`: `platform, modelName, backend, nativeSingletonPresent, isAvailable, hasPermission, speechEnabledSetting, ttsAvailable, listenCount, recognizedCount, failedCount, lastFailureReason, launchCount, writtenAt` | No — the test fails if a transcript key is added | No |
| Music-rights marker | `user://OWNER_ACKNOWLEDGED_UNVERIFIED_MUSIC` | presence only | No | No |

Microphone: opened only by the frozen native iOS plugin through
`SpeechService` → `IosSpeechBackend` (`ios_speech_backend.gd:16-17`), with
`requiresOnDeviceRecognition = YES` asserted by `test_speech_privacy_guard.gd`.
Godot's own `AudioStreamMicrophone` / `AudioEffectRecord` /
`audio/driver/enable_input` appear nowhere (asserted by
`test_tutor_privacy_guards.gd`). Android: `permissions/record_audio=false`
and no `INTERNET` permission in `export_presets.cfg`; Android has no speech
backend at all and reports "unavailable".

Network: no `HTTPRequest`, `HTTPClient` or socket class exists under `game/`
today (asserted). The only URL literals are the loopback development default
in `tutor_flags.gd:23` and the Parent Corner text link.

### A2. What the cloud path WOULD send (verified against contracts + backend source)

Per `docs/ALIZ_TUTOR_CONTRACTS.md` and `backend/src/app.js` at `1ec9cbc`:

| Direction | Field | Source | Personal information? |
| --- | --- | --- | --- |
| device → backend, `POST /sessions` | `lessonId`, `clientId` (device-invented string, regex-limited), `parentApprovalToken` (HMAC token bound to clientId) | `app.js:173-176` | `clientId` is a **persistent identifier** (COPPA 312.2) |
| device → backend, `POST /sessions/{id}/turns` | `transcript` (≤ 500 chars, text produced by on-device recognition), `lessonContext{stepId, outcome, expectedAnswers, hint, nextQuestionText, visualAssetId, matched, lessonAction}`, `audioSeconds` (a number), header `Idempotency-Key` | `app.js:219-221` | transcript may contain anything the child said, including a name |
| backend → OpenAI (only when `TUTOR_PROVIDER=openai` and a key is set) | system prompt + one user message: `lessonId, stepId, outcome, expectedAnswers, hint, nextQuestionText, visualAssetId, childSaid:<transcript, first 200 chars>`; `store:false`; no `user`/`safety_identifier` | `openai_provider.js:58-71, 105-115` | transcript only; **no clientId, sessionId, name, age, device, location** (verified) |
| **raw audio** | **never** — there is no audio field, no audio endpoint, no multipart handling in the backend (`grep -n audio app.js` finds only the numeric `audioSeconds`); the client speech layer is structurally unable to network (`test_speech_privacy_guard.gd`) | | **NOT sent in V1 — verified** |

### A3. What the backend stores and for how long (as written today)

| Collection (`backend/src/store.js`) | Contents | Retention as coded |
| --- | --- | --- |
| `sessions` | `sessionId, clientId, lessonId, entitlement, approvedVia, startedAt, lastEventAt, turnCount, endedAt, endReason` | **forever** (no purge) |
| `usage` | per clientId `{dayKey, usedSeconds}` | overwritten daily, never deleted |
| `turns` | per session/turn usage numbers: `sttSeconds, llm tokens, ttsChars, latencyMs, cached, provider, costUsd` — **no transcript** | forever |
| `idempotency` | `sessionId:key → {hash(sha256 of full request body incl. transcript), status, body(turn), at}` | forever |
| `entitlements`, `receipts`, `spend` | entitlement records, mock receipts, monthly USD | forever |
| provider side | OpenAI abuse-monitoring logs: prompts/responses **up to 30 days by default** (§B3) unless ZDR is approved | 30 days default |
| access log (`server.js:35`) | method, **full URL** (includes `clientId` query and session ids), status, ms | wherever stdout goes |

Assessment: transcripts are not persisted server-side (good), but there is no
retention policy at all, and the idempotency hash and access log are two
places where child-linked data lingers. See findings M1, M3, M4.

---

## B. Provider terms — as fetched on 2026-09-20

Fetch log (what actually loaded):

| URL | Result |
| --- | --- |
| https://openai.com/policies/usage-policies/ | HTTP **403** to WebFetch and to curl; page text was obtained through a read-only fetch proxy (r.jina.ai) the same day and is quoted below with that caveat |
| https://openai.com/policies/row-terms-of-use/ | 403 direct; obtained via the same proxy |
| https://developers.openai.com/api/docs/guides/your-data (platform.openai.com/docs/guides/your-data 301-redirects here) | 200 |
| https://developers.openai.com/api/docs/guides/safety-best-practices | 200 |
| https://developers.openai.com/api/docs/guides/safety-checks/under-18-api-guidance | 200 |
| https://help.openai.com/en/articles/8660679-how-can-i-get-zero-data-retention-zdr | 403 direct; via proxy the article now titles itself "How can I get a Business Associate Agreement (BAA)..." — the ZDR content lives on the developers page above |

### B1. Usage policies (openai.com/policies/usage-policies, changelog "2025-10-29: ... universal set of policies"; read via proxy)

> "**Keep minors safe**. Children and teens deserve special protection. Our services are designed to prevent harm and support their well-being, and must never be used to exploit, endanger, or sexualize anyone under 18 years old." Prohibited uses include "exposing minors to age-inappropriate content, such as graphic self-harm, sexual, or violent content".

> Under "Empower people": no "automation of high-stakes decisions in sensitive areas without human review", listing "education" among those areas.

Reading for this product: an English-word tutor that praises and repeats is
not a high-stakes decision; the output validator (age filter, banned words,
no URLs) plus the deterministic fallback turn is the "age-appropriate content
filter" the guidance below requires.

### B2. Terms of use (openai.com/policies/row-terms-of-use, read via proxy)

> "Minimum age. You must be at least 13 years old or the minimum age required in your country to consent to use the Services. If you are under 18 you must have your parent or legal guardian's permission to use the Services."

This is the *consumer* terms clause. In the API model the developer (Little
Days) is OpenAI's customer and the child is the developer's end user; the
clause that governs us is the Under-18 guidance (B4).

### B3. API data retention default and ZDR (developers.openai.com/api/docs/guides/your-data, HTTP 200)

> "By default, abuse monitoring logs are generated for all API feature usage and retained for up to 30 days, unless longer retention is required by law, or is reasonably necessary to protect our services or any third party from harm."

> "Abuse monitoring logs may contain certain customer content, such as prompts and responses, as well as metadata derived from that customer content, such as classifier outputs."

> "Eligible customers may have their customer content excluded from these abuse monitoring logs, subject to the limitations below, by getting approved for the Zero Data Retention or Modified Abuse Monitoring controls. Currently, these controls are subject to prior approval by OpenAI and acceptance of additional requirements."

> "Customers who enable Modified Abuse Monitoring or Zero Data Retention are responsible for ensuring their users abide by OpenAI's policies for safe and responsible use of AI and complying with any moderation and reporting requirements under applicable law."

> "Get in touch with our sales team to learn more about these offerings and inquire about eligibility."

> "Zero Data Retention changes some endpoint behavior: the `store` parameter for `/v1/responses` and `v1/chat/completions` will always be treated as `false`, even if the request attempts to set the value to `true`."

> "As of March 1, 2023, data sent to the OpenAI API is not used to train or improve OpenAI models (unless you explicitly opt in to share data with us)."

Table on that page: `/v1/chat/completions` — training: No; abuse-monitoring
retention: 30 days; ZDR eligible: Yes. So `store:false` (which the adapter
already sends) removes dashboard/application-state storage but **does not**
remove the 30-day abuse-monitoring copy; only an approved ZDR (or Modified
Abuse Monitoring) arrangement does.

### B4. Under-18 API guidance (developers.openai.com/api/docs/guides/safety-checks/under-18-api-guidance, HTTP 200)

> "Young people have unique needs online and offline, so developers should implement additional safeguards when using our API to serve minors (under 18 years old)."

> "Organizations serving minors must comply with all applicable child protection, safety, and privacy laws, including the Children's Online Privacy Protection Act (COPPA)."

> "**You should not use OpenAI services to process any personal data of children under 13 or the applicable age of digital consent without first implementing zero data retention in our API.**"

> "Providing age-appropriate disclosures to minors about AI tools and how to use them responsibly." / "Implementing age-appropriate content filters to address potentially sensitive content." / "Implementing reasonable monitoring and reporting mechanisms, including escalation paths for high-risk interactions." / "Where required or otherwise appropriate for your use case, using age assurance systems to ensure only intended users can access the product."

> "OpenAI reserves the right to audit organizations for compliance with this policy." ... "may be subject to suspension or termination of API access."

Safety best practices page (HTTP 200): "If your application serves minors,
also follow the Under-18 guidance." It also recommends a per-user
`safety_identifier` ("a string that uniquely identifies each user"); the
backend deliberately does not send one, because a per-child persistent
identifier handed to a third party is COPPA personal information (finding L8).

**Provider position, in one line:** OpenAI's published position is that
under-13 personal data may be processed only with ZDR in place, plus content
filters, disclosures, monitoring/escalation and COPPA compliance. There is no
per-customer written position for Little Days; nobody has contacted sales, no
OpenAI organisation exists for this project, and no key is present on this
machine (`OPENAI_API_KEY` unset; verified by the backend README and by the
history scan in §G).

---

## C. Law and platform policy — primary sources fetched 2026-09-20

### C1. COPPA (United States) — 16 CFR Part 312 (law.cornell.edu mirror, HTTP 200; ecfr.gov redirected to an unblock page and was not used)

Definitions (§312.2):
- "Child" — "an individual under the age of 13".
- "Personal information" includes "A first and last name", "Online contact
  information", "A persistent identifier that can be used to recognize a user
  over time and across different websites or online services", "A photograph,
  video, or audio file where such file contains a child's image or voice", and
  a biometric identifier "such as ... voiceprints".
- "Collects or collection" — "the gathering of any personal information from a
  child by any means, including ... Requesting, prompting, or encouraging a
  child to submit personal information online".
- "Web site or online service directed to children" — a service "targeted to
  children", plus the *actual knowledge* prong for services that know they
  collect from children or from users of a child-directed service.
- "Support for the internal operations" — activities "necessary to maintain
  or analyze the functioning" etc., provided the information is not "used or
  disclosed to contact a specific individual ... or for any other purpose".

Consent (§312.5):
- (a) "An operator is required to obtain verifiable parental consent before any
  collection, use, or disclosure of personal information from children", with
  **separate** consent for disclosure to third parties.
- (b)(2) enumerated methods: signed consent form (mail/fax/scan); credit/debit
  card or online payment transaction with notification; toll-free number
  staffed by trained personnel; video-conference with trained personnel;
  government ID checked against a database and promptly deleted;
  knowledge-based authentication questions a child could not answer; photo ID
  matched to a live image with prompt deletion; and, for operators that do
  **not** disclose to third parties, "email plus" or "text plus" a confirming
  step.
- (c) exceptions include a one-time response to a child's specific request
  without re-contact, persistent identifiers used solely for support for
  internal operations, and (c)(9) audio files of a child's voice used solely to
  respond to a specific request and not retained.

Enforcement guidance — FTC "Complying with COPPA: FAQs" (ftc.gov, HTTP 200):
- B.7: "Foreign-based websites and online services must comply with COPPA if
  they are directed to children in the United States, or if they knowingly
  collect personal information from children in the U.S."
- F.6 (voice): "when an operator collects an audio file containing a child's
  voice solely as a replacement for written words, such as to perform a search
  or fulfill a verbal instruction or request, and only maintains the file for
  the brief time necessary for that purpose, the FTC will not take an
  enforcement action".
- H.1 (actual knowledge): operators "will be held to have acquired actual
  knowledge ... where, for example, they later learn of a child's age or grade
  from a concerned parent".
- H.3: "simply including a check box stating, 'I am over 12 years old' would
  not be considered a neutral age-screening mechanism".
- I.4: a consent method must be "reasonably calculated, in light of available
  technology, to ensure that the person providing consent is the child's
  parent".

2025 amendments — FTC press release 2025-01-16 (ftc.gov, HTTP 200): operators
"will be required to obtain separate verifiable parental consent to disclose
children's personal information to third-party companies"; "The rule requires
covered operators to only retain personal information for as long as
reasonably necessary to fulfill a specific purpose for which it was
collected"; personal information now expressly includes biometric and
government identifiers; effective 60 days after Federal Register publication
with one year to comply. (The Federal Register publication date itself was not
fetched; treat the compliance deadline as already in force by 2026-09-20.)

**Application to Little Days.** The app is *directed to children* by design
(the prompt in `openai_provider.js:18` literally says "children aged 3 to 6").
The actual-knowledge standard is therefore moot: COPPA applies in full to any
US child, and B.7 says it applies to a Thai operator serving US children. Under
the cloud path: `clientId` is a persistent identifier; keeping quota by it is
arguably "support for the internal operations", but sending the transcript to
OpenAI is a **disclosure to a third party** of information collected from a
child, for which (a) the 2025 rule requires *separate* verifiable consent and
(b) the "email plus" shortcut is unavailable, because it is reserved for
operators that do not disclose. A 3-second press-and-hold is not on the
§312.5(b)(2) list and does not meet I.4. The on-device recognition path is
covered by F.6 / (c)(9): the audio is used only to recognise the practice word
and is never stored — which is exactly what `test_speech_privacy_guard.gd`
proves.

### C2. Thailand PDPA B.E. 2562 (2019)

Section 20 (English text from pdpathailand.com, HTTP 200; the thainetizen PDF
404'd and siam-legal returned 403):

> "In the event that the data subject is a minor who is not sui juris by marriage or has no capacity as a sui juris person under section 27 of the Civil and Commercial Code, the request for the consent from such data subject shall be made as follows..."
> (1) [paraphrase — the page's sub-clause text was not returned verbatim] where the minor's giving of consent is not an act the minor may do alone under Civil and Commercial Code ss. 22–24, consent must also come from the holder of parental responsibility;
> (2) verbatim: "Where the minor is below the age of ten years, the consent shall be obtained from the holder of parental responsibility over the child."

Section 19 (consent must be explicit, written or electronic, purpose
informed, clearly distinguishable, as easy to withdraw as to give) was not
retrievable from a primary page today and is **not** quoted; it is cited as
"see Section 19" pending a fetch.

Application: the target users (3–6) are below ten, so *only* the holder of
parental responsibility can consent; the child cannot. Consent must be
explicit and withdrawable (Section 19), which is the "Delete learning history
/ revoke" flow in §F. Sending transcripts to a US provider is a cross-border
transfer under the PDPA's transfer section (commonly cited as Section 28 —
**not fetched today; verify the section text before relying on it**), which
needs an adequate destination or an exception such as informed consent.

### C3. GDPR Article 8 (gdpr-info.eu, HTTP 200) — only if EU users are served

> "in relation to the offer of information society services directly to a child, the processing of the personal data of a child shall be lawful where the child is at least 16 years old" — below that "only if and to the extent that consent is given or authorised by the holder of parental responsibility", Member States may lower the age "provided that such lower age is not below 13 years".

> "The controller shall make reasonable efforts to verify in such cases that consent is given or authorised by the holder of parental responsibility over the child, taking into consideration available technology."

Application: same consent design as COPPA/PDPA; additionally a DPIA is
expected for systematic processing of children's data with an AI provider,
and Standard Contractual Clauses / the EU-US Data Privacy Framework status of
the provider must be checked at the time. Not a blocker if the EU is not a
launch market; recorded as a gate condition scoped to EU distribution.

### C4. Google Play Families Policy (support.google.com/googleplay/android-developer/answer/9893335, HTTP 200)

> "If one of the target audiences for your app is children, you must comply with the following requirements."
> "You must disclose the collection of any personal and sensitive information from children in your app"
> "You must ensure that your app ... is compliant with the U.S. Children's Online Privacy and Protection Act (COPPA), E.U. General Data Protection Regulation (GDPR)"
> "Apps that solely target children must not transmit Android advertising identifier (AAID), SIM Serial, Build Serial, BSSID, MAC, SSID, IMEI, and/or IMSI"
> "Apps that solely target children must not contain any APIs or SDKs that are not approved for use in primarily child-directed services"
> Ads: "Only use Google Play Families Self-Certified Ads SDKs" and no interest-based advertising or remarketing.
> "Your app must have a privacy policy that accurately reflects data collection and handling practices"

Current state (from `docs/GOOGLE_PLAY_RELEASE_READINESS.md`): no ads, no SDKs,
no `INTERNET` permission, Data Safety answer "no data collected" — all of which
the cloud path would change (INTERNET permission, "App activity / other
user-generated content" shared with a third party, privacy policy update).
`clientId` is app-generated, not AAID/IMEI, which is the right choice.

### C5. Apple App Review Guidelines (developer.apple.com/app-store/review/guidelines, HTTP 200)

1.3 Kids Category: apps "must not include links out of the app, purchasing
opportunities, or other distractions to kids unless reserved for a designated
area behind a parental gate"; "Kids Category apps may not send personally
identifiable information or device information to third parties"; "should not
include third-party analytics or third-party advertising".

5.1.4 Kids: "Apps intended primarily for kids should not include third-party
analytics or third-party advertising." Apps that "collect, transmit, or have
the capability to share personal information (e.g. name, address, email,
location, photos, videos, drawings, **the ability to chat**, other personal
data, or persistent identifiers used in combination with any of the above)
from a minor must include a privacy policy and must comply with all applicable
children's privacy statutes. For the sake of clarity, the parental gate
requirement for the Kid's Category is generally not the same as securing
parental consent to collect personal data under these privacy statutes."

5.1.1(i): privacy policy must "Identify what data, if any, the app/service
collects, how it collects that data, and all uses of that data", confirm
third parties give equal protection, and "Explain its data retention/deletion
policies and describe how a user can revoke consent and/or request deletion".

5.1.2(i): "You must clearly disclose where personal data will be shared with
third parties, **including with third-party AI**, and obtain explicit
permission before doing so."

Application: the cloud tutor is "the ability to chat" plus a persistent
identifier; it needs the privacy policy, explicit permission for third-party
AI sharing, and a consent mechanism distinct from the 3-second gate. The
existing gate remains correct for what it does (controls, prices as text, the
copied link).

---

## D. The gate — all must be TRUE before `little_days/ai_tutor/cloud_enabled` may be true in ANY build

| # | Condition | Status 2026-09-20 | Evidence / what is missing |
| --- | --- | --- | --- |
| G1 | Zero Data Retention (or Modified Abuse Monitoring) approved by OpenAI and confirmed on the organisation/project that holds the key | **FALSE** | No OpenAI organisation, no key, no sales contact. Required by B4 before any under-13 personal data is processed. |
| G2 | Written provider position covering under-13 transcript processing for this use, or an architecture that meets OpenAI's published Under-18 guidance point by point (ZDR, content filter, disclosures, monitoring/escalation) | **FALSE** | Guidance fetched and quoted (B4). Validator + fallback exist (`turn_validator.js`); ZDR (G1), monitoring/escalation path and the in-app AI disclosure to the child do not. |
| G3 | Verifiable parental consent flow (a §312.5(b)(2) method, separate consent for third-party disclosure) implemented, recorded server-side with revocation, and driving token issuance | **FALSE** | Only a DEV_MODE mint route exists (finding H1); the 3 s hold is a gate, not consent (Apple 5.1.4(b), FTC I.4). Design in §F. |
| G4 | Privacy policy URL live, specific to this app, stating the cloud data flow, provider, retention, deletion and revocation | **FALSE** | `GOOGLE_PLAY_RELEASE_READINESS.md` §4: "No such page exists yet (OWNER)". |
| G5 | Play Data Safety form and App Store privacy labels aligned with the cloud flow (user-generated content shared with a third party; app-generated identifier) | **FALSE** | No Play Console app; current answers assume "no data collected". |
| G6 | No raw audio upload — device recognises on-device and sends text only; backend accepts no audio | **TRUE** | `test_speech_privacy_guard.gd`, `test_tutor_privacy_guards.gd`; backend has no audio field or endpoint (A2). Re-review required if `STT_MODE=cloud` is ever implemented. |
| G7 | Backend secret management: key in a managed secret store on the host, rotated, never in env files in the repo, `PARENT_APPROVAL_SECRET` distinct and ≥ 32 random bytes, TLS terminated in front, `HOST` not `0.0.0.0` without a proxy | **FALSE** | No host exists. Repo hygiene is TRUE (`.env.example` names only; `.env` and `data/` ignored; §G scan clean). |
| G8 | Independent penetration test of the backend with the H/M findings in `ALIZ_TUTOR_SECURITY_FINDINGS.md` closed | **FALSE** | Static review only; H1–H4, M1–M7 open. |
| G9 | Monthly budget guard on by default (fail closed when the OpenAI provider is selected without `MONTHLY_BUDGET_USD`) plus a per-client daily turn cap | **FALSE** | `config.js:58` defaults to no limit (finding H4). |
| G10 | Written retention schedule implemented in code: sessions/idempotency purged after the session, per-turn usage aggregated ≤ 30 days, client-scoped delete endpoint | **FALSE** | `store.js` never deletes (finding M4); required by the 2025 COPPA retention amendment (FTC release quoted in C1; the amended §312.10 text itself was not fetched today) and Apple 5.1.1(i). |
| G11 | Logs carry no `clientId`, session id or transcript at info level | **FALSE** | `server.js:35` logs the full URL (finding M1). |
| G12 | Android build declares `INTERNET` only in a build where G1–G11 are TRUE; Families declaration and content rating re-done for that build | **FALSE** (correctly — no INTERNET today) | `export_presets.cfg`; `test_tutor_privacy_guards.gd` fails on `permissions/internet=true`. |
| G13 | In-app parent text updated in the same commit that flips the flag (the sentence "The online AI tutor is switched off in this build" must go) and the child sees an age-appropriate "Aliz is a computer helper" line before the first cloud turn | **FALSE** | Text for the OFF state exists (`ALIZ_TUTOR_PARENT_INFO.md`); ON-state copy does not. |
| G14 | Thailand PDPA: consent from the holder of parental responsibility for under-10s, Section 19-compliant notice, cross-border transfer basis documented, DPO/contact named | **FALSE** | Depends on G3/G4. |
| G15 | If distributed in the EU: Article 8 parental-consent verification, DPIA on file, transfer mechanism to the provider confirmed | **FALSE / N/A until EU launch** | Not a launch market today. |
| G16 | Client guards green: `test_tutor_flags.gd` + `test_tutor_privacy_guards.gd`, and the network allowlist contains only the flag-checked tutor files | **TRUE** | Suite: 144 cases, 0 failures on 2026-09-20 in this worktree. |
| G17 | The server, not the client, is the authority for lesson text placed in the prompt (client-supplied `hint`/`nextQuestionText` ignored) | **FALSE** | Finding M2. |

Rule: the lead flips the flag only by editing `project.godot` in a commit whose
message links this document with every row TRUE, and `test_tutor_flags.gd`
must be updated in that same commit (it currently fails on `cloud_enabled=true`
by design). No developer user-arg path exists in an exported build
(`OS.get_cmdline_user_args()` is empty on device).

---

## E. What may ship now: the local scripted tutor, and why it is compliant

The local tutor (LessonEngine → ScriptedConversationProvider → bundled voice /
on-device TTS → face) may ship in public builds with the flag off, because:

1. **No network.** No network class exists under `game/`; Android has no
   `INTERNET` permission; `TutorFlags.cloud_enabled()` is false in
   `project.godot` and both presets; all four facts are test-enforced.
2. **No personal information collected.** The only new stored data is
   `tutorProgress` (counts) and the local quota (seconds per UTC day), both in
   `user://profile.json`, both erasable from Parent Corner, neither containing
   words the child said. Nothing is transmitted, so COPPA's *collection*
   trigger (gathering personal information *online*) is not met; the persistent
   identifier `clientId` is not even generated in the local path.
3. **On-device recognition only.** The speech layer is unchanged: iOS native
   recognition with `requiresOnDeviceRecognition = YES`, no audio to disk, no
   transcript persisted (FTC FAQ F.6 posture, but stricter — nothing is
   retained at all). The tutor reaches it only via `SpeechService`.
4. **Parental gate for controls.** Tutor controls (daily minutes, erase
   history, privacy information) sit behind the unchanged 3 s hold, which is
   what Apple 1.3 requires for a *control area*; no link, no purchase, no
   third-party SDK, no analytics.
5. **Content is deterministic and reviewed.** Every line Aliz says comes from
   bundled lesson JSON validated by the same TutorTurn rules (length, ASCII,
   no URLs, banned words) that the cloud path would use, so the child-safety
   bar does not depend on the provider.
6. **Honest UI.** The parent text states the cloud tutor is off and cannot be
   turned on from the app (`ALIZ_TUTOR_PARENT_INFO.md`).

Residual notes for the local ship: keep the Data Safety answer "no data
collected"; the privacy policy URL is still required by both stores
independently of the tutor (existing OWNER item).

---

## F. Parental consent design for the future cloud path

Who consents: the holder of parental responsibility (PDPA s.20(2), COPPA
"parent"), never the child; the child is under the age of digital consent in
every jurisdiction considered.

How it is obtained (must be a §312.5(b)(2) method, and because transcripts
go to a third party the "email plus" shortcut is **not** available):

1. Parent Corner → "Learn with Aliz online" → full-screen notice (English +
   Thai): what is sent (typed-out words the device recognised, the lesson
   step), to whom (Little Days server; OpenAI as processor under ZDR), what is
   not sent (audio, name, location, device ids), retention (server: session
   data purged after the session, usage counts 30 days; provider: none under
   ZDR), how to stop (this screen, any time), contact, policy version.
2. Verification by one of: (a) a card transaction of a nominal amount with a
   notification (this can coincide with a Family Club purchase once billing
   exists — but the *free* tier needs a card-free path too), or (b) a signed
   consent form returned by e-mail scan, or (c) a video call — choose (a) plus
   (b). Record `{consentId, clientId, method, policyVersion, consentedAt,
   verifierRef, ipCountry}` server-side; the device holds only `consentId`.
3. Separate, explicit consent line for "share my child's practice words with
   the AI provider" (2025 COPPA third-party disclosure consent; Apple 5.1.2(i)
   "including with third-party AI"). Without it the cloud tutor stays off
   even if the rest is consented.
4. The parent-approval token is minted **from** the consent record
   (`sub = consentId`, short TTL, refreshed while the record is active) — not
   from the gate; `verify()` checks the record is not revoked (finding H1/H2).

How it is revoked: Parent Corner → "Stop online tutor" (behind the gate) →
`POST /consent/{id}/revoke` → record gets `revokedAt`, all tokens for it
refuse, quota keys under that `clientId` are deleted; offline the device
flips to the scripted tutor immediately and retries the revoke call later.

"Delete learning history": one row, behind the gate, two steps (tap, then
hold-to-confirm using the BAR gate). Device side: remove `tutorProgress`,
`tutorLocalQuota`, `clientId`. Server side: `DELETE /client/{clientId}`
authenticated by the parent token → sessions, usage, turns, idempotency and
the consent record for that client are deleted; response confirms counts.
Provider side: nothing to delete under ZDR; without ZDR the honest answer is
"the provider may keep a copy for up to 30 days", which is one more reason G1
is first.

Re-consent triggers: policy version change, provider change, any new data
field, or 12 months elapsed.

---

## G. Repository secret scan — run 2026-09-20 in this worktree (all branches, 188 commits, 13 refs)

Commands and results:

```
git log --all -S"sk-" ... | grep -oE "sk-(proj-)?[A-Za-z0-9_-]{20,}"      -> no matches
  (25 commits contain the two-character sequence; the only key-shaped hit is the
   test placeholder 'sk-test-not-real' in backend/test/openai_provider.test.js,
   commits b784917 / 1ec9cbc — 15 chars, not a key; finding L9 asks to rename it)
git log -p --all -S"OPENAI_API_KEY=" | grep -E "OPENAI_API_KEY=\S+"        -> no matches with a value
git log -p --all -S"MESHY_API_KEY"   | grep -E "MESHY_API_KEY=\S+"         -> only 'MESHY_API_KEY=...' placeholders in docs/scripts
git log -p --all | grep -oE "msy_[A-Za-z0-9]{10,}"                          -> no matches (Meshy token shape)
git log -p --all | grep -oiE "bearer [A-Za-z0-9_-]{20,}"                    -> no matches
git log -p --all | grep -oE "(AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}|xox[baprs]-...|AIza[0-9A-Za-z_-]{30,}|sk_live_...)" -> no matches
git log --all --diff-filter=A --name-only | grep -E "\.env(\.|$)|backend/data/|\.keystore$|\.jks$|\.p12$" -> only backend/.env.example
```

Result: **clean.** The Meshy key has never been committed (re-verified); no
OpenAI key, bearer token, keystore or `.env` has ever entered history on any
branch. `backend/.env.example` (backend branch) contains names only; the guard
test re-checks this on every run once the backend directory is present.

---

## H. Blockers and asks for the lead

1. Nothing in this pass blocks shipping the **local** tutor.
2. The cloud path is blocked on G1 (OpenAI ZDR approval — a sales
   conversation, not code) and G3 (real consent flow, backend + UI). Everything
   else is downstream of those two.
3. Route `ALIZ_TUTOR_SECURITY_FINDINGS.md` H1–H4 to Agent D before any
   non-DEV_MODE run, M1–M7 before any child uses the cloud path.
4. Agents E and F: add your network files to `NETWORK_ALLOWLIST` in
   `test_tutor_privacy_guards.gd` (one line each, with the owner comment) and
   construct `HTTPRequest` lazily after `TutorFlags.cloud_enabled()`; the test
   proves source order.
5. Contract nit: the local quota key is `tutorLocalQuota` in the classroom
   worktree while the contract says `tutorQuota`; reconcile before merge so
   "Delete learning history" removes the right key.
6. Owner: publish the privacy-policy URL (needed for the local ship too), and
   decide whether US and EU are launch markets — that decides whether G15 is
   real.
