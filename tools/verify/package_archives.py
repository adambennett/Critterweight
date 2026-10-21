"""Check every archived file against BUILD_MANIFEST without extracting anything.

Accepts build-directory names and the versioned GitHub asset names. Also checks
the Linux executable bit, archive digests, duplicate members and all four targets.
"""
import argparse
import hashlib
import json
import pathlib
import tarfile
import zipfile


def digest(stream):
    result = hashlib.sha256()
    while True:
        chunk = stream.read(1024 * 1024)
        if not chunk:
            return result.hexdigest()
        result.update(chunk)


def verify(folder, version, allow_dirty=False):
    folder = pathlib.Path(folder)
    manifest = json.loads((folder / "BUILD_MANIFEST.json").read_text(encoding="utf-8-sig"))
    assert manifest["version"] == version, "Wrong manifest version"
    assert allow_dirty or not manifest["working_tree_dirty"], "Release source is dirty"
    if not allow_dirty:
        assert manifest.get("tag") == "v" + version, "Missing exact release tag"
    targets = manifest["targets"]
    assert len(targets) == 4, "Expected four build targets"
    assert {t["target"] for t in targets} == {"Windows Desktop", "Linux", "Windows Server", "Linux Server"}
    reports = []
    for target in targets:
        original_name = target["archive"]
        assert pathlib.PurePosixPath(original_name).name == original_name, "Unsafe archive name"
        archive = folder / original_name
        if not archive.is_file():
            archive = folder / original_name.replace("Critterweight-", "Critterweight-" + version + "-", 1)
        with archive.open("rb") as stream:
            archive_hash = digest(stream)
        assert archive_hash == target["archive_sha256"], "Archive digest: " + archive.name
        expected = {target["folder"] + "/" + f["path"]: f for f in target["files"]}
        assert len(expected) == len(target["files"]), "Duplicate manifest paths"
        for name in expected:
            p = pathlib.PurePosixPath(name)
            assert not p.is_absolute() and ".." not in p.parts and "\\" not in name, "Unsafe member name"
        seen = set()
        opener = zipfile.ZipFile if archive.suffix == ".zip" else tarfile.open
        with opener(str(archive), "r") as packed:
            entries = packed.infolist() if isinstance(packed, zipfile.ZipFile) else packed.getmembers()
            for entry in entries:
                is_zip = isinstance(packed, zipfile.ZipFile)
                if entry.is_dir() if is_zip else entry.isdir():
                    continue
                name = entry.filename.replace("\\", "/") if is_zip else entry.name
                assert name not in seen, "Duplicate archive member: " + name
                assert name in expected, "Unlisted archive member: " + name
                seen.add(name)
                if not is_zip:
                    assert entry.isfile(), "Archive links are not supported: " + name
                    if name == target["folder"] + "/" + target["binary"]:
                        assert entry.mode & 0o111, "Linux binary is not executable"
                size = entry.file_size if is_zip else entry.size
                assert size == expected[name]["bytes"], "Member size: " + name
                with packed.open(entry) if is_zip else packed.extractfile(entry) as stream:
                    assert digest(stream) == expected[name]["sha256"], "Member digest: " + name
        assert seen == set(expected), "Missing archive members: " + str(set(expected) - seen)
        reports.append(dict(target=target["target"], archive=archive.name,
                            sha256=archive_hash, files_checked=len(seen), passed=True))
    return dict(version=version, commit=manifest["git_revision"], tag=manifest.get("tag"),
                dirty=manifest["working_tree_dirty"], targets=reports, passed=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder")
    parser.add_argument("--version", required=True)
    parser.add_argument("--allow-dirty", action="store_true", help="Only for a verification candidate")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    result = verify(args.folder, args.version, args.allow_dirty)
    pathlib.Path(args.out).write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result))
