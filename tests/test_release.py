"""Offline regression tests for release integrity and ambiguous upload recovery."""

import copy
import contextlib
import hashlib
import io
import json
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

from tools import package, publish


def source(root: Path):
    (root / package.TOC).write_text("\n".join([
        "## Interface: 16001", "## Title: Questie Zone Completion", "## Version: 0.1.0",
        "## OptionalDeps: Questie, QuestieDB", "## SavedVariablesPerCharacter: QuestieZoneCompletionDB",
        "Config.lua", "Core.lua", "",
    ]), encoding="utf-8")
    (root / "Config.lua").write_text("local config = {}\n", encoding="utf-8")
    (root / "Core.lua").write_text("local core = {}\n", encoding="utf-8")
    (root / "LICENSE").write_text("Test license\n", encoding="utf-8")
    (root / "secret.env").write_text("never packaged", encoding="utf-8")


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        source(self.root)

    def test_channels_are_deliberate(self):
        for tag, channel in [("v1.2.3", "release"), ("v0.1.0-alpha.1", "alpha"), ("v2.0.0-beta.7", "beta")]:
            self.assertEqual(package.release_type(tag), channel)
        for tag in ("v01.0.0", "v1.0.0-rc.1", "v1.0.0-alpha.0", "v1.0.0; echo token", "main"):
            with self.assertRaises(ValueError):
                package.release_type(tag)

    def test_zip_is_runtime_only_and_reproducible_across_line_endings(self):
        first = self.root / "a.zip"
        second = self.root / "b.zip"
        package.build(self.root, first, "v0.1.0-beta.1")
        (self.root / "Config.lua").write_bytes(b"local config = {}\r\n")
        package.build(self.root, second, "v0.1.0-beta.1")
        self.assertEqual(first.read_bytes(), second.read_bytes())
        contents = package.validate_zip(first, self.root, "v0.1.0-beta.1")
        self.assertEqual(len(contents), 4)
        self.assertIn(b"## Version: 0.1.0-beta.1", contents[package.ADDON + "/" + package.TOC])
        self.assertNotIn(package.ADDON + "/secret.env", contents)

    def test_extra_and_missing_archive_files_fail_closed(self):
        archive = self.root / "extra.zip"
        package.build(self.root, archive)
        with zipfile.ZipFile(archive, "a") as zipped:
            zipped.writestr(package.ADDON + "/secret.env", "no")
        with self.assertRaisesRegex(ValueError, "unexpected"):
            package.validate_zip(archive, self.root)
        with zipfile.ZipFile(archive, "w") as zipped:
            zipped.writestr(package.ADDON + "/Core.lua", "local core = {}\n")
        with self.assertRaisesRegex(ValueError, "Missing archive entries"):
            package.validate_zip(archive, self.root)

    def test_modified_runtime_file_is_rejected(self):
        archive = self.root / "modified.zip"
        package.build(self.root, archive)
        (self.root / "Core.lua").write_text("error('changed')\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "differs"):
            package.validate_zip(archive, self.root)

    def test_source_rejects_unverified_interface_missing_dependency_and_traversal(self):
        toc = self.root / package.TOC
        original = toc.read_text(encoding="utf-8")
        for old, new in [("16001", "11508"), ("Questie, QuestieDB", "Questie"),
                         ("Config.lua", "../Config.lua"), ("Config.lua", "./Config.lua")]:
            toc.write_text(original.replace(old, new), encoding="utf-8")
            with self.assertRaises(ValueError):
                package.validate_source(self.root)
        toc.write_text(original, encoding="utf-8")

    def test_bigwigs_zip_normalization_produces_local_build_bytes(self):
        original, normalized, local = [self.root / name for name in ("original.zip", "normal.zip", "local.zip")]
        # BigWigs leaves a literal playable-source version unchanged on beta
        # tags; normalization must stamp it before comparison and ZIP writing.
        package.build(self.root, original)
        with zipfile.ZipFile(original) as zipped:
            self.assertIn(b"## Version: 0.1.0\n", zipped.read(package.ADDON + "/" + package.TOC))
        with self.assertRaisesRegex(ValueError, "differs"):
            package.validate_zip(original, self.root, "v0.1.0-beta.1")
        package.build(self.root, normalized, "v0.1.0-beta.1", source_zip=original)
        package.build(self.root, local, "v0.1.0-beta.1")
        self.assertEqual(normalized.read_bytes(), local.read_bytes())
        with zipfile.ZipFile(normalized) as zipped:
            self.assertIn(b"## Version: 0.1.0-beta.1\n", zipped.read(package.ADDON + "/" + package.TOC))
        package.validate_zip(normalized, self.root, "v0.1.0-beta.1")


class FakeGitHub:
    def __init__(self):
        self.stored = {}
        self.created = False
        self.finished = False
        self.fail_receipt = False
        self.fail_finish = False

    def release(self, tag, changelog, channel):
        self.created = True
        return {"id": 1, "tag_name": tag}

    def find_asset(self, release, name):
        return {"name": name} if name in self.stored else None

    def read_asset(self, asset):
        return self.stored[asset["name"]]

    def put_asset(self, release, name, data, content_type="application/json", *, exclusive=False):
        if self.fail_receipt and name.endswith("receipt.json"):
            raise RuntimeError("Simulated GitHub interruption")
        if name in self.stored and (exclusive or self.stored[name] != data):
            raise RuntimeError("Immutable asset collision")
        self.stored[name] = data

    def finish(self, release, channel):
        if self.fail_finish:
            raise RuntimeError("Simulated GitHub finalize interruption")
        self.finished = True


class PublisherTests(unittest.TestCase):
    VERSIONS = [{"id": 17053, "gameVersionTypeID": 88568, "name": "1.60.1"}]

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.archive = Path(self.temp.name) / "QuestieZoneCompletion-v0.1.0-forever.zip"
        self.archive.write_bytes(b"exact validated zip bytes")
        self.github = FakeGitHub()
        self.posts = []
        self.response = {"id": 42}
        self.output = contextlib.redirect_stdout(io.StringIO())
        self.output.__enter__()
        self.addCleanup(self.output.__exit__, None, None, None)

    def transport(self, url, **kwargs):
        if kwargs.get("method", "GET") == "POST":
            self.posts.append((url, kwargs))
            return self.response
        return copy.deepcopy(self.VERSIONS)

    def run_publish(self, **kwargs):
        with patch("tools.publish.request", side_effect=self.transport):
            publish.publish(self.github, "v0.1.0", self.archive, "Release notes", cf_token="secret",
                            cf_project=123, cf_version=17053, **kwargs)

    def test_exact_artifact_upload_and_confirmed_rerun_skips_post(self):
        self.run_publish()
        self.run_publish()
        self.assertEqual(len(self.posts), 1)
        self.assertIn(self.archive.read_bytes(), self.posts[0][1]["data"])
        self.assertIn(b'"gameVersions": [\n    17053', self.posts[0][1]["data"])
        self.assertEqual(self.github.stored[self.archive.name], self.archive.read_bytes())
        receipt = json.loads(self.github.stored["curseforge-upload-receipt.json"])
        self.assertEqual(receipt["fileID"], 42)
        self.assertEqual(receipt["identity"]["sha256"], hashlib.sha256(self.archive.read_bytes()).hexdigest())
        self.assertTrue(self.github.finished)

    def test_ambiguous_response_creates_intent_and_prevents_reupload(self):
        self.response = {}
        with self.assertRaisesRegex(RuntimeError, "did not confirm"):
            self.run_publish()
        with self.assertRaisesRegex(RuntimeError, "intent exists"):
            self.run_publish()
        self.assertEqual(len(self.posts), 1)
        self.assertFalse(self.github.finished)

    def test_receipt_persistence_failure_prevents_duplicate(self):
        self.github.fail_receipt = True
        with self.assertRaisesRegex(RuntimeError, "interruption"):
            self.run_publish()
        self.github.fail_receipt = False
        with self.assertRaisesRegex(RuntimeError, "intent exists"):
            self.run_publish()
        self.assertEqual(len(self.posts), 1)

    def test_finalize_failure_can_resume_without_uploading_twice(self):
        self.github.fail_finish = True
        with self.assertRaisesRegex(RuntimeError, "interruption"):
            self.run_publish()
        self.github.fail_finish = False
        self.run_publish()
        self.assertEqual(len(self.posts), 1)
        self.assertTrue(self.github.finished)

    def test_changed_artifact_is_never_overwritten(self):
        self.run_publish()
        self.archive.write_bytes(b"different artifact")
        with self.assertRaisesRegex(RuntimeError, "collision"):
            self.run_publish()
        self.assertEqual(len(self.posts), 1)

    def test_forever_mapping_must_be_exact_unique_and_approved(self):
        for versions, approved in [([], 17053), (self.VERSIONS * 2, 17053), (self.VERSIONS, 999),
                                   ([{"id": 17053, "gameVersionTypeID": 517, "name": "1.60.1"}], 17053)]:
            with self.assertRaises(ValueError):
                publish.forever_version(versions, approved)
        self.assertEqual(publish.forever_version(self.VERSIONS, 17053)["id"], 17053)

    def test_disabled_curseforge_uses_no_network(self):
        with patch("tools.publish.request") as network:
            publish.publish(self.github, "v0.1.0-beta.1", self.archive, "Notes")
            network.assert_not_called()
        self.assertNotIn("curseforge-upload-intent.json", self.github.stored)

    def test_incomplete_cf_configuration_fails_before_github_mutation(self):
        with self.assertRaises(ValueError):
            publish.publish(self.github, "v0.1.0", self.archive, "Notes", cf_project=0)
        self.assertFalse(self.github.created)

    def test_exclusive_intent_creation_never_reuses_existing_intent(self):
        github = publish.GitHub("owner/repository", "secret")
        with patch.object(github, "find_asset") as find, patch("tools.publish.request", side_effect=RuntimeError("HTTP 422")):
            with self.assertRaisesRegex(RuntimeError, "422"):
                github.put_asset({"id": 1}, "curseforge-upload-intent.json", b"{}", exclusive=True)
            find.assert_not_called()

    def test_invalid_version_response_fails_before_any_publication(self):
        with patch("tools.publish.request", return_value={"errorMessage": "not a version list"}):
            with self.assertRaisesRegex(ValueError, "game-version list"):
                publish.publish(self.github, "v0.1.0", self.archive, "Notes", cf_token="secret", cf_project=123, cf_version=17053)
        self.assertFalse(self.github.created)


if __name__ == "__main__":
    unittest.main()
