"""Publish one validated ZIP; preserve durable intent before a single CF POST.

All credentials come from environment variables. Network operations are only
performed by main(); unit tests exercise the publisher with fake transports.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

try:
    from .package import ADDON, INTERFACE, release_type, validate_zip
except ImportError:
    from package import ADDON, INTERFACE, release_type, validate_zip

FOREVER_TYPE_ID = 88568  # Verified in the pinned BigWigs packager; checked live too.
CF_BASE = "https://wow.curseforge.com"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def request(url: str, *, token: str = "", method: str = "GET", data: bytes | None = None,
            content_type: str = "application/json", github: bool = False, raw: bool = False):
    headers = {"User-Agent": "QuestieZoneCompletion-release", "Content-Type": content_type,
               "Accept": "application/octet-stream" if raw else "application/json"}
    if token:
        headers["Authorization" if github else "X-Api-Token"] = f"Bearer {token}" if github else token
    opener = urllib.request.build_opener(NoRedirect)
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with opener.open(req, timeout=60) as response:
            payload = response.read()
    except urllib.error.HTTPError as error:
        # GitHub asset downloads redirect to a signed HTTPS URL. Never forward
        # either authorization header to that host or follow an upload redirect.
        location = error.headers.get("Location", "")
        parsed = urllib.parse.urlparse(location)
        if github and raw and method == "GET" and error.code in (301, 302, 303, 307, 308) and (
                parsed.scheme == "https" and parsed.hostname and parsed.hostname.endswith(".githubusercontent.com")):
            return request(location, raw=True)
        # Response bodies may contain credentials or private data; report status only.
        raise RuntimeError(f"{method} {urllib.parse.urlparse(url).path}: HTTP {error.code}") from None
    return payload if raw else json.loads(payload) if payload else None


def encode_json(value) -> bytes:
    return (json.dumps(value, sort_keys=True, indent=2) + "\n").encode()


class GitHub:
    def __init__(self, repository: str, token: str):
        parts = repository.split("/")
        if len(parts) != 2 or not all(part and part.replace("-", "").replace("_", "").replace(".", "").isalnum() for part in parts):
            raise ValueError("GITHUB_REPOSITORY must be owner/repository")
        self.repository = repository
        self.token = token
        self.base = f"https://api.github.com/repos/{repository}"

    def api(self, path: str, method: str = "GET", value=None):
        return request(self.base + path, token=self.token, github=True, method=method,
                       data=encode_json(value) if value is not None else None)

    def release(self, tag: str, changelog: str, channel: str) -> dict:
        # List instead of interpreting a 404 (which can also mean missing access).
        releases = []
        for page in range(1, 101):
            batch = self.api(f"/releases?per_page=100&page={page}")
            releases.extend(batch)
            if len(batch) < 100:
                break
        else:
            raise RuntimeError("Release listing exceeded its safety bound")
        matches = [release for release in releases if release["tag_name"] == tag]
        if len(matches) > 1:
            raise RuntimeError("Multiple releases exist for this tag")
        if matches:
            return matches[0]
        return self.api("/releases", "POST", {"tag_name": tag, "name": tag, "body": changelog,
                        "draft": True, "prerelease": channel != "release"})

    def assets(self, release: dict) -> list:
        assets = []
        for page in range(1, 101):
            batch = self.api(f"/releases/{release['id']}/assets?per_page=100&page={page}")
            assets.extend(batch)
            if len(batch) < 100:
                return assets
        raise RuntimeError("Asset listing exceeded its safety bound")

    def find_asset(self, release: dict, name: str):
        return next((asset for asset in self.assets(release) if asset["name"] == name), None)

    def read_asset(self, asset: dict) -> bytes:
        return request(f"{self.base}/releases/assets/{asset['id']}", token=self.token, github=True, raw=True)

    def put_asset(self, release: dict, name: str, data: bytes, content_type="application/json", *, exclusive=False):
        existing = None if exclusive else self.find_asset(release, name)
        if existing:
            digest = existing.get("digest")
            if digest != "sha256:" + hashlib.sha256(data).hexdigest() and self.read_asset(existing) != data:
                raise RuntimeError(f"Immutable release asset differs: {name}")
            return existing
        url = f"https://uploads.github.com/repos/{self.repository}/releases/{release['id']}/assets?" + urllib.parse.urlencode({"name": name})
        return request(url, token=self.token, github=True, method="POST", data=data, content_type=content_type)

    def finish(self, release: dict, channel: str):
        return self.api(f"/releases/{release['id']}", "PATCH", {"draft": False, "prerelease": channel != "release"})


def forever_version(versions: list, approved_id: int) -> dict:
    if not isinstance(versions, list) or not all(isinstance(version, dict) for version in versions):
        raise ValueError("CurseForge did not return a game-version list")
    name = f"{int(INTERFACE) // 10000}.{int(INTERFACE) // 100 % 100}.{int(INTERFACE) % 100}"
    matches = [version for version in versions if version.get("gameVersionTypeID") == FOREVER_TYPE_ID
               and version.get("name") == name]
    if len(matches) != 1 or matches[0].get("id") != approved_id:
        raise ValueError(f"Live CurseForge mapping must uniquely match approved ID {approved_id}, Forever type {FOREVER_TYPE_ID}, version {name}")
    return matches[0]


def multipart(metadata: dict, archive_name: str, archive: bytes) -> tuple[str, bytes]:
    boundary = "qzc" + uuid.uuid4().hex
    data = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"metadata\"\r\n"
            f"Content-Type: application/json\r\n\r\n").encode() + encode_json(metadata)
    data += (f"\r\n--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{archive_name}\"\r\n"
             f"Content-Type: application/zip\r\n\r\n").encode() + archive
    data += f"\r\n--{boundary}--\r\n".encode()
    return f"multipart/form-data; boundary={boundary}", data


def publish(github: GitHub, tag: str, archive: Path, changelog: str, *, cf_token: str = "",
            cf_project: int | None = None, cf_version: int | None = None):
    channel = release_type(tag)
    if not archive.name or any(character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-" for character in archive.name):
        raise ValueError("Unsafe archive filename")
    data = archive.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    # Fail before creating even a draft when CF was requested but incomplete.
    mapping = None
    if cf_project is not None:
        if not cf_token or cf_project <= 0 or not cf_version or cf_version <= 0:
            raise ValueError("CF publishing requires CF_API_TOKEN, CF_PROJECT_ID and approved CF_GAME_VERSION_ID")
        mapping = forever_version(request(f"{CF_BASE}/api/game/wow/versions", token=cf_token), cf_version)
    release = github.release(tag, changelog, channel)
    github.put_asset(release, archive.name, data, "application/zip")
    github.put_asset(release, archive.name + ".sha256", f"{digest}  {archive.name}\n".encode(), "text/plain")
    if mapping:
        identity = {"tag": tag, "sha256": digest, "projectID": cf_project,
                    "gameVersionID": mapping["id"], "gameVersionTypeID": mapping["gameVersionTypeID"],
                    "gameVersion": mapping["name"], "releaseType": channel}
        intent_name = "curseforge-upload-intent.json"
        receipt_name = "curseforge-upload-receipt.json"
        receipt = github.find_asset(release, receipt_name)
        if receipt:
            recorded = json.loads(github.read_asset(receipt))
            if recorded.get("identity") != identity or type(recorded.get("fileID")) is not int or recorded["fileID"] <= 0:
                raise RuntimeError("CurseForge receipt does not match this immutable artifact/configuration")
            print(f"CurseForge already confirmed file {recorded['fileID']}; upload skipped")
        else:
            if github.find_asset(release, intent_name):
                raise RuntimeError("An upload intent exists without a receipt. Inspect CurseForge before recovery; automatic re-upload is disabled")
            # GitHub rejects an asset-name collision, making concurrent attempts
            # fail before their POST. An ambiguous network outcome stays blocked.
            github.put_asset(release, intent_name, encode_json(identity), exclusive=True)
            metadata = {"displayName": f"{ADDON} {tag} (Forever)", "gameVersions": [mapping["id"]],
                        "releaseType": channel, "changelog": changelog, "changelogType": "markdown",
                        "relations": {"projects": [{"slug": slug, "type": "requiredDependency"}
                                                    for slug in ("questie", "questiedb")]}}
            content_type, body = multipart(metadata, archive.name, data)
            result = request(f"{CF_BASE}/api/projects/{cf_project}/upload-file", token=cf_token,
                             method="POST", data=body, content_type=content_type)
            if not isinstance(result, dict) or type(result.get("id")) is not int or result["id"] <= 0:
                raise RuntimeError("CurseForge did not confirm a positive file ID; inspect the upload intent before retrying")
            github.put_asset(release, receipt_name, encode_json({"identity": identity, "fileID": result["id"]}))
            print(f"CurseForge confirmed file {result['id']}")
    github.finish(release, channel)
    print(f"GitHub Release ready: {tag}; artifact sha256 {digest}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag")
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--list-versions", action="store_true")
    args = parser.parse_args()
    cf_token = os.environ.get("CF_API_TOKEN", "")
    if args.list_versions:
        versions = request(f"{CF_BASE}/api/game/wow/versions", token=cf_token)
        print(json.dumps([value for value in versions if value.get("gameVersionTypeID") == FOREVER_TYPE_ID], indent=2))
        return
    if not args.tag or not args.archive:
        parser.error("--tag and --archive are required for publishing")
    if os.environ.get("GITHUB_REF") != "refs/tags/" + args.tag or os.environ.get("GITHUB_EVENT_NAME") != "push":
        raise ValueError("Publishing is restricted to a tag-push workflow")
    validate_zip(args.archive, args.root, args.tag)
    enabled = os.environ.get("CF_PUBLISH_ENABLED") == "true"
    publish(GitHub(os.environ["GITHUB_REPOSITORY"], os.environ["GITHUB_TOKEN"]), args.tag, args.archive,
            (args.root / "CHANGELOG.md").read_text(encoding="utf-8"), cf_token=cf_token,
            cf_project=int(os.environ.get("CF_PROJECT_ID", "0")) if enabled else None,
            cf_version=int(os.environ.get("CF_GAME_VERSION_ID", "0")) if enabled else None)


if __name__ == "__main__":
    main()
