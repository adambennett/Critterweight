"""Offline rejection checks for the release verification contract."""
import copy
import pathlib
import tempfile
import unittest

from published_release import expected_names, file_sha, validate_checksums, validate_release


class PublishedReleaseTests(unittest.TestCase):
    def setUp(self):
        self.release = dict(tag_name="v0.9.17", draft=False, prerelease=True,
                            published_at="2026-10-21T00:00:00Z", assets=[
                                dict(name=n, state="uploaded", size=1, digest="sha256:" + "0" * 64)
                                for n in sorted(expected_names("0.9.17"))])

    def test_accepts_complete_published_prerelease(self):
        validate_release(self.release, "0.9.17")

    def test_rejects_wrong_tag(self):
        self.release["tag_name"] = "v0.9.16"
        with self.assertRaises(AssertionError):
            validate_release(self.release, "0.9.17")

    def test_rejects_draft_or_wrong_release_kind(self):
        for key, value in (("draft", True), ("prerelease", False), ("published_at", None)):
            release = copy.deepcopy(self.release)
            release[key] = value
            with self.assertRaises(AssertionError):
                validate_release(release, "0.9.17")

    def test_rejects_missing_duplicate_or_extra_assets(self):
        for assets in (self.release["assets"][:-1], self.release["assets"] + [self.release["assets"][0]],
                       self.release["assets"][:-1] + [self.release["assets"][0]]):
            release = copy.deepcopy(self.release)
            release["assets"] = assets
            with self.assertRaises(AssertionError):
                validate_release(release, "0.9.17")

    def test_rejects_incomplete_or_undigested_upload(self):
        for key, value in (("state", "new"), ("size", 0), ("digest", ""), ("digest", "sha256:bad")):
            release = copy.deepcopy(self.release)
            release["assets"][0][key] = value
            with self.assertRaises(AssertionError):
                validate_release(release, "0.9.17")

    def test_checksums_require_exact_names_and_content(self):
        with tempfile.TemporaryDirectory(prefix="cw-release-fixture-") as temp:
            folder = pathlib.Path(temp)
            names = expected_names("0.9.17") - {"SHA256SUMS.txt"}
            for name in names:
                (folder / name).write_bytes(b"fixture")
            lines = [file_sha(folder / name) + "  " + name for name in sorted(names)]
            sums = folder / "SHA256SUMS.txt"
            sums.write_text("\n".join(lines) + "\n", encoding="utf-8")
            validate_checksums(folder, self.release["assets"])
            for invalid in (lines[:-1], lines + [lines[0]], [lines[0][:64] + "  ../escape"] + lines[1:]):
                sums.write_text("\n".join(invalid) + "\n", encoding="utf-8")
                with self.assertRaises(AssertionError):
                    validate_checksums(folder, self.release["assets"])
            sums.write_text("\n".join(lines) + "\n", encoding="utf-8")
            (folder / sorted(names)[0]).write_bytes(b"changed")
            with self.assertRaises(AssertionError):
                validate_checksums(folder, self.release["assets"])


if __name__ == "__main__":
    unittest.main()
