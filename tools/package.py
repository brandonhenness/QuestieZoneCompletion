"""Validate the addon manifest and create a deterministic, runtime-only ZIP.

The release workflow uses BigWigsMods/packager first, then validates and
normalizes its ZIP. Local builds use the same allowlist and archive format.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import stat
import zipfile
from pathlib import Path, PurePosixPath

ADDON = "QuestieZoneCompletion"
TOC = f"{ADDON}.toc"
INTERFACE = "16001"
SEMVER = re.compile(r"v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-(alpha|beta)\.([1-9]\d*))?\Z")


def release_type(version: str) -> str:
    match = SEMVER.fullmatch(version)
    if not match:
        raise ValueError("Use vMAJOR.MINOR.PATCH, optionally -alpha.N or -beta.N")
    return match.group(4) or "release"


def read_manifest(root: Path) -> tuple[dict[str, str], list[str]]:
    metadata: dict[str, str] = {}
    files: list[str] = []
    for line in (root / TOC).read_text(encoding="utf-8-sig").splitlines():
        if line.startswith("##"):
            key, sep, value = line[2:].partition(":")
            if sep:
                key = key.strip()
                if key in metadata:
                    raise ValueError(f"Duplicate TOC field: {key}")
                metadata[key] = value.strip()
        elif line.strip() and not line.lstrip().startswith("#"):
            name = line.strip().replace("\\", "/")
            path = PurePosixPath(name)
            if path.is_absolute() or ".." in path.parts or ":" in name or path.suffix != ".lua" or path.as_posix() != name:
                raise ValueError(f"Unsafe or unsupported TOC path: {name}")
            if name in files:
                raise ValueError(f"Duplicate TOC entry: {name}")
            files.append(name)
    return metadata, files


def validate_source(root: Path) -> list[str]:
    metadata, files = read_manifest(root)
    if metadata.get("Interface") != INTERFACE:
        raise ValueError(f"Expected verified Forever Interface {INTERFACE}")
    if not metadata.get("Title") or not files:
        raise ValueError("TOC requires a title and runtime files")
    release_type(metadata.get("Version", ""))
    dependencies = set()
    for key in ("Dependencies", "RequiredDeps", "OptionalDeps"):
        dependencies.update(part.strip() for part in metadata.get(key, "").split(","))
    if not {"Questie", "QuestieDB"}.issubset(dependencies):
        raise ValueError("Manifest must declare Questie and QuestieDB load ordering")
    if not metadata.get("SavedVariablesPerCharacter"):
        raise ValueError("Expected per-character settings declaration")
    if files[-1] != "Core.lua":
        raise ValueError("Core.lua must load after the modules it initializes")
    allowed = sorted([TOC, "LICENSE", *files])
    for name in allowed:
        path = root / name
        if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(root.resolve()):
            raise ValueError(f"Missing, linked, or out-of-tree runtime file: {name}")
        if not path.read_bytes():
            raise ValueError(f"Empty runtime file: {name}")
    return allowed


def runtime_bytes(root: Path, name: str, version: str | None = None) -> bytes:
    # Normalize checkout line endings so Windows and Linux produce the same ZIP.
    data = (root / name).read_bytes().replace(b"\r\n", b"\n")
    if name == TOC and version:
        release_type(version)
        data = re.sub(rb"(?m)^## Version:.*$", f"## Version: {version.removeprefix('v')}".encode(), data)
    return data


def validate_zip(archive: Path, root: Path, version: str | None = None, *, stamp_version: bool = False) -> dict[str, bytes]:
    expected = {f"{ADDON}/{name}": name for name in validate_source(root)}
    contents: dict[str, bytes] = {}
    with zipfile.ZipFile(archive) as zipped:
        for item in zipped.infolist():
            if item.is_dir():
                if item.filename != f"{ADDON}/" and not any(name.startswith(item.filename) for name in expected):
                    raise ValueError(f"Unexpected archive directory: {item.filename}")
                continue
            if item.filename in contents or item.filename not in expected:
                raise ValueError(f"Duplicate or unexpected archive entry: {item.filename}")
            if stat.S_ISLNK(item.external_attr >> 16) or item.file_size > 2 * 1024 * 1024:
                raise ValueError(f"Invalid archive file: {item.filename}")
            data = zipped.read(item).replace(b"\r\n", b"\n")
            source = runtime_bytes(root, expected[item.filename], version)
            # Only the normalization input may have an unstamped playable TOC.
            # Final archive validation (including publishing) is always strict.
            if expected[item.filename] == TOC and version and stamp_version:
                data = re.sub(rb"(?m)^## Version:.*$", f"## Version: {version.removeprefix('v')}".encode(), data)
            if data != source:
                raise ValueError(f"Packaged content differs from validated source: {item.filename}")
            contents[item.filename] = data
    if set(contents) != set(expected):
        raise ValueError(f"Missing archive entries: {sorted(set(expected) - set(contents))}")
    return contents


def write_zip(output: Path, contents: dict[str, bytes]) -> str:
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zipped:
        for name, data in sorted(contents.items()):
            item = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            item.create_system = 3
            item.external_attr = 0o100644 << 16
            item.compress_type = zipfile.ZIP_DEFLATED
            zipped.writestr(item, data, compresslevel=9)
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix(".zip.sha256").write_text(f"{digest}  {output.name}\n", encoding="ascii")
    return digest


def build(root: Path, output: Path, version: str | None = None, source_zip: Path | None = None) -> str:
    files = validate_source(root)
    if version:
        release_type(version)
    contents = validate_zip(source_zip, root, version, stamp_version=True) if source_zip else {
        f"{ADDON}/{name}": runtime_bytes(root, name, version) for name in files
    }
    digest = write_zip(output, contents)
    validate_zip(output, root, version)
    return digest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--version", help="Release tag; replaces the packaged TOC version")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--from-zip", type=Path, help="Validate and normalize a BigWigs-built ZIP")
    args = parser.parse_args()
    if args.output:
        print(f"{args.output}: sha256 {build(args.root, args.output, args.version, args.from_zip)}")
    else:
        print(f"Validated {len(validate_source(args.root))} runtime files")


if __name__ == "__main__":
    main()
