"""Create a .tar.gz of a Linux build folder with POSIX executable permissions on the binary.

Windows filesystems do not carry the executable bit, so Linux archives are assembled here with
explicit modes: the named binary (and any *.sh) get 0755, everything else 0644.
Usage: python make_tar.py <folder> <out.tar.gz> <binary-name>
"""
import os
import sys
import tarfile


def main() -> int:
    folder, out, binary = sys.argv[1], sys.argv[2], sys.argv[3]
    base = os.path.basename(os.path.normpath(folder))
    with tarfile.open(out, "w:gz") as tar:
        for dirpath, _dirs, files in os.walk(folder):
            for name in sorted(files):
                full = os.path.join(dirpath, name)
                rel = os.path.relpath(full, folder).replace("\\", "/")
                info = tar.gettarinfo(full, arcname=f"{base}/{rel}")
                info.mode = 0o755 if (name == binary or name.endswith(".sh")) else 0o644
                info.uid = info.gid = 0
                info.uname = info.gname = "root"
                with open(full, "rb") as fh:
                    tar.addfile(info, fh)
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
