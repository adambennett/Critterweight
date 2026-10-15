"""Requirement/evidence digest from docs/REQUIREMENTS.md.

Prints a compact table (ID, state, requirement, evidence) and counts per state, so the final audit can
show every row at once. States: I = implemented, T = automated test, V = verified at runtime in the
packaged build, W = waived/external gap allowed by the brief, X = partial with a recorded gap,
~ = in progress, - = not started.

    python tools/verify/ledger_digest.py [--open] [--md out.md]

--open lists only rows that are not at least "I T" or explicitly waived.
"""
import io
import re
import sys
from collections import Counter

ROW = re.compile(r"^\| ([A-Z]+-\d+) \| (.*?) \| (.*?) \| (.*?)\|\s*$")


def rows(path="docs/REQUIREMENTS.md"):
    out = []
    with io.open(path, encoding="utf-8") as f:
        for line in f:
            m = ROW.match(line.rstrip("\n"))
            if m:
                out.append({"id": m.group(1), "req": m.group(2).strip(), "state": m.group(3).strip(), "evidence": m.group(4).strip()})
    return out


def is_open(state):
    s = set(state.replace(",", " ").split())
    if "W" in s:
        return False
    return not ("I" in s and ("T" in s or "V" in s))


def main(argv):
    only_open = "--open" in argv
    md_out = argv[argv.index("--md") + 1] if "--md" in argv else ""
    rs = rows()
    counts = Counter(r["state"] for r in rs)
    lines = ["| ID | State | Requirement | Evidence |", "|---|---|---|---|"]
    for r in rs:
        if only_open and not is_open(r["state"]):
            continue
        ev = r["evidence"] if len(r["evidence"]) <= 220 else r["evidence"][:217] + "..."
        req = r["req"] if len(r["req"]) <= 90 else r["req"][:87] + "..."
        lines.append("| %s | %s | %s | %s |" % (r["id"], r["state"] or "-", req, ev))
    summary = "%d rows; states: %s; open: %d" % (len(rs), ", ".join("%s=%d" % (k or "-", v) for k, v in sorted(counts.items())),
                                                 sum(1 for r in rs if is_open(r["state"])))
    text = summary + "\n\n" + "\n".join(lines) + "\n"
    if md_out:
        with io.open(md_out, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
    sys.stdout.buffer.write(text.encode("utf-8"))


if __name__ == "__main__":
    main(sys.argv[1:])
