"""Download and verify an already published Critterweight GitHub prerelease.

Uses the existing gh login. Never creates or edits a remote release/tag. Verifies
the annotated remote tag, exact source commit, all seven uploaded digests, the
checksum list, every archived member, and the standalone Windows executable.
Only replaces an incomplete/mismatched expected download in the chosen folder.
"""
import argparse
import hashlib
import json
import pathlib
import re
import subprocess
from datetime import datetime, timezone

from package_archives import verify as verify_archives


def file_sha(path):
    sha = hashlib.sha256()
    with pathlib.Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            sha.update(chunk)
    return sha.hexdigest()


def expected_names(version):
    return {
        "Critterweight-" + version + "-windows-x64.exe",
        "Critterweight-" + version + "-windows-x64.zip",
        "Critterweight-" + version + "-server-windows-x64.zip",
        "Critterweight-" + version + "-linux-x86_64.tar.gz",
        "Critterweight-" + version + "-server-linux-x86_64.tar.gz",
        "BUILD_MANIFEST.json", "SHA256SUMS.txt",
    }


def validate_release(release, version):
    assert release["tag_name"] == "v" + version, "Unexpected release tag"
    assert not release["draft"] and release["prerelease"], "Expected a published 0.9.x prerelease"
    assert release["published_at"], "Release has not been published"
    assets = release["assets"]
    assert len(assets) == 7, "Expected exactly seven release assets"
    assert {a["name"] for a in assets} == expected_names(version), "Wrong release assets"
    for asset in assets:
        assert asset["state"] == "uploaded" and asset["size"] > 0, "Incomplete asset"
        assert re.fullmatch(r"sha256:[0-9a-f]{64}", asset.get("digest", "")), "Missing GitHub SHA-256"


def validate_checksums(folder, assets):
    listed = {}
    for line in (folder / "SHA256SUMS.txt").read_text(encoding="utf-8-sig").splitlines():
        match = re.fullmatch(r"([0-9a-fA-F]{64})  ([^/\\]+)", line)
        assert match, "Malformed checksum line"
        digest, name = match.groups()
        assert name not in listed, "Duplicate checksum filename"
        listed[name] = digest.lower()
    assert set(listed) == {a["name"] for a in assets} - {"SHA256SUMS.txt"}, "Incomplete checksum list"
    for name, digest in listed.items():
        assert file_sha(folder / name) == digest, "Checksum mismatch: " + name


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--commit", required=True, help="Full 40-character tested source commit")
    parser.add_argument("--repo", default="adambennett/Critterweight")
    parser.add_argument("--downloads", required=True, type=pathlib.Path)
    parser.add_argument("--out", required=True, type=pathlib.Path)
    parser.add_argument("--gh", default="gh")
    args = parser.parse_args()
    assert re.fullmatch(r"0\.9\.\d+", args.version), "Expected a normal 0.9.x release"
    assert re.fullmatch(r"[0-9a-f]{40}", args.commit), "Supply the full tested commit"
    assert re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repo), "Invalid repository"

    def api(endpoint):
        result = subprocess.run([args.gh, "api", "repos/" + args.repo + endpoint],
                                check=True, stdout=subprocess.PIPE, encoding="utf-8", timeout=120)
        return json.loads(result.stdout)

    tag_name = "v" + args.version
    release = api("/releases/tags/" + tag_name)
    validate_release(release, args.version)
    ref = api("/git/ref/tags/" + tag_name)
    assert ref["object"]["type"] == "tag", "Remote tag must be annotated"
    tag = api("/git/tags/" + ref["object"]["sha"])
    assert tag["tag"] == tag_name and tag["object"]["type"] == "commit", "Unexpected tag target"
    assert tag["object"]["sha"] == args.commit, "Tag differs from the tested commit"

    args.downloads.mkdir(parents=True, exist_ok=True)
    downloads = []
    for asset in release["assets"]:
        path = args.downloads / asset["name"]
        expected_sha = asset["digest"].split(":", 1)[1]
        if not path.is_file() or path.stat().st_size != asset["size"] or file_sha(path) != expected_sha:
            subprocess.run([args.gh, "release", "download", tag_name, "--repo", args.repo,
                            "--pattern", asset["name"], "--dir", str(args.downloads), "--clobber"],
                           check=True, timeout=900)
        assert path.stat().st_size == asset["size"], "Download size: " + path.name
        assert file_sha(path) == expected_sha, "Download digest: " + path.name
        downloads.append(dict(name=path.name, bytes=path.stat().st_size, sha256=expected_sha,
                              url=asset["browser_download_url"], passed=True))
        print("Verified download: " + path.name, flush=True)

    validate_checksums(args.downloads, release["assets"])
    manifest = json.loads((args.downloads / "BUILD_MANIFEST.json").read_text(encoding="utf-8-sig"))
    revision = manifest["git_revision"]
    assert re.fullmatch(r"[0-9a-f]{7,40}", revision) and args.commit.startswith(revision), "Wrong build source"
    archives = verify_archives(args.downloads, args.version)
    windows = next(t for t in manifest["targets"] if t["target"] == "Windows Desktop")
    binary = next(f for f in windows["files"] if f["path"] == windows["binary"])
    standalone = args.downloads / ("Critterweight-" + args.version + "-windows-x64.exe")
    assert file_sha(standalone) == binary["sha256"], "Standalone executable differs from the package"
    report = dict(version=args.version, commit=args.commit, annotated_tag=ref["object"]["sha"],
                  url=release["html_url"], published_at=release["published_at"], prerelease=True,
                  checked_at=datetime.now(timezone.utc).isoformat(), downloads=downloads,
                  archives=archives, standalone_matches_package=True, checksum_list_passed=True,
                  passed=True)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("Published release verified: " + release["html_url"], flush=True)


if __name__ == "__main__":
    main()
