# Typography QA — English and Thai

The shared hierarchy is Display 48, Section 32, Body 28, Helper 22, Button 28 and Reward 32. Main-menu branding and large reward numerals are deliberate display exceptions.

| Area | English | Thai / multilingual | Result |
|---|---|---|---|
| Main menu / picker | Stable captions, centred wrapping, consistent card labels | Destination names remain English by product design | PASS |
| House, feeding and care overlays | Smart wrap; helper line separated from the English learning phrase | Explicit `HelperFont` fallback and RTL direction support | PASS |
| Classroom | State, prompt and control roles are consistent | **Fixed:** banner partial transcripts and Aliz subtitle now explicitly use `HelperFont`; smart wrapping remains enabled | PASS |
| Parent gate / settings | Adult-density 20–32 px type is scrollable; footer remains fixed | Selector and privacy/helper copy explicitly use fallback fonts | PASS |
| Dress Up | Category and item labels share roles and selected emphasis | Short labels; no observed clipping | PASS |
| Reward / sticker book | Larger celebratory scale is intentional, not body-text drift | English-only reward copy | PASS with intentional exception |
| Legacy Baby Room / break cards | Several historical numeric constants remain | No clipped shipped copy observed | PASS; consolidate aliases later |

No custom font was added. This avoids a Thai coverage and licensing regression. The remaining hardcoded sizes in Baby Room, sticker book, session summary and adult settings are visually intentional or legacy maintainability debt; changing them without new device screenshots would be churn rather than a visible fix.
