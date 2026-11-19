# Implementation plan

1. Inspect Questie, QuestieDB and the Forever UI source. Record the exact revisions,
   integration surfaces and count differences in `questie-integration.md`.
2. Isolate all Questie calls in an adapter. Reuse Journey's initialized zone index
   and classification; never build a second database or directly write Questie's settings.
3. Count unique non-repeatable quests in Journey's available, completed and missing
   requirement groups. Confirm completion against the character's game flags and
   split accepted quests with `C_QuestLog.IsOnQuest`. Default new/reset settings
   to available-quests progress, omitting unmet requirements; offer total-zone
   progress as an alternative and preserve explicitly saved mode choices.
   Keep completed, in-progress, available and missing-requirement segments disjoint.
   Reject genuinely malformed or unclassified data without blocking valid progress
   behind a separate data-scope setting.
4. Build a compact segmented widget that uses Questie's fonts, content width and
   backdrop preferences, with character-specific native Blizzard AddOns settings.
   Put the four status counts in a short hover tooltip instead of an on-screen
   legend. Measure count text after resizing, omit "completed" when it does not
   fit, and prevent wrapping. Add a settings question mark and a separate title
   that minimizes the details without hiding the header. Persist that state.
   Open Journey's verified `zone` tab from the progress area; do not manipulate
   its private dropdowns or assume a current-zone deep link.
   Default new/reset settings to attachment above Questie's tracker while preserving
   explicit placement preferences. Use Ctrl-drag for standalone movement. While attached,
   delegate Ctrl-drag to Questie's existing start/stop handlers so the whole group
   moves and Questie saves its own position. Never replace Questie's scripts or
   directly write its SavedVariables. Use public Questie callbacks, game events
   and coalesced timers, with bounded startup retries.
5. Exercise counting, dependency failures, callback registration, event timing and
   persistence with a Lua harness. Record all unperformed in-game tests honestly.
6. Validate manifests and reproducible packages in CI. Gate tag-only publishing;
   verify the live Forever CurseForge mapping and preserve upload receipts.
7. Keep the existing GPL-3.0 license, update public documentation and record release
   prerequisites. In-game verification and external publishing require their actual
   environments; neither can be inferred from automated tests.

The user reported that the installed widget works and supplied a screenshot of the
segmented bar attached above Questie's tracker. That feedback does not establish
agent-run in-game validation of the matching typography, native Settings, combined
Ctrl-drag movement, compact header, resizing or persistence. Those client checks
remain pending in `testing.md`.
