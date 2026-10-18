# v0.9.15 preview 3 verification

2026-10-18. The entire previous playtest-fix, artwork and dialogue/name batch was completed
and packaged first; see ../v0.9.15-preview2/README.md for its full-suite and packaged evidence.
This increment adds P15-12, the editor-only Rooftop Canvas.

## Source checks

- 403 scripts compile, zero failures.
- Arena integration/content/editor/hazards/validation: 61/61 pass, including nine canvas tests.
- Previous v0.9.15 regressions: 13/13 pass.
- Audio-related filter: 30/30 pass, including all nine recorded-speech tests and the canvas
  acoustic-profile assertion. All 764 voice clips/names remain present.
- AI observation contract: 9/9 pass; canvas rectangle boundary rays have separate coverage.
- No script/parse errors in the successful final runs; git diff --check is clean.

Canvas tests cover editor-only discovery, 12-64m independent dimensions, valid default
markers at all extreme sizes, empty platform/hazards, exact floor collision/open ledges,
existing disabled-ringout guards, real falling/returning fighters at all four edges,
controller width edits, inspector coordinates beyond 20m, editor camera distance, test-play
and return, save/load/export/import, undo/redo and out-of-bounds preservation, rooftop audio,
AI boundary perception and multi-angle camera framing at small/medium/large sizes.

Initial canvas-test authoring exposed a formatting error in an assertion and a headless audio
fixture missing its players. Those fixtures were corrected; final source JSON/log evidence
supersedes the initial runs. Existing networking negative tests intentionally log rejected
content/rules. The audio/hub run retains the previously recorded shutdown-only ObjectDB and
four-resource warning; no new runtime error is present in the successful verification logs.

## Build

Windows local preview export and packaged verification pending. No graphical launch, tag,
push or publication. Physical controller feel, real monitor placement, visual composition and
voice/music taste remain for the owner's playtest. All work and test user roots are on B:;
Godot jobs run sequentially at BelowNormal priority.
