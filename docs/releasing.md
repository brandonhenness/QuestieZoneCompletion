# Release maintenance

The repository is configured for tag-triggered GitHub and CurseForge publishing,
with both release gates enabled and `CF_API_TOKEN` stored as an Actions secret.
The first beta, [v0.2.0-beta.5](https://github.com/brandonhenness/QuestieZoneCompletion/releases/tag/v0.2.0-beta.5),
is published on GitHub. The [tagged release workflow](https://github.com/brandonhenness/QuestieZoneCompletion/actions/runs/44485001929)
completed both validation and publication successfully. CurseForge accepted the
file upload; file processing and project moderator approval remain pending.

## First-release record

Observed on **2026-11-19**:

| Item | Confirmed result |
| --- | --- |
| GitHub release | Published prerelease `v0.2.0-beta.5` |
| Actions run | `44485001929`; validation and publish jobs succeeded |
| CurseForge project | [Questie Zone Completion](https://www.curseforge.com/wow/addons/questie-zone-completion), ID `1816201` |
| CurseForge uploaded file | ID `9697007`, Beta channel, game version `1.60.1` |
| File status | **Processing** in the author portal |
| Project status | New project awaiting moderator approval |
| File dependencies | Questie and QuestieDB both shown as Required Dependency |
| Artifact verification | GitHub and the CurseForge CDN serve identical ZIP bytes; all seven runtime/license members match the validated source |

Published ZIP SHA-256:
`1dc7d985e93dfae5df1b09038273829e7211e4ad428b6c1909f07da3f7210633`.
The checksum asset and durable upload receipt match this artifact.

API acceptance and a recorded file ID do not establish public availability.
Inspect the author portal for completed processing and moderator approval before
announcing CurseForge distribution as live. Main-branch CI and the
[authenticated version preflight](https://github.com/brandonhenness/QuestieZoneCompletion/actions/runs/44484301575)
passed; the latter verified Forever version `1.60.1`, file-version ID `17053`,
and game-version type `88568`. This game-version ID is distinct from the uploaded
file ID `9697007`. Review and record
the [manual test matrix](testing.md); initial local use has been reported successful,
but the full compatibility matrix remains outstanding. Beta publication must
describe that validation limit without claiming unperformed client tests.

## Pipeline

Ordinary branch pushes and pull requests run CI only. A pushed tag runs source,
Lua 5.1, behavior, package and publisher tests before preparing an installable ZIP.
Tags must be `vMAJOR.MINOR.PATCH`, `vMAJOR.MINOR.PATCH-alpha.N` or
`vMAJOR.MINOR.PATCH-beta.N` (positive `N`). Other prerelease spellings fail
validation. Alpha/beta tags create GitHub prereleases and the matching CurseForge
channel; stable tags use `release`.

The release job uses [BigWigsMods/packager](https://github.com/BigWigsMods/packager)
at reviewed commit `01e8631a69c69d7654c788d152630d5fed9e3812`, with uploads disabled
and `-g forever`. The packager recognizes Forever and `16???` interface values.
The addon uses the ordinary `QuestieZoneCompletion.toc` fallback filename;
`_Forever.toc` is not recognized by the inspected packager. Its
[upload implementation](https://github.com/BigWigsMods/packager/blob/01e8631a69c69d7654c788d152630d5fed9e3812/release.sh#L2889)
maps Forever to game-version **type** `88568` but can substitute another version
if an exact match is absent and retries upload POSTs. Consequently this project
uses its packaging support and a small, separately tested strict publisher for
the authenticated upload. This deliberately goes beyond the brief's fallback
condition to preserve exact version matching and safe reruns.

`tools/package.py` verifies the resulting ZIP against the manifest and source,
normalizes line endings and ZIP metadata, and writes its SHA-256 checksum. Only
the TOC, its Lua files and this project's license are included, beneath
`QuestieZoneCompletion/`. Questie and QuestieDB are required external dependencies
and are never bundled. The packaged TOC version comes from the validated tag.
The **same ZIP bytes** are stored in GitHub and uploaded to CurseForge.
Rebuilding with a different compression library can produce different ZIP bytes
despite identical members and normalized metadata; use the published checksum
to verify downloads and the same toolchain when comparing rebuilt archive hashes.

`tools/publish.py` creates a draft GitHub Release, stores immutable ZIP/checksum
assets, optionally uploads to CurseForge, and then publishes the GitHub Release.
Only this job gets `contents: write`; CI and packaging get read access. Per-tag
workflow concurrency prevents cancelled or overlapping uploads.

## One-time setup

1. The WoW addon project is already created as **Questie Zone Completion**,
   slug `questie-zone-completion`, project ID **`1816201`**. Monitor its moderation
   status in the CurseForge author portal; project creation is not confirmation
   of file acceptance or public availability. The TOC includes this project's
   `X-Curse-Project-ID` for CurseForge client identification.
2. Generate an upload token on the [CurseForge author token page](https://authors.curseforge.com/account/api-tokens).
   Add it as the repository Actions secret `CF_API_TOKEN`. It is sent only in the
   `X-Api-Token` header; never put it in command-line arguments or tracked files.
3. Set Actions repository variables:

   | Variable | Value |
   | --- | --- |
   | `CF_PROJECT_ID` | `1816201` |
   | `CF_GAME_VERSION_ID` | `17053`, authenticated mapping for Forever `1.60.1` |
   | `CF_PUBLISH_ENABLED` | `true` when CurseForge is ready; otherwise leave unset |
   | `RELEASE_ENABLED` | `true` after validation results and release notes are reviewed; otherwise leave unset |

4. Verify the current client with `select(4, GetBuildInfo())`, currently targeted
   as `16001`. Confirm the supported Questie/QuestieDB builds and run the manual
   matrix where available. Record actual results, versions and outstanding checks
   in `docs/testing.md`; use the beta channel while wider validation remains pending.
5. Run the **CurseForge preflight** workflow from the repository's GitHub Actions
   page using **Run workflow**. This manually dispatched workflow is read-only:
   it uses `CF_API_TOKEN` to verify the exact live Forever mapping and prints only
   the public version record. It does not create a release or upload a file.
   [The successful setup run](https://github.com/brandonhenness/QuestieZoneCompletion/actions/runs/44484301575)
   confirmed `id: 17053`, `name: "1.60.1"`, and `gameVersionTypeID: 88568`.

   For a local check with the token already in your process environment, run:

   ```powershell
   python tools/publish.py --list-versions
   ```

   After changing the target client interface, rerun preflight and review its
   unique matching record before updating `CF_GAME_VERSION_ID`. The upload job
   **rechecks the exact type, name and configured ID every time**, with no
   fallback to a different client or version. Keep the mapping separate from
   project ID `1816201`; these IDs identify different objects.
6. Ensure repository Actions can create releases. Restrict release-tag creation
   to maintainers using repository rules where available. No personal GitHub
   token is needed; the job uses `GITHUB_TOKEN`.

Leaving `RELEASE_ENABLED` unset still builds tagged workflow artifacts for
review. Leaving only `CF_PUBLISH_ENABLED` unset allows GitHub-only releases.
Enabling CurseForge with missing credentials/project/version configuration fails
before creating the GitHub draft, rather than silently skipping the upload.

## Release checklist

1. Update runtime source and the concise README; document integration changes,
   compatibility limitations and manual results. Review dependencies and licenses.
2. Curate `CHANGELOG.md` for the tag. Its contents are used as release notes on
   both services. The initial public tag is `v0.2.0-beta.5`; retain a beta channel
   while broader in-game validation remains outstanding.
3. Run local checks:

   ```powershell
   python tools/package.py
   lua5.1 tests/run.lua
   python -m unittest discover -s tests -p 'test_*.py' -v
   python tools/package.py --version v0.2.0-beta.5 --output dist/QuestieZoneCompletion-v0.2.0-beta.5-forever.zip
   ```

   Lua executable names vary locally. CI additionally compiles every Lua file
   using `luac5.1 -p`. `python` must be 3.10 or newer; CI uses 3.14.
4. Commit the reviewed changes, then create and push the deliberate version tag:

   ```powershell
   git tag -a v0.2.0-beta.5 -m 'Questie Zone Completion 0.2.0 beta 5'
   git push origin v0.2.0-beta.5
   ```

5. Inspect Actions validation, archive contents, SHA-256 and the GitHub Release.
   For CurseForge, inspect the returned file ID, moderation status, Forever
   version, release channel and required `questie` / `questiedb` relations.
   A returned file ID confirms API acceptance; moderation/public availability
   still needs inspection. Install the published artifact for a smoke test.

## Reruns and interrupted uploads

Published ZIP/checksum assets are immutable. A rerun reuses matching assets and
refuses to overwrite different bytes. Never move an existing release tag.

Immediately before the single CurseForge POST, the publisher creates the GitHub
asset `curseforge-upload-intent.json`. After a positive API file ID, it stores
`curseforge-upload-receipt.json`, containing that ID and the tag, artifact hash,
project, game-version mapping and channel. A matching receipt lets reruns finish
without another POST. POST requests are never automatically retried.

An intent without a receipt is deliberately an actionable failure: the API might
have accepted an upload before a response or receipt was lost. Inspect the
CurseForge project and Actions logs before changing anything:

- If no upload was accepted, delete **only** the orphaned intent asset from the
  GitHub draft and rerun the failed workflow. Confirm absence with CurseForge
  support if the API outcome remains uncertain.
- If the exact file was accepted, verify its artifact/hash, mapping and channel,
  then attach `curseforge-upload-receipt.json` manually. Copy the intent object
  unchanged as the `identity` value and use the confirmed numeric `fileID`:

  ```json
  {"identity": {"...": "exact object from the intent asset"}, "fileID": 123456}
  ```

  Replace the illustrated object and ID with the real verified values. Rerun the
  workflow; it validates the receipt before finishing. Do not delete the intent
  merely to bypass an uncertain upload.

If finalizing the GitHub Release fails after the receipt was stored, rerun
normally. The receipt prevents another CurseForge upload. Upload errors are
reported without dumping credentials or arbitrary server response bodies.

The upload contract follows the official
[CurseForge Upload API](https://support.curseforge.com/support/solutions/articles/9000197321-curseforge-upload-api).
The live WoW versions endpoint is `/api/game/wow/versions`, as used by the pinned
packager. The upload endpoint is `/api/projects/{projectId}/upload-file` with
`metadata` and `file` multipart fields. No project, token, or successful external
publication is assumed by the repository.
