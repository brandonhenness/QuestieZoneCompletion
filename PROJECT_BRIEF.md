# Codex Project Brief — Questie Zone Completion

## Role and objective

Act as a senior World of Warcraft addon engineer and open-source maintainer. Build **Questie Zone Completion** (`QuestieZoneCompletion`): a lightweight, polished companion addon for **WoW Forever** that shows the player's current zone quest-completion progress on screen using Questie's existing quest and completion data.

The defining user experience is **zone progress at a glance, with no need to navigate Questie's Journey menu**. Keep the addon focused; do not reproduce a general quest helper, route planner, or collectible tracker.

## Non-negotiable engineering principles

1. **Integrate; do not fork.** Require Questie and its necessary QuestieDB dependency. Never modify or redistribute Questie/QuestieDB files. Reference existing data and functionality wherever supported.
2. **Investigate before implementing.** Inspect the current Questie and QuestieDB repositories, particularly the Journey / Quests by Zone logic, eligibility filtering, completion-state logic, and available integration surfaces. Document the verified functions, events, and data structures in `docs/questie-integration.md`. Do not invent stable public APIs or assume internal APIs will remain stable.
3. **Accuracy beats a fabricated percentage.** Define the numerator and denominator precisely. Reuse Questie's zone membership, faction/class/race/level/prerequisite and repeatable-quest rules when possible. Identify unavailable or unknown quests. If a reliable total cannot be determined, show an honest `—` / "Data incomplete" state rather than a deceptively precise count. Never count currently active quests as completed unless Questie/game state confirms completion.
4. **Forever-first.** Target the current WoW Forever client, currently `Interface: 16001` (verify before shipping). Do not assume Classic Era APIs are interchangeable with Forever's modern APIs. Use supported addon APIs; avoid protected or combat-restricted interactions.
5. **Independent, maintainable project.** Keep the addon modular, versioned, testable where practical, and safe when Questie changes or is missing.

## MVP experience

Implement a small, draggable, resizable-in-settings (or scale-adjustable) overlay with:

- Current zone name, `completed / eligible known quests`, percent, and a progress bar.
- Automatic updates when the player changes zones or quest completion state changes.
- Lightweight event-driven refreshes, with bounded throttling/debouncing where appropriate; no perpetual frame-by-frame database scans.
- Click to open the relevant Questie zone list **if a reliable integration path is verified**; otherwise open Questie's Journey screen and clearly document the limitation.
- A concise hover tooltip explaining counts, excluded/unknown quests, and data completeness.
- Configurable widget scale, position, visibility, lock/unlock, background opacity, and optional hide-when-complete.
- Saved settings across sessions. Prefer per-character positioning/progress-display preferences, with an explicit documented SavedVariables model.
- Slash commands such as `/qzc`, `/qzc show`, `/qzc hide`, `/qzc lock`, `/qzc reset`, and `/qzc config` (adapt to verified implementation).
- Helpful, non-spammy message when Questie is missing/outdated. No Lua errors during normal gameplay.

### Count semantics and edge cases

Define "zone completion" as the count of **eligible, non-repeatable, currently known quests assigned to a zone**, based on data Questie can support for the player. Document policies for mutually exclusive quests, breadcrumb quests, quest chains, class/faction/race restrictions, dailies, repeatables, dungeon quests, world events, quests that start in one zone and finish in another, newly added Forever quests, and characters with incomplete historical data. Avoid double counting. If any policy is unverifiable, mark it as an open limitation, not an assumed fact.

Consider making the denominator opt-in or conservative if Questie's available quest data does not expose an authoritative, stable eligible-quest set. Present numbers with an explanation of their scope. Where possible, match the counts a player sees in Questie's **Quests by Zone** interface, and explicitly test/report any discrepancy.

## User interface

- Visually blend with Warcraft/Questie while remaining readable at common UI scales.
- Keep the default compact: zone title, number, percent, progress bar.
- No extra minimap button by default; optional LibDataBroker/LibDBIcon integration only if its benefit justifies the dependency.
- Sensible default placement that avoids the default quest tracker; draggable with a visible unlock state.
- Accessible contrast and straightforward settings. Do not block gameplay or obscure critical UI elements.
- Use Blizzard UI primitives and established libraries only when justified; avoid excessive dependencies.

## Architecture and deliverables

Propose a clean structure, adjusting to the repository and verified implementation:

```text
QuestieZoneCompletion/
  QuestieZoneCompletion_Forever.toc  # or verified valid TOC naming convention
  Core.lua
  QuestieAdapter.lua
  ZoneProgress.lua
  UI.lua
  Config.lua
  Locale/enUS.lua                # optional if useful
.github/workflows/ci.yml
.github/workflows/release.yml
.pkgmeta
.gitignore
LICENSE
README.md
CHANGELOG.md
docs/questie-integration.md
docs/releasing.md
```

Implement an adapter boundary separating Questie's internal interfaces from counting and UI logic. Allow clean failure/degradation if data is temporarily unavailable. Do not hardcode a Questie function name without checking the upstream source. If Questie offers callbacks, use those; otherwise use documented game events with minimal polling. Avoid altering Questie's SavedVariables and avoid unsafe hooks.

## Quality assurance and acceptance criteria

1. Loads in WoW Forever with current Questie + QuestieDB and shows a clear dependency warning if unavailable.
2. Displays the current zone's verified completion state, or an explicit incomplete-data state; never silently claims completeness.
3. Refreshes after quest acceptance/completion/turn-in and zone transitions without a UI reload when the API supports it.
4. Widget movement, scale, visibility and settings persist across logout/login; reset works.
5. Opening Questie from the widget works as documented and does not break Questie's own UI.
6. No excessive CPU usage, memory growth, repetitive errors, or noisy chat output while idle.
7. Manual test matrix includes new and progressed characters, quests across two zones, repeatables, exclusive branches, faction/class-specific quests, reload/relog, missing Questie, and database updates.
8. Automated checks lint or validate Lua/TOC/package contents where feasible; publish no release when validation fails.
9. Produce a concise, polished README with install instructions, features, commands, requirements, known data limitations, compatibility, and links/placeholders for repository and CurseForge.
10. Document verified Questie integration details, limitations, and release setup so another maintainer can continue the project.

## GitHub → CurseForge release automation

Set up **tag-driven** automated releases, never publishing on ordinary pushes or pull requests:

- A versioned tag such as `v0.1.0` triggers GitHub Actions.
- CI validates source, manifest/TOC, dependencies, and distributable ZIP layout before release.
- The release workflow packages only files needed by WoW, with the correct top-level addon directory, excluding development material.
- Publish the ZIP to a GitHub Release with generated or curated changelog.
- Upload the exact release artifact to CurseForge using the verified WoW Forever game-version identifier, correct release channel (alpha/beta/release), and the CurseForge project ID.
- Prefer the maintained **BigWigsMods/packager** GitHub Action when it correctly recognizes WoW Forever. If it does not, implement a carefully documented, minimal authenticated CurseForge Upload API step as a fallback. **Verify support and IDs rather than guessing.**
- Use GitHub Actions secrets (e.g. `CF_API_TOKEN`, according to the selected tooling's actual expected variable name); never commit tokens. Use `GITHUB_TOKEN` with least-privilege `contents: write` for GitHub releases.
- Prevent duplicate publishing, support reruns safely, and clearly surface upload failures. No claim of successful CurseForge release unless the API confirms it.
- Document one-time setup: create/approve CurseForge addon project; obtain project ID and upload API token; configure secrets; verify the Forever version mapping; create first tag; inspect published release.
- Use semantic versioning and a documented release checklist. Consider tag prereleases as alpha/beta deliberately, not by accident.

Reference documentation:
- https://github.com/BigWigsMods/packager
- https://support.curseforge.com/support/solutions/articles/9000197321-curseforge-upload-api
- https://github.com/Questie/Questie
- https://github.com/Questie/QuestieDB

## Scope boundaries

Do not implement auto-accept/auto-turn-in, quest routing, questgiver map pins, item collection tracking, or a second quest database for the MVP. Do not promise 100% zone coverage when QuestieDB may be incomplete. Avoid shipping a third-party addon bundle.

## Execution order

1. Inspect upstream source and document integration decisions and risks.
2. Scaffold the addon and write a short technical plan.
3. Implement the Questie adapter and independently testable counting logic.
4. Implement the widget and settings.
5. Validate in WoW Forever and record reproducible test results.
6. Add CI and tag-driven packaging/publishing (with publishing disabled until credentials/project ID exist).
7. Finalize README, license, changelog, and release instructions.

Work autonomously, making sensible design decisions; ask only when a genuinely blocking decision or credential is required. Never invent test results or claim in-game validation without running the game. If in-game access is unavailable, explicitly document the outstanding manual tests. Deliver working source files and summarize completed functionality, known limitations, and exact steps required for the first release.
