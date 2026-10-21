# Critterweight v0.9.17 verification

**Scope:** the owner's v0.9.17 specification (`Version 17 and 18 Updates.md`, first release):
commentary overhaul, full-roster art with expressions and secondary motion, the "Legacy Varga skin"
option, and new ability effects for every fighter. Gameplay is unchanged. Ledger rows C17-01..05,
ART-10, ART-11, VFX-01, SAV-04 (docs/REQUIREMENTS.md). Checklist:
[docs/releases/v0.9.17-v0.9.18-checklist.md](../../../releases/v0.9.17-v0.9.18-checklist.md).

Machine: Windows 10 (19045), i7-7700K, RTX 4070 Ti Super, Godot 4.5.1 (official), Blender 5.2.2.
Networking is loopback on this PC.

## Baseline (before the work)

- `main` = `origin/main` = `0465a05` (v0.9.16 published, tag `v0.9.16`), clean; playable roster
  Stoke, Dredge, Gusto, Dozer, Slurry, Jitters, Varga, Knell. A detached checkout of `0465a05`
  (`B:\Critterweight-work\baseline-src`) produced every "before" capture and measurement below.

## Commentary

COMMENTARY_RESULTS

## Recorded speech

521 clips installed (426 Devon, 93 Kendall, 2 Coach Buck; 33.7 min; mono 16-bit 24 kHz), every WAV
matching its catalog SHA-256. The technical speech audit (`tools/audio/breeze/audit_speech.py`:
levels, clipping, endings, pauses, pace, pitch range; heuristics, not listening) flagged 51 of the
521 new clips; 19 were retaken with direction notes (four cut-off endings, four flat deliveries on
big calls, three long pauses, the eight fastest deliveries), one retake was rejected and replaced by
a second take, and one had a stray sound after 0.4 s of digital silence trimmed. After the retakes
the four endings close at -67 to -99 dB, the pauses are under 0.4 s and the fastest lines dropped
from 26–30 to 17–25 characters per second. Breeze total for the goal: 3,255.8 of 10,000 credits
(provider report in docs/audio/breeze/v0.9.17/budget-final.json). Nothing was listened to by a
person in this session; listening approval remains with the owner.

## Fighter art

All eight playable fighters were rebuilt (docs/ART_REVAMP.md, v0.9.17 section): every model binds
the unchanged segment skeleton, passes `audit_models.js` (30k budget: 26.4k–29.8k triangles), the
art tests (`test_new_fighters`, `test_hub_cosmetics`, `test_content_audit`) and rebuilds
byte-identically from its committed source. Before/after images: [art/](art/) (front and back
comparisons and face close-ups per fighter). ROSTER_WALL

## Legacy Varga skin

`test_varga_skins` (6/6): the legacy model is the v0.9.16 file byte for byte
(sha256 `4fa78a8a…0460fc`), the upgraded model is the default, the setting persists, its Settings row
is a controller focus stop that toggles with A, previews/matches swap live with the same body, and
Varga's gameplay data and the content hash are identical under both skins. VARGA_CAPTURES

## Ability effects

`test_ability_vfx` (5/5): the simulation's effect events carry the true footprint (cone angle, line
length/width, ring radii, origin) and the drawn decals use exactly those numbers; every fighter's
events and entities are drawn and cleaned up; JUICE auras follow JUICE; Low quality drops light
flashes and thins particles; Reduce flashing dims flashes; the new event fields reach online
clients. Before/after showcase: 40 shots (five per fighter: both abilities, JUICE, the charged heavy
or Varga's heavy, an elemental reaction), each at the same simulation times in v0.9.16 and v0.9.17:
[vfx/](vfx/) holds one overview strip per fighter. VFX_NOTES

## Saves

`test_saves_from_older_build` (3/3): an Off the Street run, a Career after a bout, settings and a user
rules preset written by the v0.9.16 checkout load in v0.9.17; the run's decision log still rebuilds it
and it plays on to the end; the career books its next bout; the settings keep their values with the
new option at its default.

## Performance

PERF_RESULTS

## Source checks

SUITE_RESULTS

## Packaged checks

PACKAGED_RESULTS

## Bug hunt

BUG_HUNT

## Not verified

- No human listening review of the new recordings and no human or physical-controller playtest.
- Online play only over loopback.
- Linux packages are built but not run.
