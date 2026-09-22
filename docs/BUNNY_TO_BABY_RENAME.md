# Bunny to Baby display rename

## Decision

The character is a human baby. Player-facing copy now calls the character **Baby**, never Bunny. Internal identifiers were deliberately left stable where changing them could break saves, routes, content references, audio lookup, or test fixtures.

## Updated player-facing surfaces

- Main menu and activity picker: `Play with Baby`
- Care, feeding, kitchen, bedtime, onboarding, rewards, classroom fallback and parent voice labels
- Chapter, mission, task and voice-manifest display text
- English, Thai, Japanese, Chinese, Hindi and Arabic localization values
- Thai embedded care hints

Localized display forms are Baby, เบบี๋, 赤ちゃん, 宝宝, बेबी and الطفل. Localization key names remain stable.

## Remaining intentional internal references

- Scene/node compatibility: `Bunny`, `BunnyVoiceSlider`, related node lookups
- Save/audio compatibility: `bunnyVoiceVolume`, voice character `bunny`, `bunny_*` line IDs and folders, `hungryBunny`
- Content/API compatibility: task IDs such as `bunnyIsHungry`, `carryMilkToBunny`, `feedBunnyCare`, `cuddleBunny`, and mission references
- Recognition compatibility: legacy accepted command `bunny` remains an alias; the taught/displayed word is `baby`
- Resource paths, test fixture IDs, filenames, historical screenshots, tools, engineering comments and historical documentation

No internal identifier was renamed in this pass. No save migration is required.

## Classification

- User-facing: updated in shipped content, UI scripts/scenes and localized helper values.
- Internal compatibility: retained as listed above.
- Test-only: user-facing assertions updated; internal harness names and diagnostics retained.
- Obsolete: no safe obsolete runtime occurrence was identified for removal.

## Regression coverage

`test_baby_display_name.gd` scans shipped JSON display values and the UI sources that own visible labels. It fails if Bunny reappears, while explicitly allowing documented compatibility fields. Localization, activity picker and main-menu route tests cover fit and navigation.
