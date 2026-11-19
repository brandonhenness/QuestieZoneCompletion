# Questie Zone Completion

**See your zone's quest progress without navigating Questie's Journey menu.**

A compact companion addon for **World of Warcraft: Forever**, using Questie's existing zone groups and eligibility rules.

**Status:** Preparing the initial beta release. The [CurseForge project](https://www.curseforge.com/wow/addons/questie-zone-completion) has been created and awaits moderator approval and its first confirmed upload. Initial in-game use has been reported successful; broader compatibility testing remains in progress. See the [validation record](docs/testing.md).

## Features

- Current-zone counts, percentage and separate completed, in-progress, available and missing-requirement segments.
- Automatic updates when zones, quests or eligibility change, with selectable **Available quests** and **Total zone** progress.
- Questie tracker styling and attached placement by default; Ctrl-drag moves the tracker and widget together.
- A question-mark settings button, collapsible header and direct access to Journey's **Quests by Zone** tab.
- Per-character controls for placement, scale, opacity, visibility and hide-when-complete in Blizzard's **Options > AddOns** menu.

## Requirements and installation

Requires **Forever interface `16001`**, [Questie](https://www.curseforge.com/wow/addons/questie), and [QuestieDB](https://www.curseforge.com/wow/addons/questiedb) supporting contract 4. Install compatible Forever builds of both dependencies separately. See [integration details](docs/questie-integration.md) for inspected versions and internal interface requirements.

1. Install compatible Forever builds of both dependencies.
2. Download a validated ZIP from [GitHub Releases](https://github.com/brandonhenness/QuestieZoneCompletion/releases) when available, or build from source below. The [CurseForge listing](https://www.curseforge.com/wow/addons/questie-zone-completion) is awaiting approval and its first file.
3. Extract so the manifest is at `_forever_/Interface/AddOns/QuestieZoneCompletion/QuestieZoneCompletion.toc`.
4. Restart the client and enable the addon at character selection.

## Usage

New characters start **attached to Questie's tracker**, using **Available quests** progress. Hold **Ctrl** and drag to reposition the group, or turn attachment off for independent placement. If Questie's tracker is unavailable, the widget uses its saved standalone position.

Click the **question mark** or use `/qzc config` to open settings. Click **Zone Completion** to minimize/expand the display. Click the zone, counts or bar to open Journey's **Quests by Zone** tab. Navigation and movement respect combat restrictions; the selected Journey category/zone is preserved.

Hover for the color legend and counts. Narrow trackers omit the word “completed” to keep the count on one line. The default background follows Questie's transparent style; opacity applies when its tracker background is enabled.

| Progress basis | Denominator | Behavior |
| --- | --- | --- |
| **Available quests** (default) | Completed + in progress + available | Can reach 100% before higher-level or other requirements are met; unlocking more quests can lower the percentage. |
| **Total zone** | Completed + in progress + available + missing requirements | Shows progress through all eligible Questie zone quests; unlocking requirements transfers quests between segments. |

Only confirmed completions contribute to the percentage. Questie's **Available** category already includes in-progress quests; they are split into separate segments without being counted twice. Reset restores attached placement and Available quests mode; updates preserve explicit saved choices.

| Command | Action |
| --- | --- |
| `/qzc` | Toggle visibility |
| `/qzc show` / `hide` | Show or hide the widget |
| `/qzc config` | Open Blizzard's AddOns settings category |
| `/qzc scale 0.6–1.8` | Set scale, e.g. `/qzc scale 1.2` |
| `/qzc opacity 0–1` | Set background opacity |
| `/qzc mode total` / `available` | Select the progress basis |
| `/qzc attach on` / `off` | Attach to Questie's tracker or use standalone positioning |
| `/qzc complete on` / `off` | Hide or show fully completed lists in the selected mode |
| `/qzc refresh` / `open` | Refresh progress or open Journey |
| `/qzc reset` | Restore display defaults |

Display preferences are stored per character in **`QuestieZoneCompletionDB`** (`SavedVariablesPerCharacter`), including minimized state and standalone position. No completion history or account-wide settings are stored. Reset affects this addon's preferences only.

## Count scope and limitations

Counts use unique, non-repeatable quests in Journey's eligible groups. Available mode excludes unmet requirements; both modes exclude unobtainable quests and repeatable/daily/weekly/monthly quests. Breadcrumb and hidden overlays count once. Completed quests require the game's **character** completion flag; in-progress quests come from the character's quest log.

Journey credits some exclusive alternatives as completed. This addon excludes unconfirmed alternatives, so its counts can differ intentionally. Zone membership follows Journey's assignments rather than every quest physically touching the area. Database omissions and incomplete server history remain upstream limitations. Missing or incompatible data shows an incomplete/unavailable state.

Both dependencies are required for progress; optional TOC load ordering lets the addon report a missing dependency. Reload after database updates. Current-zone automatic selection inside Journey is not supported. See [integration details](docs/questie-integration.md) and the [manual test matrix](docs/testing.md).

## Development and releases

Requires Python 3.10+ and Lua 5.1; CI uses Python 3.14. From the repository root:

```sh
lua tests/run.lua
python -m unittest discover -s tests -p 'test_*.py' -v
python tools/package.py --output dist/QuestieZoneCompletion-dev-forever.zip
```

CI checks Lua syntax/behavior, manifest safety and ZIP contents. Only version tags can publish, after validation and explicit repository setup. GitHub and CurseForge receive the same validated ZIP; upload receipts protect reruns. See [release setup and checklist](docs/releasing.md).

Report issues at [GitHub Issues](https://github.com/brandonhenness/QuestieZoneCompletion/issues), including client/addon versions, zone, progress basis and reproducible steps. Contributions are welcome.

## License

[GNU GPL v3](LICENSE). Questie and QuestieDB remain separate projects with their own licenses and are not modified or redistributed.
