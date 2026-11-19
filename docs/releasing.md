# Release maintenance

Publishing is **disabled by default** until the repository and CurseForge setup
below are complete. The first public version is prepared as `v0.2.0-beta.5`.
No GitHub Release or CurseForge upload has been confirmed yet. Review and record
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

`tools/publish.py` creates a draft GitHub Release, stores immutable ZIP/checksum
assets, optionally uploads to CurseForge, and then publishes the GitHub Release.
Only this job gets `contents: write`; CI and packaging get read access. Per-tag
workflow concurrency prevents cancelled or overlapping uploads.

## One-time setup

1. Create and obtain approval for a CurseForge WoW addon project. Save its numeric
   project ID; do not use Questie's or QuestieDB's project ID.
2. Generate an upload token on the [CurseForge author token page](https://authors.curseforge.com/account/api-tokens).
   Add it as the repository Actions secret `CF_API_TOKEN`. It is sent only in the
   `X-Api-Token` header; never put it in command-line arguments or tracked files.
3. Set Actions repository variables:

   | Variable | Value |
   | --- | --- |
   | `CF_PROJECT_ID` | Your approved addon project's numeric ID |
   | `CF_GAME_VERSION_ID` | Approved live Forever **file version** ID for `1.60.1` |
   | `CF_PUBLISH_ENABLED` | `true` when CurseForge is ready; otherwise leave unset |
   | `RELEASE_ENABLED` | `true` after validation results and release notes are reviewed; otherwise leave unset |

4. Verify the current client with `select(4, GetBuildInfo())`, currently targeted
   as `16001`. Confirm the supported Questie/QuestieDB builds and run the manual
   matrix where available. Record actual results, versions and outstanding checks
   in `docs/testing.md`; use the beta channel while wider validation remains pending.
5. Verify CurseForge's authenticated live versions response. With the token in
   your process environment, run:

   ```powershell
   python tools/publish.py --list-versions
   ```

   Select the unique record with `gameVersionTypeID: 88568` and `name: "1.60.1"`.
   Its `id` is the value for `CF_GAME_VERSION_ID`. QuestieDB's inspected
   [distribution source](https://github.com/Questie/QuestieDB/blob/4f628e8328ed8923ffba169c8b432996e0a7a326/tools/distribution/curseforge.py#L29)
   currently uses `17053`, but this project has not authenticated to verify that
   live response. The upload job **rechecks the exact type, name and configured
   ID every time**, with no fallback to a different client or version.
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
