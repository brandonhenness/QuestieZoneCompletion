# Changelog

## 0.2.0-beta.5

Initial public beta for **World of Warcraft: Forever**. Requires compatible **Questie** and **QuestieDB** installations.

- Show current-zone counts, completion percentage and a segmented progress bar using Questie's zone groups and eligibility rules.
- Separate confirmed completions, in-progress quests, available quests and missing requirements without double counting. Exclude repeatable and unobtainable quests; count breadcrumb/hidden overlays once.
- Default to **Available quests** progress attached above Questie's tracker, with **Total zone** progress and independent placement available in settings.
- Match Questie's tracker fonts, colors, width and background preferences. Ctrl-drag moves the attached group through Questie's own movement and position-saving handlers.
- Open native AddOns settings from the question mark, minimize from the header, and open Journey's **Quests by Zone** tab from the progress area.
- Save display preferences per character, keep narrow count text on one line, and show the legend in a concise hover tooltip.
- Add Lua behavior tests, strict manifest/ZIP validation, reproducible packaging and tag-driven GitHub/CurseForge publishing with upload receipts for safe reruns.

Validation: **86 Lua checks and 16 release-tool checks passed locally**. Initial operation in Forever has been reported successful. The full manual compatibility matrix remains outstanding. Database omissions, incomplete server history and unconfirmed exclusive alternatives remain documented limitations.
