# Validation and manual test matrix

## Automated checks

Run from the repository root with Lua 5.1 and Python 3.10+:

```sh
lua tests/run.lua
python -m unittest discover -s tests -p 'test_*.py' -v
python tools/package.py --output dist/QuestieZoneCompletion-dev-forever.zip
```

CI additionally compiles every project Lua file with `luac5.1 -p`. The Lua harness
uses isolated WoW/Questie fixtures; it tests real project modules, not a game client.
Python tests use temporary packages and fake API transports and never publish.

Local results for `0.2.0-beta.3` on 2026-11-18: **86 Lua cases and 16 Python cases passed**, using
Lua 5.1.5 from the ignored QuestieDB research checkout and Python 3.14. The
interpreter is not bundled with this project. Manifest validation and the beta
ZIP build passed. The beta artifact contains exactly seven runtime/license files
under `QuestieZoneCompletion/`.

During the initial implementation, the pinned BigWigs script was also run against
an isolated temporary repository and beta tag, with publishing and ZIP creation disabled. Its real Forever staging
was archived locally with Python (no native ZIP executable was available), then
normalized and compared byte-for-byte with the local beta build. This passed;
the GitHub-hosted workflow and the services themselves have not been exercised.

Coverage includes confirmed history versus quest-log readiness, exclusive alternatives,
duplicate breadcrumb/hidden entries, reset quests, unknown data, empty zones, missing
dependencies, changed API shapes, saved-settings migration, native Settings registration,
disjoint colored segments, both denominator modes, Ctrl-drag, tracker attachment,
combined movement and native position-saving delegation, modifier-release cleanup,
Questie typography/backdrop styling, measured single-line count fitting, concise
tooltip budgets, header/settings click routing, saved minimization, zone-tab
navigation, layout-only refreshes, UI visibility, combat
guards, timer coalescing, immutable artifacts, exact version mapping, failed
uploads and reruns. It cannot establish client loading, visual layout or server timing.

## Current manual status

**2026-11-18: no agent-performed in-game tests.** Source inspection verified interface
`16001` in current Questie/QuestieDB manifests and the installed Questie manifest.
A local Forever process was discovered, but computer-use could not capture/target
its game window; recovery found no unique targetable window. At the user's subsequent
request, the validated `0.1.0-beta.1` build was installed under the local Forever
`Interface/AddOns/QuestieZoneCompletion` directory. All seven installed files were
verified against the package. Installed Questie `12.11.0` and QuestieDB `1.1.3`
expose the required source interfaces. The user subsequently reported that the
original widget loads and shows progress after enabling the old totals option.
That is limited user-reported evidence for the original build, not verification
of the redesigned bar, native settings, Shift-drag or tracker attachment. No quest
or character state was changed by the agent.

The `0.2.0-beta.1` redesign was then installed over that copy. All seven existing
addon files were backed up under the workspace's ignored `.research/install-backups/`
directory and the replacement files were verified byte-for-byte against the
validated package. SavedVariables were not edited; schema migration runs when the
client next loads the addon. This installation does not establish in-game behavior.

The user later supplied a screenshot showing the segmented Barrens widget above
Questie's tracker: 15/50 completed (30%), 15 completed, 22 in progress, 13 available
and 50 later. This establishes the displayed result in that supplied snapshot; it
does not verify the new `0.2.0-beta.2` matching appearance or combined Ctrl-drag.

`0.2.0-beta.2` was installed with the same seven-file backup and byte-verification
procedure. Its current archive SHA-256 is
`73b19bd06befa92bcd8d11519cc0da701226a2827595ba09a5cd27b3795d2c19`.
The agent did not reload the game, exercise movement or edit either addon's
SavedVariables files. Questie's own position-saving handler runs when the user
Ctrl-drags the attached widget after reload.

The latest header, minimized state and zone-tab navigation are validated by
automated fixtures only. They still require the client checks below.

`0.2.0-beta.3` was installed using the same seven-file backup and verification
procedure. Its archive SHA-256 is
`fffb8d6ac7980dba0e580a29d01cf46ba8789597fa4519c0777cd986a237eb01`.
The game was not reloaded by the agent; the new header and saved minimized state
take effect on the user's next addon load.

`0.2.0-beta.4` corrects the header alignment using the installed Questie source:
the icon starts 6px from the header edge and the title is anchored 2px to its right,
with natural font height. The existing 86 Lua cases passed; the seven installed
files were backed up and verified against the new package. Visual alignment after
reload remains a client check. Archive SHA-256:
`d710bfc0ca27488b8dd6c9a88e94e189bb2e5714f9dd4011389ec33319432378`.

`0.2.0-beta.5` sets new/reset preferences to attached placement and Available quests
mode while preserving explicit saved choices. All 86 existing Lua cases passed,
including the updated default/reset and saved-preference checks. The seven addon
files were backed up and verified after installation; SavedVariables were not edited.
Archive SHA-256:
`d8ba2c733ebeaf2fe56bd1bb3d51cfa386da4bb58cb887cffd7477e8f0c03691`.

All rows below are **pending**. Before publishing, record the tag/commit, client build
and `select(4, GetBuildInfo())`, Questie/QuestieDB versions, character faction/class/race,
zone/area ID and relevant quest IDs. Capture Lua errors and compare Journey categories
with `C_QuestLog.IsQuestFlaggedCompleted(id)`, which is a character completion check.

| Scenario | Procedure and expected result | Status |
| --- | --- | --- |
| Fresh character | Install and restart; verify attachment and Available quests mode are the defaults. Compare unique primary-category IDs and progress segments; verify Total zone mode remains selectable. | Pending |
| Progressed character | Verify previously turned-in quests match character flags. An objective-complete active quest must not increase completed count. | Pending |
| Two zones/subzones | Travel between two outdoor zones, a subzone and a dungeon; verify title, Journey grouping and refresh without reload. Unmapped zones remain incomplete. | Pending |
| Accept/abandon/turn in | Accept, complete objectives, abandon, retake and turn in a quest; verify flags and denominator settle. Include Forever's delayed/missing turn-in event behavior. | Pending |
| Repeatables/resets | Inspect repeatable and daily/weekly/monthly quests; exclude them even when marked completed. | Pending |
| Exclusive branches | Compare Journey's virtual completion against actual character flags. Record IDs and the intentional difference in numerator and denominator. | Pending |
| Breadcrumbs/chains | Inspect breadcrumb/hidden duplicates, unmet prerequisites and future-level steps. Overlays count once; unknown classifications suppress percentage. | Pending |
| Faction/class/race | Compare appropriate quests across characters, including a Forever race; reuse Journey filtering without adding incompatible quests. | Pending |
| Events/professions/reputation | Change eligibility where available; compare Journey after event refresh. Seasonal quests retain Journey's separate groups. | Pending |
| Progress basis | Compare total-zone and available modes. Available already includes quests in progress. Unlock a requirement: total stays stable while available denominator grows. | Pending |
| Move/settings | Verify ordinary/Shift dragging does nothing and Ctrl-drag moves; no lock control or Move label. Use native AddOns settings to adjust scale, opacity, visibility and hide-complete. Verify clamping at common UI scales. | Pending |
| Tracker attachment | Ctrl-drag the attached widget: both move, attachment stays enabled, standalone position stays unchanged, and Questie saves its new location. Release Ctrl before the mouse, hide mid-drag and enter combat mid-drag; no stuck movement. Detach through settings, then reload/relog to check both positions. | Pending |
| Matching style | Compare transparent/default appearance, fonts, outlines, colors and attached width with Questie. Change tracker font, width and background settings while idle; layout refreshes without quest scans. Check hover fading and common UI scales, including minimized/initially narrow tracker states. | Pending |
| Narrow display and tooltip | Narrow Questie and change body font size. “Completed” disappears when needed; count and percent stay on one line above the bar. No legend appears on screen. Hover shows the four counts and a short mode/click hint, without long explanatory paragraphs. | Pending |
| Header controls | Question mark opens this addon's native settings. Zone Completion title minimizes/expands only this section; state survives reload/relog. Ctrl-drag the header or question mark while attached: move the group without an accidental collapse or settings click. | Pending |
| Reload/relog/reset | Save changes, reload and relog; confirm character-specific persistence. Reset restores defaults without touching Questie data. | Pending |
| Navigation/combat | Click zone/counts/bar and use `/qzc open` with Journey hidden, on My Journey and already on Quests by Zone. Always select Quests by Zone without closing it; retain its selected category/zone. In combat show a concise message; retry after combat. | Pending |
| Missing/outdated dependency | Disable Questie, QuestieDB and incompatible builds in turn; verify useful warning and no gameplay Lua errors. Restore and reload. | Pending |
| Unknown database entry | Test a missing/malformed entry and unsupported classification on a development build; no exact percentage or false 100%. | Pending |
| Database update | Update Questie/QuestieDB, reload, recheck zone/parent index and category shape. No cached progress survives independently. | Pending |
| Idle/performance | Observe addon CPU/memory over 10 idle minutes and a questing session. No periodic database scans, growing timer backlog or repeated chat errors. Record measurements. | Pending |
| Packaging/install | Install the generated ZIP on a clean AddOns tree; confirm one top-level folder, standard TOC loading and no development/third-party files. | Pending |

## Acceptance boundaries

Automated passes are reproducible evidence for counting, defensive behavior and release
tooling only. Acceptance criteria involving loading, actual event timing, appearance,
relogging, Questie navigation and CPU/memory in Forever remain outstanding until the
matrix is executed. Keep publishing gates disabled until those results are reviewed.
