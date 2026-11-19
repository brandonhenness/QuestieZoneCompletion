# Questie integration

Inspected on 2026-11-18. This is source inspection and an integration policy, not evidence of an agent-run Forever test. The user reported the installed widget working and supplied a screenshot of its segmented bar above Questie's tracker. The new matching appearance and combined Ctrl-drag behavior still require client verification. Questie and QuestieDB files are installed separately and are never bundled or modified.

## Verified upstream revisions

| Source | Inspected revision | Relevant version |
| --- | --- | --- |
| [Questie](https://github.com/Questie/Questie/tree/81dd55a3fafc5eac262eff618340b2bb2e98591f) | `81dd55a3fafc5eac262eff618340b2bb2e98591f` | Forever TOC: `12.11.0`, interface `16001` |
| [QuestieDB](https://github.com/Questie/QuestieDB/tree/4f628e8328ed8923ffba169c8b432996e0a7a326) | `4f628e8328ed8923ffba169c8b432996e0a7a326` | Source TOC: `1.1.3`, contract `4`, supports interface `16001` |
| [Blizzard Forever UI mirror](https://github.com/Gethe/wow-ui-source/tree/3d8abb1da73acd38e412e24fb3f99454a6392346) | `3d8abb1da73acd38e412e24fb3f99454a6392346` | `forever` branch, including `Camelot` UI files |

The Forever target is corroborated by [Questie's manifest](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Questie_Forever.toc#L1) and [QuestieDB's flavor configuration](https://github.com/Questie/QuestieDB/blob/4f628e8328ed8923ffba169c8b432996e0a7a326/src/config.lua#L65). This project uses the standard unsuffixed `QuestieZoneCompletion.toc` with interface `16001`; only Forever is targeted. This also allows the inspected BigWigs packager to parse the manifest. Recheck `select(4, GetBuildInfo())` and manifest loading in the actual client before release.

## Public interfaces and internal boundaries

Questie's [public API documentation](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Public/README.md) and these functions are verified:

- [`Questie.API.RegisterOnReady(callback)`](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Public/RegisterOnReady.lua#L10) invokes immediately if `Questie.API.isReady` is already true, otherwise after successful initialization. The initialization code sets readiness only after its stages finish.
- [`Questie.API.RegisterForQuestUpdates(callback)`](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Public/RegisterForQuestUpdates.lua#L10) receives `(questId, objectiveIndexOrNil, triggerReason)`. One update can deliver multiple objective callbacks. There is no unregister function in this interface; register once per session and coalesce refresh requests.

There is no verified public API returning the Journey denominator or opening a specific zone. `QuestieAdapter.lua` alone accesses these **internal, changeable** modules: `QuestieJourney`, `QuestieDB`, `ZoneDB`, `QuestiePlayer`, `QuestieTracker`, `TrackerBaseFrame`, `TrackerHeaderFrame`, `TrackerLayout`, and `TrackerFadeTicker`. It checks the existing `QuestieLoader._modules` registry before importing because the inspected loader otherwise creates absent modules; optional typography/layout modules are read from that existing registry. Capability/shape checks and protected calls turn incompatible versions or initialization failures into unavailable/incomplete states. A version string alone is not a compatibility guarantee.

QuestieDB separately provides a [public, versioned data API](https://github.com/Questie/QuestieDB/blob/4f628e8328ed8923ffba169c8b432996e0a7a326/docs/api.md): `LibQuestieDB.RequireContract(required)`, `LibQuestieDB.Quest` (also global `QuestDB`), named field getters, `Get`, `GetAll`, `Exists`, and `GetAllIds`. `RequireContract` checks the inclusive supported range, rather than only a minimum current version. Basic entity reads require contract 1; race/faction masks require 3; active class keys require 4. This addon requires contract 4, matching the inspected Questie integration, and lets Questie's own runtime layer interpret eligibility rather than duplicating those rules or enumerating the whole database again.

## How Journey builds Quests by Zone

[`QuestieJourney:Initialize()`](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Modules/Journey/QuestieJourney.lua#L78) builds `QuestieJourney.zoneMap` once through [`JourneyData.Build(true)`](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Modules/Journey/JourneyData.lua#L16). Its shape is:

```lua
zoneMap[areaIdOrNegativeQuestSort][questId] = true
```

The backing [`ZoneDB.GetZonesWithQuests`](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Database/Zones/zoneDB.lua#L254) traverses Questie's `QuestPointers`, filters its blacklist and race/class policy, then groups positive `zoneOrSort` values under their parent area when present. Recognized negative quest sorts remain separate. It splits seasonal groups, then applies Journey-specific redirects. The inspected Journey redirect moves Night Elf quests into Teldrassil without changing database fields.

For categories lacking a recognized area/sort, upstream attempts NPC/object starter/finisher spawn fallback. The inspected fallback functions at `zoneDB.lua:359` and `:380` use starter/finisher table keys as group entries; they do not establish that every resulting key is a valid quest ID. This addon treats absent quest pointers/names as unknown instead of assuming those entries are countable quests. A coincidentally valid quest ID cannot be distinguished by that check; upstream grouping remains a limitation.

`JourneyData.Build` explicitly warns that each call scans the database and is not cached. This addon reads Journey's existing map and **never calls Build or GetZonesWithQuests**. It treats all upstream tables as read-only.

Current position comes from [`QuestiePlayer:GetCurrentZoneId()`](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Modules/QuestiePlayer.lua#L99), which uses `C_Map.GetBestMapForUnit("player")`, Questie's UI-map/area mappings, a zone-text fallback for continent maps, and an instance fallback. The adapter normalizes a recognized subzone/alternative dungeon area through [`ZoneDB:GetParentZoneId(areaId)`](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Database/Zones/zoneDB.lua#L238), matching Journey's grouping. Unknown/unmapped zones remain incomplete.

## Classification and completion

[`QuestieJourney.private.questsByZone:CategorizeQuests(questSet)`](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Modules/Journey/tabs/QuestsByZone/QuestsByZone.lua#L177) returns category nodes containing `{value = category, children = {{value = questId, ...}, ...}}`:

| Value | Journey category | Addon policy |
| --- | --- | --- |
| `a` | Available, including quests in the log | Split into accepted/in-progress and not-yet-accepted available quests; completion still requires the character completion flag |
| `c` | Completed, including some excluded alternatives | Include confirmed completions; a currently accepted entry is in progress; otherwise exclude as an unconfirmed alternative |
| `p` | Missing Requirement | Include in total-zone mode; exclude from available-mode denominator |
| `r` | Repeatable | Exclude |
| `u` | Unobtainable | Exclude according to Questie's current policy |
| `b` | Breadcrumb overlay | Deduplicate against primary categories; do not add another denominator entry |
| `h` | Manually hidden overlay | Deduplicate; manually hiding a quest is not completion |

Journey computes its denominator as `availableCounter + completedCounter + prequestMissingCounter`. Its `zoneTree.numquests` additionally sums repeatable, breadcrumb, unobtainable and hidden counts and therefore **is not a unique eligible denominator**. This addon derives unique quest IDs from the category tree and never parses localized header labels or uses `numquests`.

Journey calls [`QuestieDB.IsDoableVerbose(questId, false, true, false)`](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Database/QuestieDB.lua#L967), whose third result is a `QuestieDB.DoableStates` value. It checks Questie's historical character set, active quests, blacklist/event policy, race/class, exclusivity, professions, level, breadcrumbs, reputation, prerequisites, parent quests and other conditions. Missing requirements can be recoverable (`p`) or unobtainable (`u`). The adapter does not reimplement this decision tree.

The inspected [`IsDoableVerbose` quest-log check](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Database/QuestieDB.lua#L999) uses `C_QuestLog.IsOnQuest(questId) == true`. Journey categorizes that `QUEST_LOG` reason under **Available Quests** rather than exposing a separate active group. The addon uses the same game API to split accepted quests from that available population. It queries only IDs in the current Journey zone group, so unrelated quests in the character's log do not become zone progress. Child quests exposed through `PARENT_ACTIVE` can remain available without being individually accepted; the game-log check distinguishes them.

[`ActiveQuests.Get`](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Modules/Quest/ActiveQuests.lua#L83) returns a Questie acceptance object or nil. That internal cache can be reset/rebuilt; it is not an additional count and is not needed for the widget's accepted-quest status. The game completion flag takes precedence over accepted status during a state transition. In the pure counting layer, accepted status takes precedence over a stale missing-requirement marker, so segments remain mutually exclusive.

An entry omitted from the tree is unknown unless verified as wrong race, wrong class or automatically blacklisted by this function. For example, upstream currently returns `EXCLUSIVE_BREADCRUMB` without a matching categorization branch; that remains unknown. Errors, invalid shapes, conflicting primary categories, missing pointers/names, or unavailable completion results also prevent an exact percentage.

### Why counts can differ from Journey

Journey places some uncompleted exclusive alternatives in `c`, including when another branch is merely active. Its active-parent handling can also increment the completed counter for a blocked child. Therefore Journey's completed header is not proof that the character turned in every counted quest.

This addon requires **`C_QuestLog.IsQuestFlaggedCompleted(questId) == true`** for the numerator and uses that character API throughout. It never uses account completion, an active quest, objective readiness, or a turn-in dialogue as proof. In particular, [`QuestieDB.IsComplete`](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Database/QuestieDB.lua#L1451) reads active quest-log objective readiness and is unsuitable for historical completion.

Unconfirmed, unaccepted `c` entries are excluded from the denominator instead of credited as completed. A quest still accepted according to `IsOnQuest` remains in progress, even if Questie's historical categorization has not settled. This is an intentional discrepancy from Journey. Agent-run live count comparisons have not been performed; record both headers, character flags, category membership and quest IDs using the [manual test matrix](testing.md).

## Progress modes and segment rules

Progress is displayed by default using Questie's database and the current character's confirmed completion flags. The removed `knownScope` option no longer gates display. The product UI does not add a coverage warning; the upstream data limitations remain documented below.

The eligible population is the unique non-repeatable union of `a`, `c`, and `p`, with repeatable/daily/weekly/monthly quests, unobtainable entries and unconfirmed, unaccepted exclusive alternatives excluded. Each eligible quest belongs to exactly one segment:

| Segment | Meaning |
| --- | --- |
| Completed | Character completion flag is true, whether or not the log still contains the quest |
| In progress | Not completed and `C_QuestLog.IsOnQuest(id)` is true |
| Available | Neither completed nor accepted, with no Journey missing-requirement marker |
| Missing requirements | Not completed or accepted, and Journey classified it as `p` |

The percentage always represents **completed** quests. Accepted quests have a separate colored segment and do not receive completion credit. Settings select the denominator:

- **Total zone quests**: `completed + inProgress + available + missingRequirements`.
- **Currently available quests** (default for new/reset settings): `completed + inProgress + available`. Missing requirements remain available in tooltip details but do not occupy the selected bar.

For the user's Barrens example, Journey's 35 Available includes the 22 accepted quests. The disjoint segments are therefore **15 completed, 22 in progress, 13 available and 50 missing requirements**. Total-zone progress is `15 / 100 = 15%`; available-mode progress is `15 / 50 = 30%`. The eight repeatables, two unobtainable quests and four breadcrumb overlay entries do not add another denominator population. These are fixture calculations from the reported counts, not an agent-run live character comparison.

Available-mode completion can reach 100%, then fall when more quests unlock. Total-zone mode avoids that particular change because those missing-requirement quests were already counted, although changing exclusive branches or upstream assignments can still change the total. Breadcrumbs are introduction quests pointing to a follow-up; they are counted once through their ordinary status. Questie usually makes an uncompleted breadcrumb unobtainable after its follow-up is accepted or completed.

Zero or missing groups never become `0 / 0` or 100%. Actual unknown/malformed entries still suppress a percentage, rather than fabricating a denominator. The optional-data gate is gone; this defensive behavior remains for unreadable data. Unknown quests absent from upstream's inventory cannot be enumerated.

| Edge case | Policy and limitation |
| --- | --- |
| Faction, class and race | Reuse Journey's filtering; do not infer restrictions from geography. Questie's arithmetic mask checks preserve Forever Skyborne bits above 32 bits. |
| Level and prerequisites | Total mode includes Journey `p` future steps; available mode excludes them until requirements are met. Level-too-high/unobtainable quests follow `u`. |
| Exclusive branches | Follow categorization, but require the character flag for `c`; uncompleted alternatives are excluded. Activating or changing branches can change the denominator. |
| Breadcrumbs | Optional introductions to follow-up quests. Count at most once through a primary category; the separate breadcrumb list is an overlay. Followup-active/completed breadcrumbs usually become unobtainable; unclassified overlay-only entries stay unknown. |
| Repeatables and resets | Exclude `r` and quests flagged repeatable, daily, weekly or monthly by Questie's verified helpers. Incorrect or missing upstream flags cannot be repaired by this addon. |
| World events | Reuse Questie's seasonal grouping and active-event policy. This is not a calendar-completion tracker. |
| Dungeon and class quests | Follow Journey's assigned group; recognized class/profession sorts remain separate unless Journey explicitly redirects them. Do not silently add all class or dungeon quests to the outdoor zone. |
| Start/finish in different zones | Follow Journey's category/group assignment, not physical objective coverage. Its fallback and redirects may differ from raw `zoneOrSort`. |
| Newly added Forever quests | Only Questie/QuestieDB-known entries are visible; no second database or fabricated totals. |
| Incomplete history | Character flags are the available proof. Missing server history cannot be reconstructed; this addon stores no progress history. |
| Database/correction updates | Reuse the initialized Journey map. Restart/reload after upstream database changes. Counting never mutates Questie pointers, corrections or SavedVariables. User-initiated tracker movement delegates saving to Questie's existing handler, as described below. |

QuestieDB's [`questMeta.lua`](https://github.com/Questie/QuestieDB/blob/4f628e8328ed8923ffba169c8b432996e0a7a326/src/meta/questMeta.lua) defines `zoneOrSort` as positive AreaTable ID or negative QuestSort ID. Its [public read contract](https://github.com/Questie/QuestieDB/blob/4f628e8328ed8923ffba169c8b432996e0a7a326/docs/api.md#nil-and-empty-semantics) normalizes absent numeric fields to zero for known entities, while unknown IDs return nil. Zero is not independent evidence that a restriction is verified absent. Shared ID inventories are read-only; ordinary table-valued field reads are owned copies.

The database's [Forever documentation](https://github.com/Questie/QuestieDB/blob/4f628e8328ed8923ffba169c8b432996e0a7a326/docs/forever.md) and [generated data limitations](https://github.com/Questie/QuestieDB/blob/4f628e8328ed8923ffba169c8b432996e0a7a326/docs/forever-delta-base.md#policy-and-limitations) explicitly leave gameplay/restriction gaps. Its support maps also retain compatibility mappings that are not native Forever maps. No public per-zone coverage certificate or general database-change callback was found. Locale callbacks are not completeness notifications.

## Native settings and widget movement

Configuration is a native vertical category under Blizzard **Settings > AddOns**, rather than a custom window. The inspected Forever [Settings implementation](https://github.com/Gethe/wow-ui-source/blob/3d8abb1da73acd38e412e24fb3f99454a6392346/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_Settings.lua#L134) exposes `RegisterVerticalLayoutCategory`, `RegisterAddOnCategory`, `RegisterProxySetting`, `CreateCheckbox`, `CreateSliderOptions`, `CreateSlider`, `CreateDropdown` and `OpenToCategory`. Its [implementation guide](https://github.com/Gethe/wow-ui-source/blob/3d8abb1da73acd38e412e24fb3f99454a6392346/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua#L57) demonstrates proxy getters and setters for addon-owned storage. The native settings package is not load-on-demand in the inspected source.

Proxy getters/setters read and update this addon's per-character settings table. `setting:NotifyUpdate()` refreshes native controls after slash commands, reset or drag changes, without invoking setters again. This avoids replacing Blizzard controls or writing Questie's SavedVariables. `/qzc config` opens the registered category by ID.

Settings schema 3 retains the schema-2 removal of `knownScope` and `locked`, preserves valid visibility/scale/opacity/position preferences, and adds a per-character `collapsed` flag, defaulting to false. Starting with `0.2.0-beta.5`, new characters and reset settings default to `progressMode = "available"` and `attachToTracker = true`. Explicit saved choices for either progress mode or attachment remain intact; changing defaults does not reset existing characters. The schema remains 3 because the stored fields are unchanged. Clicking the separate **Zone Completion** title minimizes or expands the details beneath it; the title and settings question mark remain visible. The question mark opens this addon's native AddOns category. This state changes only the widget layout and requires no quest-data scan.

Movement uses **Ctrl + left drag**, matching Questie's locked-tracker gesture; Shift no longer moves the widget. Header, question-mark and progress regions share the same movement gesture while their ordinary clicks have separate actions. The widget has no lock control or movement label. Standalone position is stored as center offsets in UIParent units so widget scaling does not redefine the saved location.

## Optional Questie tracker attachment

The inspected [`TrackerBaseFrame.Initialize`](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Modules/Tracker/TrackerBaseFrame.lua#L32) creates the ordinary `Questie_BaseFrame`, then publishes `TrackerBaseFrame.baseFrame` and sets `TrackerBaseFrame.IsInitialized` at [lines 164–165](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Modules/Tracker/TrackerBaseFrame.lua#L164). [`QuestieTracker.Initialize`](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Modules/Tracker/QuestieTracker.lua#L225) sets `QuestieTracker.started` after creating its frames. The adapter returns that existing base frame only after Questie is ready, the tracker is enabled in its profile, those initialization flags are set, and the required frame capabilities match. It never calls a tracker initializer to force creation.

When attachment is enabled, the widget reparents **its own frame** to the returned tracker frame and anchors its bottom-left above the tracker's top-left. Parent inheritance follows the tracker's movement, scale, visibility and alpha without a polling loop or replacement of Questie's frame scripts. The widget retains its configured relative scale. A missing, disabled or incompatible tracker falls back to the saved standalone position; progress remains functional independently.

Ctrl-dragging an attached widget moves the **whole Questie tracker**, keeping attachment enabled and preserving this addon's standalone position. Detach through the native attachment setting or `/qzc attach off`. Tracker movement delegates to the same verified plain functions used by Questie's own header and icon: [`TrackerBaseFrame.OnDragStart(frame, button)`](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Modules/Tracker/TrackerBaseFrame.lua#L291) and [`TrackerBaseFrame.OnDragStop(frame, button)`](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Modules/Tracker/TrackerBaseFrame.lua#L366). The adapter explicitly supplies `"LeftButton"`; a frame's `OnDragStart` script does not supply the mouse-button argument these functions require.

The start handler returns true only when movement starts, and retains Questie's combat, modifier, chat-focus, locked/movable and sizing guards. The stop handler is paired with the captured moving tracker even after Ctrl is released. Questie's own `MODIFIER_STATE_CHANGED` handler may already have stopped a locked tracker when Ctrl is released before the mouse button; the adapter tolerates that completed stop. The handler stops movement and queues Questie's own `_UpdateTrackerPosition`, which saves `TrackerLocation` using Questie's selected anchor. This is user-authorized tracker interaction through Questie's handlers, **not a direct write by this addon to Questie's SavedVariables**, and does not alter or redistribute Questie files. Release/reload persistence remains a client test requirement. These handler and frame contracts are internal integration surfaces that must be rechecked when Questie changes.

## Tracker appearance

The progress display uses Questie's tracker typography and a frameless presentation instead of an independent tooltip-style card. The inspected [header update](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Modules/Tracker/TrackerHeaderFrame.lua#L200) sets the actual header label's font from `trackerFontHeader`, `trackerFontSizeHeader` and `trackerFontOutline`. Ordinary [tracker lines](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Modules/Tracker/LinePool/TrackerLine.lua#L202) use corresponding zone/quest/objective font settings through Questie's existing LibSharedMedia. The adapter reads these rendered/profile values and returns sanitized style data, using bounded local defaults if the optional styling surface changes.

The [tracker base frame](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Modules/Tracker/TrackerBaseFrame.lua#L170) applies `trackerBackdropEnabled`, `trackerBorderEnabled` and `trackerBackdropColor`; their defaults have no background or border. The widget follows those preferences and the tracker's content width when available, while preserving readable layout bounds. It does not restyle Questie's own fonts, frame or profile.

The compact display has no on-screen legend. Its ordinary hover tooltip contains the colored completed, in-progress, available and missing-requirement counts, plus a short progress-mode hint. Exclusion policies and integration details remain in documentation rather than permanent tooltip paragraphs. Actual unavailable/incomplete states still show a concise explanation when relevant. The question-mark artwork reuses the same `Questie.icons["complete"]` texture reference used by Questie's [tracker header](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Modules/Tracker/TrackerHeaderFrame.lua#L50), without bundling its file.

The count and percent use single-line font strings with wrapping disabled. The full label, such as `17 / 52 completed`, is measured after applying the current fonts and layout; if it does not fit beside the percentage, the display uses just `17 / 52`. Forever's generated [FontString documentation](https://github.com/Gethe/wow-ui-source/blob/3d8abb1da73acd38e412e24fb3f99454a6392346/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleFontStringAPIDocumentation.lua#L398) verifies unbounded text-width measurement and [`SetWordWrap`](https://github.com/Gethe/wow-ui-source/blob/3d8abb1da73acd38e412e24fb3f99454a6392346/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleFontStringAPIDocumentation.lua#L720). This avoids a wrapped suffix appearing beneath the bar when Questie's tracker narrows. Exact rendering at client fonts and UI scales remains a manual check.

Questie's [background fader](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Modules/Tracker/TrackerFadeTicker.lua) changes the base backdrop alpha directly, rather than necessarily fading the entire frame. Parent inheritance therefore covers frame visibility/scale/alpha, but is not by itself proof of identical backdrop-hover fading. Likewise, AceDB profile callbacks cover profile changes, not every individual font or width option; style refresh behavior must be checked with the actual client rather than assumed.

The adapter installs idempotent, read-only `hooksecurefunc` observers after the verified tracker `Update`, `UpdateFormatting`, `UpdateWidth`, base-frame `Update`, and available base-frame backdrop color setters. They request a coalesced layout refresh, not a quest-database scan, so font, content-width and existing background-fader changes can be resampled without an idle polling loop. These are internal method observers rather than replacement scripts; failure leaves normal progress functional. Hovering the attached section forwards to Questie's own `TrackerFadeTicker.Unfade`/`Fade` handlers, preserving its normal hover interaction. It does not introduce a second perpetual fader. Layout refreshes are coalesced over 0.1 seconds; exact animation appearance remains a client check.

## Navigation and refreshes

Clicking the progress area opens [`QuestieJourney:ToggleJourneyWindow()`](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Modules/Journey/QuestieJourney.lua#L189), guarded by `IsShown()` so an already-open Journey stays open, then selects **Quests by Zone** through `QuestieJourney.tabGroup:SelectTab("zone")`. It selects that tab on every progress click, including when Journey is already open on My Journey or another tab. The inspected [tab construction](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Modules/Journey/QuestieJourney.lua#L140) declares the `zone` value and installs the normal `OnGroupSelected` callback. The bundled [AceGUI tab implementation](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Libs/AceGUI-3.0/widgets/AceGUIContainer-TabGroup.lua#L329) changes the selected tab and fires that callback even when selecting the same existing value. Questie's own [`HandleTabChange`](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Modules/Journey/QuestieJourneyPrivates.lua#L19) redraws the zone tab and updates its own remembered tab state; this addon does not write that private state directly.

This verifies a **tab-level** integration, not a specific-zone deep link. The [zone dropdown handlers](https://github.com/Questie/Questie/blob/81dd55a3fafc5eac262eff618340b2bb2e98591f/Modules/Journey/tabs/QuestsByZone/QuestsByZoneTab.lua#L26) remain local functions coupled to private widgets, so the addon does not overwrite the user's selected category or zone. Missing/changed tab interfaces return a useful failure instead of claiming successful zone navigation. Opening Journey is deferred until outside combat by requiring another click, rather than modifying protected state or installing hooks.

Refreshes use Questie's public ready/update callbacks plus `QUEST_ACCEPTED`, `QUEST_REMOVED`, `QUEST_TURNED_IN`, `ZONE_CHANGED`, `ZONE_CHANGED_INDOORS`, `ZONE_CHANGED_NEW_AREA`, `PLAYER_ENTERING_WORLD`, and level/profession/spell/reputation changes, coalesced by a bounded timer. The verified Forever documentation also contains `QUEST_LOG_UPDATE` and `QUEST_DATA_LOAD_RESULT`; the addon relies on Questie's callbacks for quest-objective updates instead of repeatedly scanning on the broad log event. There is no perpetual OnUpdate database scan. The current generated docs do not list the old `QUEST_QUERY_COMPLETE` event, so it is not assumed.

Blizzard-source references: [`C_Map` documentation](https://github.com/Gethe/wow-ui-source/blob/3d8abb1da73acd38e412e24fb3f99454a6392346/Interface/AddOns/Blizzard_APIDocumentationGenerated/MapDocumentation.lua#L49) permits a nil best map; [`C_QuestLog.IsOnQuest`](https://github.com/Gethe/wow-ui-source/blob/3d8abb1da73acd38e412e24fb3f99454a6392346/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua#L825) returns a nonnil boolean; [character completion documentation](https://github.com/Gethe/wow-ui-source/blob/3d8abb1da73acd38e412e24fb3f99454a6392346/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua#L916) separates character and account completion. `QUEST_ACCEPTED` in Forever delivers quest ID, not the Classic-era `(logIndex, questId)` pair. This addon refreshes from current state rather than relying on that older payload.

## Maintainer checks when Questie changes

1. Inspect the public ready/update callback contracts and readiness timing.
2. Check module names, `zoneMap`, category node shapes, category identifiers and completion/exclusivity behavior.
3. Check current-zone/parent mapping, reset helpers and missing-entry handling.
4. Run automated adapter/counting fixtures, then compare actual Journey headers and individual character flags in Forever.
5. Verify the two denominator modes and the disjoint accepted-quest split against Journey and character flags. Update these revision links and record manual results before claiming client verification.
6. Recheck `QuestieTracker.started`, `TrackerBaseFrame.baseFrame`/`IsInitialized`, the drag handler calling conventions, styling inputs and the native Settings registration contract. Exercise tracker visibility/scaling, Ctrl-dragging the whole attached group, release of modifiers mid-drag, saved location, font/background changes and native controls in the client.
7. Verify single-line count resizing, tooltip brevity, the question-mark settings action, title minimize/restore persistence, and zone-tab selection from both hidden and already-open Journey windows. Header, icon and progress clicks must remain distinct after a Ctrl-drag.
