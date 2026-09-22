# Naming & Trademark Review — Founder Preview

**Prepared:** 2026-09-19
**Subject:** Proposed public title "Little Days", subtitle "Care, Play & Grow", characters "Aliz" and "Bunny"
**Current internal/working name:** Little Buddy
**Product:** Offline-first children's English-learning game, ages ~3–7, iOS first, Android later. Markets: Thailand + international/English.

> **I am not a lawyer. This is not legal advice.** This is a desk research report based on public app-store data and public trademark aggregator data retrieved on 2026-09-19. Nothing here clears a name for use. Before you spend money on a logo, a domain, or an App Store submission under a final name, have a trademark attorney run a formal clearance search in your actual target jurisdictions.

---

## VERDICT BOX — read this first

| Question | Answer |
| --- | --- |
| Is "Little Days" available as an app name? | **No.** Three live apps named "Little Days" / "LittleDaysFamily" exist on the Apple App Store today. Two of them are visible in the **Thai** storefront. |
| Is the period-tracker concern real? | **Not as stated — I could not verify any period/cycle tracker named "Little Days."** The real adjacency is different and arguably worse for you: see below. |
| Is there a real trademark problem? | **A moderate one.** A French registration for "Little Days" covers **class 41** (education/entertainment) and is live. No exact "LITTLE DAYS" registration found in the US, EU (EUIPO) or Thailand. |
| Biggest actual problem with "Little Days" | **Discoverability, not law.** "Little ___ Days" is the naming cluster owned by **baby-tracker and parenting-utility apps**. A parent searching it finds logging tools, not a game for their child. |
| Recommendation | **Switch.** Use a character-led brand: **"Aliz & Bunny"**, with a descriptive subtitle. Verified clear on the App Store and clear in TMview across all offices. |
| Is "Bunny" safe as the brand? | **No — do not use "Bunny" alone.** Playboy Enterprises holds an all-class "BUNNY" EU registration (classes 1–45, including 9, 28 and 41), and App Store "bunny" searches surface adult-labelled titles. As a *paired* element ("Aliz & Bunny") it is fine. |
| Is "Little Buddy" safe to keep as the **public** name? | **No.** It is heavily registered (incl. a live **US class 9** registration) and there is already a Google Play preschool-learning app and a Steam virtual-pet-care game literally named "Little Buddy". |
| Is "Little Buddy" safe to keep as an **internal** identifier? | **Yes.** Keep save keys, mission IDs, and the repo name. The owner separately changed the Android application ID to `com.joinanny.littledays` before its first Play upload; the Apple bundle ID remains `com.pointit.littlebuddy`. |

### The one-line version
"Little Days" is not legally catastrophic, but it is commercially weak: it is taken three times over, it is descriptive and hard to own, and it drops your children's game into the middle of the baby-tracker naming cluster. **Switch to "Aliz & Bunny", change only the display name, and freeze every internal identifier.**

---

## 0. Method — what I actually searched, and what I could not

Being precise about this matters, because "I searched and found nothing" and "I could not search this source" are very different risks.

### Sources I searched successfully

| Source | How | Coverage confidence |
| --- | --- | --- |
| **Apple App Store** | Apple's public iTunes Search/Lookup API, queried directly against the **US** and **TH** storefronts | High. Structured, first-party, live data. |
| **TMview** (`tmdn.org/tmview`) — the EUIPO-operated multi-office trademark aggregator | Queried its search API directly | High for breadth. Aggregates **USPTO, EUIPO, Thailand DIP** and ~70 other offices. |
| **Thailand trademark data specifically** | Verified TMview's Thai coverage is live by running a control query (`baby`, office=TH → 2,096 records returned) before trusting any Thai negative result | Good. The Thai negatives below are real searches, not gaps. |
| **Google Play, Steam, general web, children's media** | Web search | Medium. See limitation below. |

### Sources I could NOT search — treat these as gaps

1. **USPTO's own trademark search interface** (`tmsearch.uspto.gov`, the TESS replacement). It is a JavaScript single-page application; the server returns only the app shell with no data, and the underlying API endpoint rejected direct requests (HTTP 405). **All US trademark data in this report is TMview's mirror of USPTO records, not a first-party USPTO search.** TMview mirrors are generally current but can lag on very recent filings. Any US result here should be re-confirmed at uspto.gov before you rely on it.
2. **Thailand DIP's own portal** was not queried directly. Thai results here come via TMview's mirror of DIP data.
3. **Google Play has no public structured search API.** Play coverage here rests on web search only, so it is less complete than the App Store coverage. Assume Play collisions may exist that I did not surface.
4. **One App Store listing could not be verified.** An app "Little Days" at App Store ID `6456071590` (developer listed in search results as "YUJIN HAN", a three-line diary app) appears in indexed search results, but the listing now returns **HTTP 404 in both the US and French storefronts** and does not resolve in Apple's lookup API. It appears delisted. I could not confirm its current status.
5. **No registration numbers are quoted in this report** except where I retrieved them directly, and those are labelled as *application* numbers from TMview. I have not invented any serial number, registration number or filing date.

---

## 1. App store / Google Play name collision — "Little Days"

### 1.1 Apple App Store — three live collisions, confirmed

All three confirmed via Apple's own lookup API on 2026-09-19.

| App name | Developer / seller | Bundle ID | Category | Age rating | Notes |
| --- | --- | --- | --- | --- | --- |
| **Little Days - Baby Tracker** | David Lawlor | `com.littledaysapp.app` | Lifestyle, Health & Fitness | **12+** | Released 2026-05-22, updated 2026-06-20. Free + IAP (Pro $4.99/mo, $39.99/yr). Own site at `littledays.app`, tagline "the baby tracker built for 3am". Tracks feeds, sleep, nappies, growth. **Present in the Thai storefront.** |
| **Little Days - 무료 원본 아기 앨범** ("free original-quality baby album") | THURSDAY PLANET INC | `com.beyondy.littledays` | Social Networking, Lifestyle | 4+ | Released 2025-09-02, updated 2026-09-05. Private family baby photo/video album with invite-code family sharing. **Present in the Thai storefront.** Also on **Google Play** as `com.beyondy.littledays`. |
| **LittleDaysFamily** | Luke Hakso | `com.lukehakso.LittleDays` | Lifestyle | 4+ | Live in the US storefront. |
| *(unverified)* Little Days — diary app | listed as "YUJIN HAN" | — | — | — | App Store ID `6456071590`. Listing now 404s in US and FR. **Appears delisted; could not verify.** |

**Note on bundle IDs:** `com.littledaysapp.app`, `com.beyondy.littledays` and `com.lukehakso.LittleDays` are all taken. This does not block the independent identifiers: Android is `com.joinanny.littledays`; Apple remains `com.pointit.littlebuddy`.

### 1.2 Google Play

- **Little Days – 무료 원본 아기 앨범**, package `com.beyondy.littledays`, listing updated ~2026-07-23. Same publisher as the iOS baby-album app. Confirmed live.
- No children's game named "Little Days" surfaced on Play. **Caveat:** Play has no public search API, so this is a weaker negative than the App Store negatives.

### 1.3 Is there a children's game called "Little Days"? — verified negative

Searched the App Store with games/kids-oriented query terms and searched the web for a children's educational title by that name. **Nothing found.** The closest items were unrelated ("Guess The Days", "Little Kid Games Club", littlekidsgames.com). So the *genre* slot is open — the *name* is not.

### 1.4 The period-tracker claim — I could not verify it, and here is what I found instead

You asked me to verify that "Little Days" is a known period/cycle-tracking app name. **I ran four separate searches for this and could not verify it.** There is no period or menstrual-cycle tracker named "Little Days" that I could find on the App Store, on Google Play, or on the open web.

What I think happened is worth understanding, because the underlying instinct was right even though the specific fact was not. **"Days" is a heavily used token in the cycle-tracking naming cluster:**

- **My Days – Ovulation Calendar & Period Tracker** (Google Play, `com.chris.mydays`)
- **MyDays X – Women Cycle Calendar** (Google Play / App Store)
- **Cycle Days – Period Tracker** (Google Play)
- **Menstrual cycle tracker – Days** (Whisper Arts, Google Play)
- **DaysyDay – Period Tracker** (App Store / Google Play)

So "Little Days" does not collide with a specific menstrual app — but it sits inside a family of names that read as *women's-health tracking* to anyone scanning a store listing. **And the collision that does exist is structurally the same problem.** Read on.

### 1.5 The real discoverability problem — "Little ___ Days" is baby-tracker naming territory

This is, in my assessment, the most important finding in this report, and it is stronger evidence than the period-tracker concern would have been.

I collision-tested a set of candidate names in the same family. Every single "Little/Tiny/Growing + time/growth word" name I tested is already occupied by a **parenting utility** — a baby tracker, a pregnancy log, a childcare journal, or childcare-centre admin software:

| Name tested | What actually occupies it |
| --- | --- |
| Little Nest | *Little Nest: Baby Tracker Log* (Medical); *Little Nest: Pregnancy Tracker*; *Little Nest: Child Care App* |
| Tiny Days | *TinyDays* (Lifestyle); *Tiny Days – Baby Age Widget*; *TinyDays小日子* |
| Little Sprout | *LittleSprout* (Lifestyle); *Little Sprout – Baby Tracker*; *Little Sprout Baby Tracker* |
| Growing Days | *Growing Days: Baby Journal* |
| Baby Days / Baby's Days | *Baby's Days* — childcare-management software (App Store + Google Play, by SysIQ) |
| **Little Days** | *Little Days – Baby Tracker* (12+, Health & Fitness); *Little Days* baby album; *LittleDaysFamily* |

**What this means in practice.** Your customer is a parent searching for something their 3-to-7-year-old can play. If they search "Little Days", the store returns a 12+ baby-feed-and-nappy logger, a family photo album, and a family-sharing app. Your game is a 4+ children's game competing for that query against products for a completely different job. You would be spending your entire marketing budget teaching parents to disambiguate you from utilities you have nothing to do with.

**Brand-safety angle, stated accurately.** The confirmed adjacency is not a menstrual tracker — it is an app rated **12+** in **Health & Fitness** that logs infant feeding and nappies, and which ships in your primary market (Thailand). For a 4+ children's education title, that is still the wrong neighbourhood: wrong age rating, wrong category, wrong buyer intent. It is a milder problem than a period tracker would have been, but it is a real one, and it is verified rather than assumed.

### 1.6 Thai-language readability (my linguistic assessment, not a sourced finding)

- **"Little Days"** transliterates to roughly *ลิตเทิลเดย์ส* — four-plus syllables, with a final /dz/ cluster that Thai phonology does not carry. There is no established Thai loan form. It is hard for a Thai parent to recall, pronounce or type into a search box.
- **"Aliz"** maps cleanly to *อลิซ* — two syllables, and already familiar because it is the standard Thai rendering of *Alice*. Easy to say and recall. (Minor note: this also means Thai users will hear an *Alice in Wonderland* echo. I read that as neutral-to-helpful for memorability, but you should be aware of it and should not lean on Alice imagery.)
- **"Bunny"** is already a common Thai loanword, *บันนี่*. Easy.

On searchability in Thailand alone, "Aliz & Bunny" beats "Little Days" clearly.

---

## 2. Trademark risk — "Little Days"

**Method:** TMview multi-office search for "little days", all offices, all statuses, all classes → **39 records**. Then re-run restricted to **US + EUIPO + Thailand** → **17 records**, all of them US. Classes of interest: **9** (software, downloadable games) and **41** (education, entertainment, providing online games).

### 2.1 What I found

| Office | Mark | Status | Classes | Owner | Application date | Registration date | Relevance to you |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **FR** (France) | **Little Days** | **Registered** | **16, 35, 41, 42** | Madame Camille Paillery | 2018-09-26 | 2019-01-18 | ⚠️ **Most relevant hit.** Live registration for the exact words, covering **class 41**. App no. 4486003 per TMview. |
| US | LITTLE DAYS STUDIO | Registered | 42 | Katie Zupan Design LLC | 2025-01-17 | 2026-07-28 | Low. Class 42 (design services), and the mark adds "STUDIO". App no. 99007031 per TMview. |
| US | LITTLEDAYZ | Registered | **28** | Jiangyin Kunyu Cross-Border E-Commerce Co., Ltd. | 2020-12-30 | 2021-10-19 | Low–moderate. Class 28 covers toys/games. Different spelling. |
| US | LITTLEDAYZ BOUTIQUE | Filed | 22, 24, **28** | Shanghai Yujing Electronic Commerce Co., Ltd. | 2021-06-03 | — | Low. |
| GB | LITTLEDAYS | Registered | 25 | Anita Last | 2017-12-31 | 2018-04-06 | Low. Clothing. |
| IN | LITTLE DAYS | Registered | 25 | Amar Lal | 2015-07-12 | 2015-07-12 | Low. Clothing. |
| CN | 小日子 LITTLE DAYS | Registered / Ended | 39 / **41** | 苏州小日子文化创意有限公司 | 2015-04-14 | 2016 | The class 41 record shows **Ended**; class 39 is live. |

### 2.2 What I verified as absent

- **No exact "LITTLE DAYS" registration or application at the USPTO** in any class. The only US records are LITTLE DAYS STUDIO, LITTLEDAYZ and LITTLEDAYZ BOUTIQUE. *(Via TMview's USPTO mirror — see method gap #1. Re-confirm at uspto.gov.)*
- **No "LITTLE DAYS" record at EUIPO** (office code EM) in any class.
- **No "LITTLE DAYS" record in Thailand** in any class. This is a real search, not a gap — I verified TMview's Thai coverage is live first.

### 2.3 How I read the risk

**Moderate, and mostly not where you'd expect.** Your two priority markets — the US and Thailand — appear clear of the exact mark. That is genuinely good news for "Little Days" on a pure infringement basis.

The problems are:

1. **France, class 41.** A live French registration for the exact words covering education and entertainment services. It is a national French mark, not an EU-wide EUTM, so it does not block you across the EU. But it is an obstacle in France and a plausible basis for opposition if you ever try to register "Little Days" as an EUTM, because an earlier national right can be raised against a later EU application.
2. **You would be filing a descriptive, crowded mark.** "Little" plus "Days" is two ordinary English words with a weak, laudatory-descriptive feel. Marks like this are expensive to register, narrow when granted, and hard to enforce. You would be buying a fence you cannot defend.
3. **Registering does not fix section 1.** Even a granted registration would not move your game out of the baby-tracker search cluster.

**Net:** "Little Days" is *probably* usable without being sued in the US or Thailand. It is also *probably* not worth using.

---

## 3. "Little Buddy" — the current internal name

### 3.1 As a PUBLIC name: genuinely risky. You are right to rename.

**TMview search for "little buddy", all offices → 126 records.** This is a crowded mark. The records that matter:

| Office | Mark | Status | Classes | Owner | Application date |
| --- | --- | --- | --- | --- | --- |
| **US** | **LITTLE BUDDY** | **Registered** | **9** | **BLUE SKY TECHNOLOGY LLC** | 2018-06-15 |
| **GB** | **LITTLE BUDDY** | **Registered** | **41** | **Little Buddy Kindergarten UK LTD** | 2023-06-16 |
| SK | little buddy | Registered | 20, 25, **28** | Petra Jedličková | 2017-03-10 |
| US / EM | MY LITTLE BUDDY | Registered | **28** | Lone Wolf Direct Inc. | 2022 |
| US | LITTLE BUDDY YOGA | Registered | 41 | Behrens Enterprises, Inc. | 2012-10-16 |
| US | BUDDY THE LITTLE TAXI | Registered | 25, **41** | United Trademark Holdings, Inc. | 2016-09-19 |
| US | LITTLE BUDDY | Registered | 11 | Enerco Group, Inc. | 2009-03-30 |
| US | LITTLE BUDDY | Registered | 32 | Kwik Trip, Inc. | 2008-11-24 |
| NZ | Little Buddy | Expired | 28 | Zhenyang (David) Hou | 2006-07-03 |
| (plus ~115 further records across offices and classes) | | | | | |

A **live US class 9 registration for the exact words** is the single worst fact here — class 9 is downloadable software and video games, which is exactly your class.

**Thailand: zero records for "little buddy"** in any class. (Verified search.)

### 3.2 The product-level collisions are worse than the trademark ones

| Product | Platform | What it is | Why it hurts |
| --- | --- | --- | --- |
| **Little Buddy** | Google Play | Preschool learning app — alphabet A–Z, numbers 0–10, colours, for kindergarten/toddlers | Same name, **same category, same age band**. Direct head-on collision. |
| **Little Buddy** | Steam | Casual virtual-pet game: care for a companion, feed it, play with it | Same name, **same core loop as your game**. |
| **Little Buddy Care** | App Store | Early-childhood-centre management software | Same name, adjacent audience. |
| **Buddy.ai** | App Store / Google Play | **Voice-based AI English tutor for children ages 3–8**, games + cartoons, claims 1M+ monthly children | Not the same name, but it owns the "buddy + kids + spoken English" association at scale. Anything "Buddy" in your space reads as a Buddy.ai knock-off. |

That last row is the killer. Your product is a voice-and-touch English learning game for ages 3–7. Buddy.ai is a voice-based English learning app for ages 3–8 with a million monthly users. Shipping publicly as "Little Buddy" would look derivative even though your work is independent.

**Conclusion: rename the public title. This holds regardless of which new name you pick.**

### 3.3 As an INTERNAL identifier: safe to keep. Keep it.

**Yes — it is safe to keep "Little Buddy" and `littlebuddy` as internal identifiers, and you should.**

Reasoning:

- Trademark rights attach to **use in commerce as an indicator of the source of goods or services** — that is, what the customer sees and uses to identify who made the thing. A reverse-DNS bundle identifier, a save-file path, a git repo name, a GDScript class name and a mission ID are **engineering plumbing**, not consumer-facing branding. They do not function as source identifiers and are not how a confusion analysis is run.
- A bundle ID is technically visible in a few places (crash logs, MDM inventories, some diagnostic URLs). In my assessment this is negligible exposure. Thousands of shipped apps have bundle IDs that do not match their display name, usually because the product was renamed at some point — which is exactly your situation.
- The one thing that must be true: **"Little Buddy" must not appear anywhere a customer looks.** Not in the App Store name or subtitle, not in screenshots, not in the app's own UI, not in the keywords field, not in marketing copy, not in the privacy-policy heading.

I checked the repo. The identifiers currently in place:

| Identifier | Location | Verdict |
| --- | --- | --- |
| `application/bundle_identifier="com.pointit.littlebuddy"` | `game/export_presets.cfg:26` | **DO NOT CHANGE.** See section 6. |
| `config/name="Little Buddy"` | `game/project.godot:13` | **CHANGE THIS.** This is the on-device display name — the one string that is genuinely customer-facing. |
| `user://profile.json` | `game/scripts/save/profile_store.gd`, `save_service.gd`, `entitlement_*.gd` | **DO NOT CHANGE.** |
| `user://speech_diag.json` | `game/scripts/speech/speech_service.gd` | **DO NOT CHANGE.** |
| `profileVersion` and all save schema keys | `game/scripts/save/profile_store.gd` and ~10 test cases | **DO NOT CHANGE.** |
| Mission IDs | mission/content data | **DO NOT CHANGE.** |
| Repo name `little-buddy` | git | **DO NOT CHANGE.** No customer sees it. |

---

## 4. Character names — "Aliz" and "Bunny"

### 4.1 "Aliz" — clear, distinctive, and your most valuable naming asset

**App Store (US), searched "aliz" and "aliz bunny":** zero games, zero children's apps, zero education apps. The only "Aliz"-named apps are a Food & Drink app, a Turkish textile shop, a French medical guide, a construction-industry utility and a marina shop. **No conflict in your category at all.**

**TMview, "aliz" filtered to classes 9 and 41, all offices:** no live registration for the exact word "ALIZ" in either class anywhere relevant.
- US "ALIZ" class 41 (Fernandez, Alison L M, filed 2020-11-25) — status **Ended**.
- DE "ALiZ" classes 9/16/42 (ASSIP Sicherheitssysteme GmbH, filed 1997) — status **Expired**.
- Live "ALIZ" registrations exist but in unrelated classes: class 3 (cosmetics, US), class 17 (synthetic materials — a Chinese company filing broadly across many offices in late 2025), class 42 (Brazil, Hungary).
- **Thailand:** "ALIZ" registered in class 30 (food, Prairie Marketing) and class 11. **Neither touches software or education.** No conflict.

**Children's media:** no children's cartoon or kids-TV character named "Aliz" found. Nearest names are *Alizée* (French pop singer), *Ali the Fox* (Chinese cartoon) and *Ali Baba* — none are conflicts. The main association to be conscious of is phonetic proximity to **Alice**, which carries *Alice in Wonderland* imagery. Don't lean on that imagery and it is a non-issue; it may even help recall.

**Assessment: "Aliz" is clean, short, distinctive, pronounceable in both English and Thai, and unoccupied in your category. This is the strongest naming asset you have. Build the brand on it.**

### 4.2 "Bunny" — do not use it alone. Two hard reasons.

**TMview, "bunny", offices US + EUIPO + Thailand, classes 9/41/28 → 471 records.** The two that should stop you:

1. **Playboy Enterprises International, Inc. holds a live EUIPO registration for "Bunny"** covering **all 45 classes** — including 9, 28 and 41 (filed 2013-01-11, status Registered). An earlier expired all-class filing from 2004-12-14 is also on record. For a *children's* product, having your brand word owned across every class by an adult-entertainment company in the EU is a problem on two axes at once: it is a real opposition/enforcement risk, and it is a brand-association risk you cannot control.
2. **App Store discovery is contaminated.** A "bunny" search on the App Store surfaces **"Bunniiies: Uncensored Rabbit"**, which is explicitly flagged as not for children despite cute art. Your 4+ children's game would share a search surface with it.

Other notable records:
- **US "BUNNY", Registered, class 9** (Kiser, Starla J — filings 2021-09-29 and 2024-06-11).
- **EUIPO "BUNNY", Registered, classes 7/9/35** (Duracell Batteries BV).
- **Disney Enterprises, Inc. "BUNNY TOWN"** — US class 41 registered, EUIPO classes 9/16/25/28/41 registered (filed 2006). A Disney Junior children's property. Avoid anything close to "Bunny Town".
- **Thailand: "BUNNY CUTE", Registered, class 9** (Shenzhen Mofi Technology).
- **Disney/Pixar "Bunny"** — a named character (a blue plush rabbit, voiced by Jordan Peele) in *Toy Story 4*, paired with "Ducky", with spin-off shorts *Fluffy Stuff with Ducky and Bunny*. Character names are generally not protectable on their own when this generic, and a baby rabbit named Bunny in an unrelated learning game is not plausibly confusing with a Pixar carnival-prize toy. But it does mean **"Bunny" as a headline brand word invites a Disney-adjacent comparison you will never win.**

**Genre crowding, separately:** the bunny-care mobile game space is saturated — *Bu Bunny – Cute pet care game*, *Bunnsies – Happy Pet World*, *Baby Bunny – My Talking Pet*, *Cute Bunny Life Simulator 3D*, *My Virtual Rabbit*, *bunny world: playtime & Learn*, *Bunny Pop!*, *Usagi Shima*. Leading with "Bunny" puts you in the middle of a low-quality, high-volume category.

### 4.3 Is "Aliz & Bunny" more defensible than "Bunny"? — Yes, substantially.

**Yes, and this is the key strategic point of the whole report.**

- **Trademark law rewards the composite.** In a likelihood-of-confusion analysis, what matters is the mark as a whole and its **dominant distinctive element**. In "Aliz & Bunny", the dominant element is unambiguously **"Aliz"** — an invented, arbitrary, category-clear word. "Bunny" recedes into a weak, descriptive-of-the-character role. Playboy's all-class "Bunny" registration is a serious obstacle to registering *"Bunny"*; it is a much weaker obstacle to *"Aliz & Bunny"*, where "Bunny" is not what makes the mark distinctive.
- **Verified clear.** TMview search for **"aliz bunny", all offices, all classes: 0 records.** App Store search for "Aliz and Bunny" / "Aliz & Bunny": **no exact-name app, and no app with "aliz" in the name in any games/kids/education category.**
- **It fixes the discovery problem.** A two-name pairing reads immediately as a *story with characters* — which is what a children's game is — rather than as a utility or a generic pet-care sim.
- **It is how this genre actually brands successfully.** Character-pair naming is the established pattern for durable preschool properties (*Max & Ruby*, *Ducky and Bunny*, *Bing and Flop*). It gives you a franchise container: "Aliz & Bunny: Bath Time", "Aliz & Bunny: Snack Time" — which maps directly onto the mission structure you already have in the repo.
- **It works in Thai.** *อลิซกับบันนี่* — both halves are natural in Thai.

**Recommendation: use the pairing. Never ship "Bunny" as the standalone brand.**

---

## 5. Alternatives — ranked, with real collision-check results

Each name below was checked against the Apple App Store (US storefront, via Apple's API, exact-name and prefix matching) and, where meaningful, against TMview. Results are what I actually found on 2026-09-19.

### Tier 1 — recommended

| # | Title | Collision check result | Assessment |
| --- | --- | --- | --- |
| **1** | **Aliz & Bunny** | App Store: **no exact-name app; no "aliz" app in games/kids/education at all.** TMview "aliz bunny", all offices, all classes: **0 records.** | ⭐ **Best option.** Distinctive, ownable, franchise-ready, clean in English and Thai, correct genre signal. Pair with a descriptive subtitle for search. |
| **2** | **Aliz & Bunny: Care, Play & Grow** | Same clearance as #1. "Care Play Grow" as a phrase: no exact-name app. | Same strengths as #1 with your existing subtitle preserved. Good if you want the promise in the title. Slightly long for a store title field. |
| **3** | **Aliz's Little World** / **Aliz World** | App Store: no exact-name app for either. Only 6–9 results returned for these queries at all, i.e. a near-empty namespace. | Strong. Keeps "Little" warmth without entering the "Little ___ Days" tracker cluster. Weaker than #1 because it drops Bunny, losing the character-pair advantage. |

### Tier 2 — usable, with caveats

| # | Title | Collision check result | Assessment |
| --- | --- | --- | --- |
| 4 | **Bunny Grows Up** | App Store: no exact-name app. TMview: no hit. | Clear on paper, but leans entirely on generic "Bunny", so it inherits the Playboy-EUTM and adult-adjacency problems from §4.2. Also conceptually collides with existing copy — *Bu Bunny* ("help her grow up") and *Bunnsies* ("from babies to adults") use the same hook. |
| 5 | **Bunny & Me** | App Store: no exact-name app. | Warm and readable, but "Bunny" is the dominant element → same §4.2 exposure. Also reads as a virtual-pet game rather than a learning game. |
| 6 | **Hello Bunny** | App Store: no exact-name app. | Clean and simple; "Hello" helps signal language learning. But dominant "Bunny", and close to the *Hello Kitty* cadence, which is a Sanrio-shaped shadow you don't need. |
| 7 | **Bunny Bright** | App Store: no exact-name app. | Clear, and "Bright" signals learning. Weakest on meaning — it does not tell a parent what the app does, and it drops Aliz. |
| 8 | **Bunny Days** | App Store: no exact-name app. TMview, US+EUIPO+TH, classes 9/41/28: **0 records.** | Surprisingly clear on direct search. **But** it keeps the "___ Days" tracker-cluster problem (*TinyDays*, *Tiny Days – Baby Age Widget*, *TinyDays小日子*) *and* adds the standalone-Bunny problem. Worst of both. |
| 9 | **Little Bunny Days** | App Store: no exact-name app. | Clear name, wrong shape. Sits squarely in the "Little ___ Days" parenting-utility cluster documented in §1.5. Do not solve one problem by re-creating it. |

### Tier 3 — rejected, and this is the useful part

Do not use these. Each is already occupied, and together they are the evidence for §1.5:

| Title | Why rejected |
| --- | --- |
| **Little Days** (proposed) | Three live App Store apps + one Google Play app. Inside the baby-tracker cluster. FR class 41 registration. |
| **Little Nest** | *Little Nest: Baby Tracker Log*, *Little Nest: Pregnancy Tracker*, *Little Nest: Child Care App*, *Little Nest Mumbai* (Reliance Foundation). |
| **Tiny Days** | **Exact-name collision:** *TinyDays* (Lifestyle). Plus *Tiny Days – Baby Age Widget*, *TinyDays小日子*. |
| **Little Sprout** | **Exact-name collision:** *LittleSprout* (Little Sprout LLC). Plus two baby trackers and *Little Sprouts Play Studio*. |
| **Growing Days** | *Growing Days: Baby Journal*. |
| **Baby Days / Baby's Days** | *Baby's Days* — childcare-management software on both stores. |
| **Little Buddy** (current) | Live US class 9 registration; Google Play preschool app of the same name; Steam pet-care game of the same name; Buddy.ai shadow. |
| **Bunny** (alone) | Playboy all-class EUTM; *Bunniiies: Uncensored Rabbit* in the same search surface; saturated genre. |

### 5.1 How to actually deploy the winner

App Store gives you a title field and a subtitle field, and they are indexed differently. Use the title for **brand** and the subtitle for **search**:

- **Title:** `Aliz & Bunny`
- **Subtitle (English):** `Care, Play & Learn English` — keeps your promise, and puts the words a parent actually searches ("learn English", "kids") into an indexed field.
- **Subtitle (Thai locale):** localise rather than transliterate — something on the order of *ดูแล เล่น เรียนภาษาอังกฤษ*. Have a native Thai speaker write this; do not machine-translate your store listing.
- **Keywords field:** this is where "toddler", "preschool", "ages 3-5", "English for kids", "caregiving" belong — not in the title.

This structure is why you do not need a descriptive *title*. The subtitle and keyword fields do the discovery work, leaving the title free to be distinctive and ownable — which is exactly what makes it protectable later.

---

## 6. Recommendation

### 6.1 Switch. Do not ship as "Little Days".

**Recommendation: adopt "Aliz & Bunny" as the public title, with "Care, Play & Learn English" as the subtitle.**

Honest framing of why — and note that the reason is *commercial*, not legal:

- "Little Days" is very likely **legally survivable** in the US and Thailand. I found no exact registration in either. If you shipped it, the realistic worst case is a French class-41 rights-holder objection and an awkward EUTM filing, not an existential lawsuit.
- But it is **commercially wrong**, for four verified reasons: (1) three live App Store apps already use it, two of them in your Thai market; (2) the name sits inside the baby-tracker/parenting-utility naming cluster, so parents searching it will find logging tools rather than a game; (3) it is descriptive and weak, so it is expensive to register and nearly impossible to defend; (4) it transliterates badly into Thai.
- **The period-tracker concern specifically did not check out.** I could not find any period or cycle tracker named "Little Days", and I want to be explicit that I did not find it rather than quietly confirming a plausible assumption. The concern behind it was sound — the name *does* read as a health/tracking utility — but the specific fact was not. What I found instead is a 12+ Health & Fitness infant-tracking app of the same name shipping in Thailand, which is a milder but genuinely verified version of the same problem.
- Meanwhile **"Aliz & Bunny" is clear on every check I could run**, is distinctive enough to actually own, reads correctly as a children's story property, extends into a franchise that matches your existing mission structure, and works in both Thai and English.

You have already decided to move off "Little Buddy". Since you are paying the renaming cost once, pay it for a name worth owning.

### 6.2 What to do about internal identifiers — display-name-only migration

**This is the safe path, and it is the only path I would endorse: change the display name; freeze everything else.**

#### DO NOT RENAME — freeze these

| Identifier | Where | Why it must not change |
| --- | --- | --- |
| `com.pointit.littlebuddy` | `game/export_presets.cfg:26` | **Apple does not permit changing a bundle identifier after the first App Store / TestFlight submission.** Changing it creates a *different app*: it orphans existing installs, breaks TestFlight continuity, breaks provisioning profiles and certificates, breaks push/entitlement configuration, and forfeits any App Store Connect record. There is no upside — nothing a customer evaluates depends on it. |
| `user://profile.json` | `profile_store.gd`, `save_service.gd`, `entitlement_provider.gd`, `entitlement_service.gd`, `local_entitlement_provider.gd` | Renaming the save path silently wipes every existing player's stars and progress. The path is invisible to users. Zero benefit, maximum harm. |
| `user://speech_diag.json` | `speech_service.gd`, `speech_diagnostics_panel.gd` | Same reasoning. Diagnostic artefact, invisible, referenced in multiple places. |
| `profileVersion` + all save schema keys | `profile_store.gd` + ~10 test cases | Schema keys are a contract with data already on devices. Renaming them means writing a migration for no product reason, and it would invalidate `test_save_migration.gd` and the device fixture `device_profile_v1.json`. |
| **Mission IDs** | mission/content data, `mission_replay.gd` | Mission IDs are join keys — they appear in save data (`completedActivities`), in QA replay harnesses, and in content JSON. Renaming them breaks saved progress *and* the replay proofs you just built. |
| Repo name `little-buddy`, git history, branch names | git | No customer ever sees a repo name. Renaming costs remote reconfiguration and breaks every existing link and clone for zero gain. |
| GDScript class names, script filenames, autoload names, node names | throughout `game/` | Internal code vocabulary. Renaming is pure churn and pure regression risk. |
| iOS native plugin identifiers and any `com.pointit.littlebuddy` references in `game/ios/` | `game/ios/` | Must stay consistent with the bundle ID. |

#### DO RENAME — this is the whole migration

| Item | Where | Change to |
| --- | --- | --- |
| `config/name="Little Buddy"` | `game/project.godot:13` | `config/name="Aliz & Bunny"` — this is the on-device home-screen name, the single genuinely customer-facing string in the project file. |
| App Store Connect app name | App Store Connect | `Aliz & Bunny` |
| App Store Connect subtitle | App Store Connect | `Care, Play & Learn English` (+ localised Thai subtitle) |
| Any title text rendered in the game UI (splash, title screen, about/settings) | `game/scenes/`, `game/scripts/ui/` | Must read the new display name — see the pattern below. |
| Marketing copy, screenshots, website, privacy policy heading | docs + store assets | New name. Ensure "Little Buddy" appears nowhere a customer looks. |

#### The `internalId` / `displayName` pattern

Establish the separation once, so this never has to be a rename again:

- Define the public title in **exactly one place** — a config/content constant or a small branding resource, e.g. `displayName: "Aliz & Bunny"` alongside `internalId: "littlebuddy"`.
- All child-facing UI reads `displayName`. Nothing in gameplay, save, speech, content or QA code ever reads it.
- All persistence, mission wiring, bundle configuration, telemetry-free local keys and test fixtures continue to use `internalId` and the existing frozen strings.
- Keep `displayName` localisable, since you need a Thai store presence anyway.

The result: if you rename again for launch, you touch one string and the App Store Connect metadata. Nothing else moves. This also keeps the rename compatible with your architecture rule that domain logic stays engine-agnostic — branding is presentation, and it should live on the presentation side of that line.

#### Is keeping `littlebuddy` internally a trademark risk?

In my (non-lawyer) assessment: **no, and this is a well-trodden situation.** Trademark liability turns on use of a mark *in commerce as an indicator of source* — what the customer sees and relies on to identify who made the product. Reverse-DNS bundle identifiers, save-file paths, repo names, class names and mission IDs are engineering internals that no customer uses to identify anything. Plenty of shipped apps have bundle IDs that do not match their display names, usually for exactly this reason. The condition is the one stated above: **"Little Buddy" must not appear in any customer-facing surface** — store name, subtitle, keywords, screenshots, in-app UI, or marketing.

### 6.3 Action checklist

**Before the Founder Preview:**
1. [ ] Decide the name. My recommendation: **Aliz & Bunny**.
2. [ ] Change `config/name` in `game/project.godot`. Change nothing else in that file.
3. [ ] Introduce the `displayName` / `internalId` split; point all UI title text at `displayName`.
4. [ ] Grep the repo for "Little Buddy" in **customer-facing** strings only (UI scenes, scripts under `game/scripts/ui/`, store assets). Leave code identifiers, save keys, mission IDs and the bundle ID alone.
5. [ ] Verify `com.pointit.littlebuddy` is untouched in `export_presets.cfg` and that an Xcode export still installs over an existing device build without wiping `user://profile.json`.
6. [ ] Run the test suite — particularly `test_save_migration.gd`, `test_profile_store.gd` and `test_mission_replay.gd` — to confirm the rename touched no persistence contract.

**Before any public launch or spend:**
7. [ ] Re-run a first-party **USPTO** search for the final name at uspto.gov (I could not reach it — see method gap #1).
8. [ ] Re-run a first-party **Thailand DIP** search for the final name.
9. [ ] Check **Google Play** manually for the final name (no public API; my Play coverage is incomplete).
10. [ ] Check domain and social handle availability for the final name.
11. [ ] Have a trademark attorney run formal clearance in the US, Thailand and the EU in **classes 9 and 41** before you file anything or commit to brand assets.
12. [ ] Consider filing for the final name in class 9 and class 41 in your two priority markets. A distinctive mark like "Aliz & Bunny" is worth filing; a descriptive one like "Little Days" largely is not — which is itself a reason to prefer the former.

---

## Appendix — search log

**All searches performed 2026-09-19.**

| Query | Source | Result |
| --- | --- | --- |
| `little days` | Apple iTunes Search API, US storefront, entity=software | 39 results; 3 name matches |
| `little days` | Apple iTunes Search API, **TH** storefront | 44 results; 2 name matches |
| `little days game kids` | Apple iTunes Search API, US | 50 results; **0** name matches |
| `little buddy` | Apple iTunes Search API, US and TH | 40 / 47 results; **0** name matches |
| `aliz`, `aliz bunny` | Apple iTunes Search API, US | 23 / 36 results; no games, kids or education apps |
| ID lookups `6456071590`, `6749217880`, `6761469269` | Apple iTunes Lookup API | 2 live, 1 not found (delisted) |
| 14 candidate alternative titles | Apple iTunes Search API, US, exact + prefix matching | 2 exact collisions (TinyDays, LittleSprout); results in §5 |
| `little days` | TMview, all offices, all classes | 39 records |
| `little days` | TMview, offices US + EM + TH | 17 records (all US); **0** at EUIPO, **0** in Thailand |
| `little buddy` | TMview, all offices | 126 records |
| `little buddy` | TMview, office TH | **0** records |
| `little buddy` | TMview, US + EM, classes 9/41/28 | 15 records |
| `aliz` | TMview, all offices / classes 9+41 | fuzzy result set; no live exact-word conflict in 9 or 41 |
| `aliz bunny` | TMview, all offices, all classes | **0** records |
| `bunny` | TMview, US + EM + TH, classes 9/41/28 | 471 records |
| `bunny days` | TMview, US + EM + TH, classes 9/41/28 | **0** records |
| `baby` | TMview, office TH | 2,096 records — **control query confirming Thai coverage is live** |
| `Little Days` period/cycle tracker | Web search ×4 | **Not verified. No such app found.** |
| `Aliz` children's media | Web search | No children's character by that name |
| Toy Story 4 "Bunny" | Web search | Confirmed Disney/Pixar character, paired with "Ducky" |
| `littledays.app` | Direct fetch | Baby tracker; **no ™ or ® symbol shown on the name** |

### Sources

- [Little Days — Baby Tracker (App Store)](https://apps.apple.com/app/id6761469269) · [littledays.app](https://littledays.app/)
- [Little Days — baby album (App Store)](https://apps.apple.com/us/app/id6749217880) · [same app on Google Play](https://play.google.com/store/apps/details?id=com.beyondy.littledays)
- [TMview — multi-office trademark search (EUIPO/TMDN)](https://www.tmdn.org/tmview/)
- [USPTO trademark search](https://www.uspto.gov/trademarks/search) *(could not be queried programmatically — see method gap #1)*
- [Little Buddy — preschool learning app (Google Play)](https://play.google.com/store/apps/details?id=com.littlebuddy)
- [Little Buddy — virtual pet game (Steam)](https://store.steampowered.com/app/3289230/Little_Buddy/)
- [Little Buddy Care (App Store)](https://apps.apple.com/us/app/little-buddy-care/id6749705417)
- [Buddy.ai — Kids Learning Games (App Store)](https://apps.apple.com/app/id1255783056)
- [Ducky and Bunny — Pixar Wiki](https://pixar.fandom.com/wiki/Bunny)
- [Bunniiies: Uncensored Rabbit (App Store)](https://apps.apple.com/us/app/bunniiies-uncensored-rabbit/id1545788303) *(cited as a search-surface contamination example, not a recommendation)*

---

*Prepared as desk research on 2026-09-19. Not legal advice. Trademark data is from the TMview aggregator, which mirrors national and regional registers; confirm any individual record at the issuing office before relying on it. No registration numbers, serial numbers or filing dates in this document were invented — every date and owner name was retrieved from TMview on the stated date, and every gap is labelled as a gap.*
