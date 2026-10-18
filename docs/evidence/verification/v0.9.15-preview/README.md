# Critterweight v0.9.15 local preview verification

This local Windows preview fixes two issues: saved monitor selection now survives settings reload and is reapplied after startup window placement; menu focus uses one soft tick_001.ogg cue at -14 dB with fixed pitch.

The build came from clean commit e699e9d on local branch preview/v0.9.15. It is version 0.9.15, has no release tag, and has not been published. The Windows executable is B:\Critterweight\release-work\v0.9.15-preview\Critterweight-0.9.15-preview.exe (165,003,144 bytes; SHA-256 cbca232068b5506f0e4db0ea6c5fcc5f50dc9aca8126c8caac25d08a80b7df47). Its digest matches the package output.

## Automated checks

- Godot 4.5.1 import completed; source check: 394 scripts, 0 failures.
- Source regressions: settings 3 passed, audio 11 passed.
- Deterministic audio rebuild check: all 636 generated files matched.
- Packaged Windows script check: 394 scripts, 0 failures.
- Packaged settings regressions: 3 run, 2 passed, 1 source-only skip, 0 failures.
- Packaged audio regressions: 11 run, 9 passed, 2 source-only skips, 0 failures.

The successful package checks used headless mode. Physical multi-monitor behavior and the final sound choice still need the owner's hands-on verification. See the attached JSON results and runtime logs.
