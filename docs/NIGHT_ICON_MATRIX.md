# Little Days icon completeness matrix

Audited at `7b42c6e` plus the visual-completeness patch. `PASS` means the icon is present at every shipped location, resolves to a real asset, and follows the shared picture/glyph rule. No missing texture reference was found.

| Icon | Status | Visible locations / implementation |
|---|---|---|
| Home | PASS | House, feeding, classroom, pause and break cards; shared pink-roof house picture |
| Back | PASS | Activity picker, feeding, Dress Up, sticker book and summary; shared `arrow_left.svg` |
| Close | PASS | Parent settings; `close.svg` |
| Done | PASS | Settings footer and Dress Up selection; `done.svg` |
| Reset | PASS | Settings reset-progress row; `reset.svg` |
| Music | PASS | Settings music row; shared glyph |
| Voice | PASS | Settings voice-volume row; shared glyph |
| Language | PASS | Helper-language section; shared glyph |
| Mic / Speak | PASS | Baby Room, house HUD, classroom and voice practice; `mic.svg` plus classroom state ring |
| Next | PASS | Baby Room, house HUD and session summary; `next.svg` |
| Stars / Reward | PASS | Counters, picker ratings, tutor reward, sticker book and summary; shared star/rating component |
| Stickers | PASS | Baby Room and sticker book; shared treasure-chest glyph and cohesive sticker set |
| Parents / Settings | PASS | Menu uses glossy parents picture; in-game adult entry intentionally uses the quieter settings glyph |
| Play | PASS | Menu uses glossy destination art; Continue/Replay use the functional play glyph |
| Free Play | PASS | Menu glossy toys picture |
| Dress Up | PASS | Menu glossy dress picture; selected item uses Done |
| Classroom | PASS | Menu glossy learning-book picture; classroom controls use the functional tier |
| Feeding | PASS | Picker/care overlay use the accepted bottle render through `activity_art.gd` |
| Bath | PASS | Picker/care overlay use the shared care illustration |
| Bedtime | PASS | Picker/care overlay use the shared care illustration |
| Tidy-up | PASS | Picker/care overlay use the shared care illustration |
| Replay / Retry | PASS | Session summary reuses Play; speech retry uses the mic state component |

Low-severity exception: break/exit confirmations keep their secondary actions text-only. This is intentional: the copy is unambiguous, the controls retain large targets, and adding decorative glyphs would crowd the smallest dialog. Unknown activity kinds have a drawn fallback, but no shipped route reaches it. There are no `MISSING` or `PLACEHOLDER` shipped entries.
