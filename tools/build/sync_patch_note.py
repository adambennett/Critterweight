"""Writes (or refreshes) the in-game patch note for a release from its release notes.

game/assets/data/patch_notes.json is the offline patch-notes archive shown in the game (newest
first; test_preview_0915 asserts the newest entry is this build's version). The body is the release
notes markdown, the same text the GitHub release uses.

    python -B tools/build/sync_patch_note.py 0.9.17 docs/releases/v0.9.17.md [--date 2026-10-21]
"""
import argparse, json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ARCHIVE = ROOT / 'game/assets/data/patch_notes.json'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('version')
    ap.add_argument('notes', type=Path)
    ap.add_argument('--date', default='')
    a = ap.parse_args()
    tag = 'v' + a.version
    body = a.notes.read_text(encoding='utf-8').strip() + '\n'
    date = (a.date or datetime.now(timezone.utc).strftime('%Y-%m-%d')) + 'T00:00:00Z'
    data = json.loads(ARCHIVE.read_text(encoding='utf-8'))
    entry = {'date': date, 'tag': tag, 'title': 'Critterweight ' + a.version, 'body': body}
    for previous in data:
        if not previous.get('title'):
            previous['title'] = 'Critterweight ' + str(previous.get('tag', '')).lstrip('v')
    if data and data[0].get('tag') == tag:
        entry['date'] = data[0].get('date', date) if not a.date else date
        data[0] = entry
        what = 'refreshed'
    else:
        if any(e.get('tag') == tag for e in data):
            raise SystemExit('%s exists below the newest entry; refusing to reorder the archive' % tag)
        data.insert(0, entry)
        what = 'added'
    with open(ARCHIVE, 'w', encoding='utf-8', newline='\n') as f:     # Python 3.8: no newline= on write_text
        f.write(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    print('%s %s (%d entries)' % (what, tag, len(data)))


if __name__ == '__main__':
    main()
