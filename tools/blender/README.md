# Blender on this machine

Verified on **2026-10-16** during the creature art revamp. This is a practical handoff for future agents and artists using this Windows PC. It separates machine setup from Critterweight's asset contract. For the project art specification, export details and provenance, read [ART_PIPELINE.md](../../docs/ART_PIPELINE.md); for results and known gaps, read [ART_REVAMP.md](../../docs/ART_REVAMP.md).

## Start here

Use the existing installation and isolated B: workspace. Do not reinstall Blender or download dependencies just to export these models. The MCP bridge is optional: ordinary Blender plus Node can rebuild every adopted GLB from its committed source.

- Blender: `B:\Blender\blender.exe`, **5.2.2 LTS**, build `d13f752e3b9c` (2026-09-15).
- Bundled Python: `B:\Blender\5.2\python\bin\python.exe`, Python 3.13. The machine's older system Python was not used for this bridge.
- Art clone: `B:\Critterweight-art\PokeMMA-art`, branch `art/creature-revamp`.
- Editable sources that ship: `tools/blender/*.blend` in that clone. They are saved with compression.
- Local working scenes/iterations: `B:\Critterweight-art\blender`.
- Concept PNG masters: `B:\Critterweight-art\concepts`; raw Godot captures and logs: `B:\Critterweight-art\captures`.
- Tool installation/profile/caches: `B:\Critterweight-art\tools`.
- Temporary data: `B:\Critterweight-art\tmp`; isolated test data: `B:\Critterweight-art\test_root`.
- Godot: `C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe` for headless work; the executable without `_console` for windowed captures.

These are verified paths, not universal installation defaults. Recheck them after software upgrades. Use a separate approved root and bridge port for another project; do not put its work in this art clone or another agent's checkout.

## Keep files and caches on B:

From a new PowerShell session, for ordinary art work:

```powershell
Set-Location 'B:\Critterweight-art\PokeMMA-art'
Get-PSDrive C
. .\tools\blender\art_env.ps1
Set-ArtRuntimePaths
```

[art_env.ps1](art_env.ps1) sets process-local `TEMP`/`TMP`, uv/pip/npm caches, Python bytecode cache and Blender profile paths under the art root. `Set-ArtRuntimePaths` also redirects runtime AppData and other caches to B:. It lowers the shell priority to BelowNormal. These settings affect processes launched from that shell; an already-running Blender or a desktop shortcut does not inherit later changes.

Important Blender profile variables are `BLENDER_USER_CONFIG`, `BLENDER_USER_SCRIPTS`, `BLENDER_USER_DATAFILES` and `BLENDER_EXTENSIONS`. Their directories are under `B:\Critterweight-art\tools\blender-profile`. Keep this project profile separate from the user's normal Blender preferences.

In the art profile, Preferences > File Paths > Temporary Files is `B:\Critterweight-art\tmp\`. Temporary autosaves are enabled every **3 minutes**, and one previous save version is retained. Autosave does not replace an explicit save of the editable source. `.blend1` and Python bytecode are ignored by the source folder's Git rules; keep iterations and larger bakes outside the committed source folder.

For a one-off command using bundled Python, either inherit `PYTHONPYCACHEPREFIX` from the environment helper or use `python.exe -B`. Importing a Python module can otherwise create `__pycache__` beside it, even when the script only reads data. Put virtual environments and package-download caches under the project root before installing anything.

Check C: free space before and after large jobs. During this task, C: also changed because of separate work; diagnose attribution rather than deleting another task's files. The art task's threshold was roughly 200 MB of attributable C: consumption. The built-in image generator had a specifically approved exception: one small C: staging image at a time, immediately moved to B:. That exception is not blanket permission for future downloads or caches.

## Normal edit and export loop

1. Open a committed `.blend` using the B: environment above. For hands-on editing, launch the Blender UI with the desired source file. Save edits back to that source, with compression enabled. Save experiments and large sculpts separately under the working `blender` directory.
2. Keep the hidden `REFERENCE - original forge mesh (not exported)` collection for registration. Edit the `EDITABLE` collection. Do not regenerate the source just to export it.
3. Export one model through the wrapper, inspect it in Godot, then run the targeted checks:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/blender/rebuild.ps1 -Ids f_stoke
node tools/blender/audit_models.js --out B:\Critterweight-art\captures\model-audit.json
powershell -NoProfile -ExecutionPolicy Bypass -File tools/blender/check_art.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/blender/capture_art.ps1 -Phase after -Ids f_stoke
```

Omit `-Ids` from `rebuild.ps1` to export all adopted saved sources. The wrapper uses two Blender threads, checks exit codes and C: space, and writes logs under `captures`. Read the log if the export fails; do not infer success merely because a GLB already exists.

**`rebuild.ps1 -BuildSources` is a different operation.** It reconstructs the authored starting geometry from Python and overwrites the `.blend` and GLB for the selected IDs. It does not preserve later manual sculpt/model edits. Use it only when deliberately rebuilding that initial geometry, after saving any work worth keeping. It requires original forge GLBs in `-ReferenceRoot`; current Blender-owned GLBs are not the original reference set.

The historical forge path is `node tools/forge/forge.js --legacy --out <B:-scratch-folder>`. Normal forge builds preserve Blender-owned outputs, and explicitly requesting an adopted ID without `--legacy` is rejected. This ownership guard prevents a routine rebuild from silently undoing artist work.

The direct Blender export inside the wrapper is documented in [ART_PIPELINE.md §7](../../docs/ART_PIPELINE.md#7-blender-sources-and-export). Prefer the wrapper on this shared machine: a direct command does not acquire its coordination lock.

## What must survive a Critterweight export

This project is an active-ragdoll brawler. A fighter's motion comes from physics and move data; a Blender action cannot replace it. Bodies, stats, moves and poses belong to the gameplay owner.

- Game rest space is metres, +Y up, +Z forward, +X the creature's left. Game `(x, y, z)` maps to Blender `(x, -z, y)`. Import the original GLB and verify bone heads before modeling.
- Preserve one bone per body segment, its exact name and pivot. The exporter checks the saved body hash and bone heads. A changed hash is a registration-review signal, not permission to rewrite gameplay JSON or regenerate the rig automatically.
- Exported objects have custom property `cw_role`: `body`, `gore` or `rig`. Only body/gore meshes ship. References, cameras and lights stay out. The gore piece must remain unskinned.
- Preserve scene metadata `cw_id`, `cw_bones`, `cw_body_sha256`, mesh vertex groups and material `cw_material` metadata. They are part of this exporter, not generic Blender conventions.
- `Color` is the mesh colour attribute. RGB is **linear albedo**; alpha is the **Hype glow mask**, not transparency. The helpers convert palette sRGB hex values to linear colour. Do not accidentally paint all alpha to 1 or all glow to 0.
- Keep a material named `team`. Emissive material hints enable the runtime glow mask. `detail_` materials still receive all creature effects but omit the inflated outline pass, which otherwise overwhelms small eyes and mouth details.
- Use at most four normalized influences per vertex; the delivered models use at most two. Broad surfaces stay rigid to their segment, with soft blending only around joints.
- Apply geometry modifiers before saving an export source. The exporter rejects non-armature modifiers and shape keys; it does not silently bake them or export expressions. Adding either export feature requires deliberate pipeline and view support.
- Count **body plus gore** triangles: fighters 6–30k (raised from 12k for the v0.9.17 roster pass), bosses at most 25k, minions at most 2k. These sources use no textures. If adding textures later, revisit the runtime shader/import contract and the one-1024-atlas fighter limit.

Use [export_creature.py](export_creature.py), not an arbitrary File > Export preset, for these assets. It extracts rest geometry and vertex colours and delegates GLB writing to the project's deterministic writer. The saved sources are the normal rebuild inputs; the source-generation scripts are a reproducible starting point and reference for construction.

## Local MCP bridge: what is installed and how it works

The installed free bridge is **mcp-for-blender 2.1.9**, MIT, from [ahujasid/mcp-for-blender](https://github.com/ahujasid/mcp-for-blender), pinned during setup to `7a0373ec9199183cb460068c4f96aed9c579fb4f`. The connected add-on reports **1.8**, protocol **13**, matching the server. Those are separate version numbers.

Machine-local components, not committed dependencies:

- Source checkout: `B:\Critterweight-art\tools\blender-mcp`.
- Python dependencies: `B:\Critterweight-art\tools\bridge-venv\Lib\site-packages`.
- Blender add-on: the art profile's `scripts\addons\blender_mcp` directory.
- Startup scene: `B:\Critterweight-art\blender\art-startup.blend`.
- Preference setup: `B:\Critterweight-art\tools\setup-blender.py`.
- Background Blender adapter: `B:\Critterweight-art\tools\headless-bridge.py`.
- MCP stdio wrapper: `B:\Critterweight-art\tools\bridge-server.py`.
- Logs: `blender-headless.stdout.log`, `blender-headless.stderr.log` and bridge setup/smoke files under `tools`.

The Codex entry is named `critterweight_blender_art` in the existing user config at `C:\Users\eX_Di\.codex\config.toml`. It runs bundled Python with `bridge-server.py --host 127.0.0.1 --port 9877`; that wrapper loads the B: dependency directory. The entry also supplies B: temp/bytecode paths and disables telemetry. A pre-edit config backup remains on B:. Do not replace the entire Codex configuration or other MCP entries when repairing this one.

There are **two processes/protocols**: Codex starts the stdio MCP server; it talks to the Blender add-on over local TCP **127.0.0.1:9877**. The socket listener must exist in Blender for tools to work. Do not expose this unrestricted Python-control socket on the LAN, and do not start another bridge on the same port. Inspect an existing listener and its owning process before restarting anything; a saved PID can become stale. Never kill every process named Blender.

### Hidden-window issue and the headless adapter

A hidden GUI Blender on this host did not reliably advance the add-on's normal GUI timers. A socket connection could therefore exist while commands waited without being executed. The local `headless-bridge.py` keeps the upstream protocol but drains its command queue on Blender's main thread. It has an explicit idle loop and no render, download or remote-service action at startup.

For an intentional restart, first confirm the art listener is absent, then start only this bridge using the B: environment. Example for the existing machine-local files:

```powershell
# Run only when no art bridge is already listening on 127.0.0.1:9877.
. .\tools\blender\art_env.ps1
Set-ArtRuntimePaths
$artBridge = Start-Process -FilePath 'B:\Blender\blender.exe' -ArgumentList @(
  '-b', 'B:\Critterweight-art\blender\art-startup.blend', '-t', '2',
  '--python-exit-code', '1', '--python', 'B:\Critterweight-art\tools\headless-bridge.py'
) -WindowStyle Hidden -PassThru `
  -RedirectStandardOutput 'B:\Critterweight-art\tools\blender-headless.stdout.log' `
  -RedirectStandardError 'B:\Critterweight-art\tools\blender-headless.stderr.log'
$artBridge.PriorityClass = 'BelowNormal'
```

Look for `ART_BRIDGE_READY 127.0.0.1:9877` in the output log. Then call `get_addon_status`, `get_scene_info`, and a small read-only `execute_blender_code` request. These calls were rechecked for this guide. Do not treat an open port alone as proof that Blender is processing commands. Normal interactive viewport screenshots are not guaranteed by this background adapter; use the Blender UI for hands-on editing and the Godot capture path for runtime appearance.

The source archive omitted `blender_mcp/config.py`, which broke status reporting. The two local Python package copies were repaired with disabled telemetry configuration and empty service credentials. Details are in `B:\Critterweight-art\tools\bridge-setup-notes.txt`. This is a local compatibility repair, not an upstream guarantee; re-evaluate it before an upgrade rather than copying it blindly. Do not run a generic `uvx ...` update from an unconfigured shell: it can download tools into default locations and change the tested version.

All optional asset libraries, AI 3D generators, premium integrations and telemetry are **off**. No third-party creature meshes or bridge-provided assets were used. A tool advertising an integration is not authorization to use or pay for it. No other Blender add-ons were needed for this work.

### Practical MCP/Python habits

- Read the scene and current file before editing. `execute_blender_code` acts on the live scene and has the full `bpy` API. Source-building code clears its scratch scene; never paste that operation into an artist's unsaved live file.
- Work in small steps, print useful results and save deliberately. A timeout is not proof that an operation did nothing; inspect the scene/log before repeating it. Use batch Blender for long, repeatable exports.
- Look shader nodes up by type, not localized display names. Set shader input values for rendered materials; `material.diffuse_color` alone describes viewport display colour.
- Inspect actual Blender RNA enums/current values instead of copying version-specific identifiers. In this build the live engine is `BLENDER_EEVEE`; assumptions from older Blender versions can fail.
- The bridge tool's `user_prompt` field carries the user's actual instruction. Keep that verbatim for a multi-step operation, rather than inventing a subgoal as if it came from the user.
- Keep bridge diagnostics separate from asset reproducibility. A working MCP session is convenient, but the committed source and batch exporter must stand on their own.

## CPU coordination and test safety

Only one heavy job at a time. Do not render, bake, remesh, capture or benchmark during a full suite. The wrappers resolve the **user-level default TEMP** independently of redirected art temp and acquire `critterweight_full_suite.lock` there. This matters: an early helper inherited B: TEMP and accidentally used a different lock location. The corrected wrappers all share the real machine lock.

The full suite has an intentional exception to ordinary B: temp redirection. Start a **fresh shell with its default TEMP unchanged** and run:

```powershell
Set-Location 'B:\Critterweight-art\PokeMMA-art'
powershell -NoProfile -ExecutionPolicy Bypass -File tools/blender/final_suite.ps1
```

Do not first dot-source the ordinary art environment in that shell: child shells inherit its redirected TEMP. [final_suite.ps1](final_suite.ps1) validates the real isolated B: test root, preserves default TEMP and calls `tools/dev/run_suite.ps1` without a filter. During development, [check_art.ps1](check_art.ps1) imports, checks compilation and calls that same runner with the content/asset/cosmetic filters. Never run the game's tests directly to bypass coordination.

For another project, adopt the separation between output/cache directories and a shared coordination lock. Do not copy Critterweight's lock or test-root cleanup rules into an unrelated project without understanding their ownership.

## What the art work taught us

**Establish ownership and reproducibility early.** Hash the original outputs, rebuild them, then take one asset through source, export, import, live capture and tests before multiplying the approach across a cast. Keep editable sources even when the runtime file is small. Test export from the saved source, not only from an in-memory authoring session. [verify_exports.ps1](verify_exports.ps1) does that; [verify_forge.ps1](verify_forge.ps1) checks retained ownership.

**Model to gameplay envelopes.** Attractive concepts can propose wings, crests or props well outside the hit volumes. Narrow those visual forms rather than quietly extending gameplay reach. Use collision overlays and motion as well as rest renders. The audit's distance to the union of colliders is only a vertex diagnostic: it cannot prove triangle interiors, correct weighting or every combat pose.

**Faces need clean contrast more than extra geometry.** Clear eyelids/pupils, a readable muzzle and crisp colour regions helped more than inflated overlapping detail. Small facial outlines became heavy black blobs, so the view now omits that pass on detail materials while retaining the shared effects. Keep the overall silhouette readable at 48 px.

**Cosmetics depend on mesh sampling.** Dredge's sparse shell samples and Jitters' raised coil changed automatic accessory fitting. More appropriate shell rings/cap-centre samples and a coil fitted to the body fixed it while preserving the unchanged cosmetic tests. A decorative addition can affect a mesh-driven attachment even if it never collides.

**Low-resolution and motion reviews reveal different problems.** A model can look good in a close-up yet lose its signature in an eight-fighter view. Review team colours, Hype, JUICE, flash, status, bruises and detached pieces, then actual fights. Four sampled poses are evidence, not exhaustive move coverage. Existing cage/HUD occlusion remained outside the art scope and is recorded for the gameplay owner.

**Make captures repeatable.** Use the same camera, yaw, lighting and shared before/after crop. Standalone Godot previews must wait for autoloads; world-space cosmetic transforms must match placement; set Hype before rendering. Supply both engine resolution and the game's size/windowed settings. Five seconds can capture the introduction, while Blister's self-pop can end a duel before twenty seconds. Focus-loss pausing produced repeated frozen frames; the helper now disables it only in its scratch profile through Settings/Saves. Check actual pixels, not just successful exit codes.

**Use the compatible evidence shell.** The current System.Drawing packaging helper works with Windows PowerShell 5.1 (`powershell.exe`). PowerShell 7's runtime produced a Bitmap/type-forwarding Add-Type failure. Use `powershell -File tools/blender/package_evidence.ps1`; do not install random drawing packages to paper over that mismatch. JPEGs are modest review copies; retain raw PNGs and crop/source-hash records.

**Benchmark consecutive comparisons, and keep slow runs.** Separated before/after measurements suggested a regression. A locked original/new/new/original sequence with two runs per preset reduced that timing ambiguity. The paired aggregates showed no regression, but shared-machine variation was large. Record hardware, scene, seed, warmup, duration, preset and all raw runs. A desktop Deck preset is not Steam Deck hardware validation; a mean of run p95 values is not a pooled p95.

**Report diagnostics without overstating them.** The final merged-main suite passed 684/684, but printed a Jolt job-limit warning and five-resource shutdown diagnostics also present in earlier packaged-test evidence. Preserve that context. Passing tests, a correct import, attractive stills and user playtest approval are different pieces of evidence.

**Treat generated sheets as art direction, not geometry truth.** Validate front/side/three-quarter consistency; the Kid Lamprey sheet needed a corrected turnaround. Save exact prompts, dates, tool/model disclosure, terms and source hashes. If a service does not expose its model ID, say so. Keep original creature design separate from licensed material inputs, and record any future external assets before committing them.

## Handoff and portability

The portable deliverables are the twelve compressed `.blend` files, source/export helpers, GLBs, evidence and provenance in this repository. The B: bridge installation, profile, caches, raw concepts and working iterations are local supporting data. Avoid absolute machine paths in a new project's core asset format; keep them in launch/configuration layers.

The art draft PR is [Creature art revamp #1](https://github.com/adambennett/PokeMMA/pull/1). Main's notes request a separate alternate preview build for the user's comparison before merging. Claude owns that integration and release step. This guide was added after the successful full suite; it changes documentation only.
