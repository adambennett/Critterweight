# AI Lab — user guide and technical reference

The AI Lab trains fighting policies **on this PC, inside the game**, against the real combat rules.
Two real learning approaches ship (evolution strategies from rewards, behaviour cloning from
recorded play) plus their combination; trained policies are versioned files you can fight,
spectate, evaluate, export and import. Requirements: LAB-01…LAB-10 in `docs/REQUIREMENTS.md`.
Proof-of-learning experiments and numbers: `docs/evidence/lab/README.md`.

Honest scope: learning is real (weights change from experience and measurably improve play on
held-out episodes), but strength grows with training time. Short runs learn habits such as
"close the distance and string jabs"; nothing promises a policy that beats strong humans.

---

## 1. Workflow in the game

Open the **AI Lab** screen (main menu → AI Lab; App screen `lab`). Three sample policies ship
with the game (`content/core/policies/`):

- *Drill Hitter (ES)*
- *Regular Clone (BC)*
- *Regular Clone + ES (Aggressive)*

Their training runs are in `docs/evidence/lab/`. Everything works with a
controller (D-pad/stick, A/B, **LB/RB** switch tabs) and with mouse/keyboard (**Q/E** or
**PageUp/PageDown** switch tabs; the footer prompts are clickable). The screen uses the shared
UiTheme text styles, so the text-size and UI-scale settings apply to it.

1. **Train** — choose the fighter, approach, objective/style (each reward weight is editable),
   training opponents and scenario, seed, network size, imitation dataset or starting policy,
   and limits (time, generations/epochs, episodes, worker processes, matches per worker, CPU
   share, low priority). *Start training* writes a job and launches a background worker.
2. **Runs** — every run with its state. Live: generation/epoch, episodes, elapsed vs limit,
   simulated time and speed, episodes/hour, workers alive, coordinator CPU utilisation and
   memory, current and best metrics, a learning curve (population reward and validation reward
   for ES; train/validation loss and accuracy for BC), the checkpoint list and the evaluation
   report. Buttons: Pause, Resume, Cancel (keeps the checkpoint), *Continue run* (after a
   stop, cancel or crash, from the newest checkpoint), *Save snapshot* (current best network
   into the library), Delete run (press twice).
3. **Policies** — the library (built-in + yours; invalid files are listed with the reason).
   Rename, Export to a file, Import (validation errors are shown), Delete (press twice),
   *Open policy folder*, *Evaluate vs baselines* (runs a separate evaluation job), **Fight this bot** (you vs the
   policy, choose your fighter) and **Spectate this bot** (policy vs a bot tier, a scripted
   drill or another policy).
4. **Recording** — *Record my matches for imitation learning* (off by default): while on, every
   match you play stores what you saw and did into the dataset "My <fighter> matches". You can
   also record a teacher bot headlessly, and rename/delete datasets.

The game never trains in its own process, so menus stay responsive (measured while a worker
trains: see `docs/evidence/lab/README.md`). Closing the game stops workers at their last
checkpoint ("interrupted"); *Continue run* picks them up again. When a completed run shows a
trained policy beating its baseline on held-out evaluation, the Lab unlocks the *Mad Scientist*
achievement (`Platform.unlock_achievement("ach_mad_scientist")`).

## 2. Training approaches

### 2.1 Evolution strategies (`kind: es`)
OpenAI-style ES (Salimans et al. 2017) on the flat network parameters θ:
mirrored Gaussian perturbations θ ± σε regenerated from per-pair seeds (worker processes rebuild
candidates from θ + seeds), every candidate plays the same training episodes (common random
numbers), fitness = mean episode reward → centred ranks → gradient estimate
Σ(r⁺−r⁻)ε/(2nσ) → Adam step with decoupled weight decay. No step is taken when every pair ties.

*Model selection.* ES optimises the noise-smoothed objective, so early on the mean θ can play
worse than its best perturbations. Every `eval.every` generations both θ and the generation's
best candidate ("elite") play the **validation** seeds; the best validated network is kept.
The final report evaluates the initial network and the selected one on separate **test** seeds
(and optionally a scripted reference on the same episodes).

*What it learns / why it fits.* It optimises any episode-level reward (damage, survival,
parries, taunts…) through the non-differentiable physics, needs no recordings, parallelises over
worker processes trivially, and works with the deterministic (argmax) policies used in matches.
Cost: many episodes; it learns coarse behaviours first (approach, attack rhythm, guarding).

### 2.2 Behaviour cloning (`kind: bc`)
Supervised learning of the act_v1 heads from recorded (observation, action) pairs:
masked cross-entropy on the move head and the button head (optionally class-balanced),
minibatch Adam + L2, validation split by **whole recorded episodes** (no temporal leakage),
early stopping on validation loss (best weights kept). After training the clone and — when the
dataset came from a scripted teacher — the teacher itself play the same test episodes; the report
compares outcomes and action distributions (total variation distance) next to the held-out
accuracy, the majority-class baseline and the untrained network.

*What it learns / why it fits.* A playstyle, directly from a few minutes of play (yours or a
bot's), with no reward design; fast on a CPU. It copies mistakes too and cannot exceed its
teacher on its own. BC policies sample their actions (`mode: sample`) to reproduce the teacher's
action frequencies.

### 2.3 Clone, then evolve (BC → ES)
An ES job with `model.init_policy` (a cloned policy id or file) starts from imitation and
improves it on an objective. Reported as approach `bc_es`.

## 3. Objectives / styles

Episode reward = Σ weight × raw term. Raw terms come only from the real simulation's events and
state (`src/lab/lab_rewards.gd`): `damage_dealt`, `damage_taken`, `hits`, `hits_taken`, `blocks`,
`parries`, `got_parried`, `counter_hits`, `knockdowns_dealt/taken`, `throws`, `taunts`,
`hype_gain`, `juice_used`, `approach` (potential-based: metres closed beyond 1.3 m, cannot be
farmed), `survival` (seconds), `win`/`loss`/`draw` (KO or decision at the time limit),
`ko_dealt/taken`.

| Preset | Intent | Main weights |
|---|---|---|
| Aggressive: damage | hit hard and often | damage_dealt 1, hits 0.5, knockdowns 3, KO 10, win 10, damage_taken −0.35, approach 0.5 |
| Defensive: survival | avoid damage | damage_taken −1.2, blocks 0.8, parries 3, survival 0.25/s, loss −15 |
| Technician | parries and counters | parries 4, counter_hits 2, throws 2, got_parried −1.5 |
| Showboat | play to the crowd | taunts 2, hype_gain 0.15, juice_used 8 |
| Win only | sparse | win 10, loss −10 |
| Drill: approach & hit | the controlled learning task | damage_dealt 1, hits 1, approach 0.5 |

## 4. Opponents, scenarios, seeds and evaluation

Fixed baselines (`src/lab/lab_opponents.gd`): standing dummy, patrolling dummy, scripted jabber,
scripted turtle, and the shipped BotBrain tiers Rookie / Regular / Pro / Champion (reaction
delays and mistakes; never omniscient). `policy:<file>` plays a saved policy.
Scenario presets (`src/lab/lab_scenarios.gd`): *Drill: standing dummy*, *Drill: patrolling
dummy*, *Sparring: jabber*, *Sparring: jabber + turtle*, *Bots: Rookie + Regular*, *Bots: Pro +
Champion*; every field can be overridden (opponents, round length, random vs standard spawns,
spawn distance, arena).

Every episode is a fresh physics world (SubViewport with its own World3D) running a real
`MatchSim` with the standard `MatchMode` (one round; KO or decision at the time limit). Two
rules differ from a broadcast match and are set through the normal rules dictionary: the
cosmetic intro is a 0.2 s settle (`intro_time`; round-start hooks still fire) and a tie at the
time limit is a draw (`sudden_death: false`) so every episode has a bounded length.

Seeds come from disjoint named streams: `train:<job seed>:<generation>:<k>`,
`val:<job seed>:<i>` (model selection only) and `test:<job seed>:<i>` (final reports only).
Evaluation additionally plays the arena's standard corner spawns, a layout random-spawn training
never sees. Reports give n, mean ± std and 95 % CI of reward, damage dealt/taken and hits, and
win rate with a Wilson 95 % interval, per opponent — every evaluated episode counts, nothing is
cherry-picked. Evaluation jobs (`kind: eval`) compare a policy with a random network of the same
shape and/or a scripted reference on the same test episodes.

## 5. Contracts (used identically in training, recording and matches)

### obs_v1 — `src/ai/policy/policy_obs.gd` (118 floats, roughly in [−1, 1])
Only what a player can perceive. Fighter space: +Z toward the facing direction, +X = the
fighter's left.

| Indices | Block | Features |
|---|---|---|
| 0–36 | self | health, stamina, poise, hype, JUICE ready/active, crash; ability 1/2 ready + cooldown; state group one-hot (neutral, acting, guard, dodge, stunned, down, grabbing, held, other); own move progress / windup / active / cancel window / class (light, heavy, ability, grab), charge; root velocity (left, forward); airborne; evading; status count and speed / damage-taken / damage-dealt modifiers |
| 37–75 | target (lagged) | present, relative position (left, forward), distance, bearing sin/cos, the target's facing relative to us (sin/cos), its velocity, HUD bars (health, stamina, hype, JUICE, ability cooldowns), state group one-hot, move progress / windup / active / recovery / class / time to active frame, airborne, evading, status count and speed, its distance to the cage wall |
| 76–94 | environment | distances to walls/props along 8 rays, ring-out arena, other enemies (count, nearest distance), nearest hostile projectile (relative position and velocity, lagged), nearest hostile zone (distance, inside), round time left |
| 95–117 | history | previous move class one-hot (9), previous button class one-hot (12), recent damage taken / dealt |

Never observed: the opponent's inputs, input buffer, AI state, RNG or hidden timers. Opponent
features come from the previous decision's snapshot (perception lag ≈ 67 ms at 15 Hz, so the
policy reacts in 67–133 ms with the action repeat). Tested: same state → identical vector;
changing an opponent's pending input or the match RNG does not change it.

### act_v1 — `src/ai/policy/policy_actions.gd`
Decisions at 15 Hz (every 8 physics ticks; staggered between policy fighters), action held until
the next decision. Two heads → 21 logits:
- **move (9):** none, toward, away, left, right, toward-left, toward-right, away-left,
  away-right — relative to the soft-lock target (own facing if none), converted to the world
  stick vector at decision time;
- **button (12):** none, light, heavy (tap), heavy_hold (charge; a continued hold does not
  re-press), guard_hold, guard_tap (release one tick, then press + hold: opens the parry
  window), dodge, grab, ability1, ability2, juice, taunt. Missing ability slots are masked.

`classify_move` / `classify_button` are the exact inverse used to label recorded play; a test
drives a fighter with a stochastic policy and checks the recorder reproduces every action.

## 6. Policy files and the library

`<user data>/policies/<id>.policy.json` (user) and `content/<package>/policies/*.json`
(built-in / mods, read-only). One JSON object:

```text
format "critterweight.policy", format_version 1, id, name, version, creature, created, updated,
description, creature_signature (hash of the fighter definition at training time),
obs {version "obs_v1", size 118, target_lag}, act {version "act_v1", heads [9, 12],
decision_hz, mode argmax|sample, temperature, mask[12]},
arch {type "mlp", inputs 118, hidden [..], activation tanh|relu, outputs 21},
weights {encoding "f32le_base64", count, data}, training {...metadata...}, checksum
```

`training` records approach, run id, objective, scenario, seed, episodes, simulated seconds,
wall time, game version, contract versions, limits, and the evaluation summary (ES: test
results before/after; BC: held-out accuracy, baselines, action-distribution distance).

**Validation on load** (`PolicyData.from_dict`, `PolicyIO.read_one`): file ≤ 4 MB (checked before
reading), JSON object, known format, format_version not newer than this build, id/name/creature
syntax and length, exact contract versions and shapes, MLP limits (≤ 4 hidden layers, width
≤ 256, ≤ 250 000 parameters), weight count and base64 length, every weight finite and
|w| ≤ 10⁴, metadata ≤ 256 KB, and the checksum. **Loading never executes code**: only
`JSON.parse` and base64 → float32 decoding; unknown fields are inert data. Writes are atomic
(temp → verify → .bak → rename); a damaged file recovers from its verified `.tmp`/`.bak`.
A policy whose fighter definition changed since training still loads (contracts unchanged), with
a warning. Incompatible files are listed with their reason and cannot be used.

### Using policies in matches, hosts and servers
- Match config fighter entry: `{"creature": "<id>", "team": 1, "kind": "policy", "policy_id": "<id>"}`
  (`MatchScene` → `PolicyInputSource.for_match`; a missing or incompatible policy falls back to a
  scripted bot with a log line, so a match never fails to start).
- Lookup API (no autoload needed):
  ```gdscript
  var p := PolicyLibrary.get_policy(id)          # PolicyData or null (PolicyLibrary.last_error(id))
  var why := PolicyLibrary.compatibility(p, creature_id)   # "" = usable for that fighter
  var src := PolicyInputSource.create(p, seed, fighter_index)  # an InputSource for MatchSim
  src.apply_creature_mask(creature_def)
  ```
  (`get` itself is reserved by Godot's Object, hence `get_policy`.) Policies run where the match
  is simulated: on a host or dedicated server the server drives the bot; clients need nothing.
  Policies are not gameplay content, so they do not affect the multiplayer content hash.
- Mods may ship policies in `policies/*.json` with ids `<modid>:<name>`.

## 7. Datasets and recording

`<user data>/lab/datasets/<id>/`: `meta.json` (Saves envelope: name, creature, contract versions,
source, optional teacher statistics) + `shard_*.bin` (one recording session each; header
`CWDS`, format, obs size, count; float32 observations, u8 move, u8 button, u32 episode).
Reading validates header, exact length, finite values and label ranges; a damaged shard is
skipped and reported. `PolicyRecorder` wraps any input source and labels each 15 Hz window with
the act_v1 inverse mapping; the in-game switch wraps the local player only (`LabRecording`).

## 8. Worker processes, jobs, files

```text
<game> --headless --fixed-fps 120 -- --lab-worker <job.json> [--lab-out <run dir>] [--user-root <dir>]
```
(from source: `godot --headless --path game --fixed-fps 120 -- --lab-worker …`). `--fixed-fps 120`
makes every frame exactly one 120 Hz tick, as fast as the CPU allows. The game launches workers
with `OS.create_process(OS.get_executable_path(), …)`, its own pid, and a private `--user-root`
per process (so workers never write the player's profile or settings).

Rank 0 (coordinator) spawns `limits.workers − 1` helper processes, runs the job, distributes
episodes through `gen/task_*.json` / `result_*.json`, and re-runs the share of a helper that dies
or stops heart-beating (helpers rewrite `gen/hb_r<k>.json` every second; silence for 20 s means
gone, and a helper that heart-beats again gets work from the next batch). Helpers exit when the
coordinator is gone. A crashed or stalled helper therefore costs time, never results.

Job file (all fields optional except where noted; defaults in `src/lab/lab_job.gd`):

```json
{"kind": "es|bc|eval|record", "name": "", "creature": "dev_biped", "opponent_creature": "", "seed": 1,
 "objective": {"preset": "aggressive", "weights": {"damage_dealt": 1.0}},
 "scenario": {"preset": "drill_dummy", "opponents": ["idle"], "round_time": 8, "spawn": "random", "dist": [2, 4.5], "arena": "the_gullet"},
 "eval": {"opponents": [], "episodes": 6, "val_episodes": 6, "every": 5, "standard_spawns": true, "reference": ""},
 "model": {"hidden": [32, 32], "activation": "tanh", "init_policy": "", "mode": "", "out_scale": 0.01},
 "es": {"pairs": 12, "sigma": 0.05, "lr": 0.02, "l2": 0.005, "episodes_per_candidate": 1},
 "bc": {"datasets": ["<dataset id or folder>"], "epochs": 60, "batch": 128, "lr": 0.003, "val_frac": 0.2, "patience": 8, "rollouts": 6, "balance": false},
 "record": {"teacher": "bot_regular", "episodes": 40, "dataset_id": "", "dataset_name": ""},
 "target": {"policy": "<eval: policy id or file>", "compare": "random_init"},
 "limits": {"max_wall_s": 1800, "max_generations": 60, "max_epochs": 60, "max_episodes": 0,
            "workers": 1, "worlds": 2, "low_priority": true, "cpu_share": 1.0, "max_memory_mb": 3072}}
```

Run folder (`<user data>/lab/runs/<run id>/`): `job.json`, `job_effective.json` (normalised),
`status.json`, `progress.json` (rewritten every 0.5 s — the heartbeat the UI uses),
`metrics.jsonl` (one line per generation / epoch / validation), `control.json`
(`{"desired": "run|pause|cancel", "snapshot_seq": n}`), `checkpoints/ckpt_<n>.json` (last 3,
Saves envelopes), `report.json`, `best.policy.json`, `final.policy.json`, `worker_r<k>.log`,
`gen/`, `home_r<k>/`.

**Pause** freezes the physics spaces of running episodes immediately; **cancel** stops at once
keeping the last checkpoint; **limits** (time, generations/epochs, episodes, memory) end training
gracefully: final evaluation, policies saved, status `completed`. **Crash/kill recovery**: the UI
sees a stale heartbeat → `interrupted`; resuming loads the newest valid checkpoint (damaged ones are
skipped), truncates later metric lines, respawns helpers and continues. **Priority**: workers
lower their own priority (`low_priority`, Windows via PowerShell, Linux/macOS via `renice`) and
can idle a fraction of each frame (`cpu_share`).

Defaults are deliberately modest: 1 worker in jobs written by hand; the UI suggests
`min(3, cores/2 − 1)` workers, 2 matches per worker, 20-minute limit, low priority.
GPU: not used — the networks are tiny and the work is dominated by the physics simulation, which
runs on the CPU; no paid services, accounts or Python are involved.

## 9. Measurements (dev PC: i7-7700K 4C/8T, Windows 10)

Numbers and raw files: `docs/evidence/lab/README.md`. Reproduce:

```powershell
$g = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe"
& $g --headless --path game --fixed-fps 120 -- --lab-worker --lab-bench inference              # 8 policy fighters
& $g --headless --path game --fixed-fps 120 -- --lab-worker --lab-bench inference --hidden 64,64
& $g --headless --path game --fixed-fps 120 -- --lab-worker --lab-bench throughput             # one worker process
```

**Inference budget** (LAB-09): mean policy cost per 120 Hz physics tick for 8 policy-controlled
fighters ≤ 0.25 ms (1.5 % of a 60 fps frame), decisions staggered at 15 Hz. The forward pass is
compiled into 4×4 `Projection` blocks (one native mat×vec = 16 multiply-adds per interpreted
step, zero input blocks skipped). Tested by `test_policy_inference.gd`.

Measured on 2026-10-15. The PC was shared with other build and test jobs, so these numbers are
pessimistic.

| What | Result |
|---|---|
| Inference, 8 fighters, 32×32 network | 138.5 µs per tick (136.5 µs per decision: 80.8 encode + 42.9 forward) |
| Inference, 8 fighters, 64×64 network | 168.6 µs per tick |
| Throughput, 1 worker process × 2 worlds | 16.3 simulated seconds per wall second, 5,520 ten-second episodes per hour |
| Throughput, 3 worker processes | 30–33× real time: 18,340 six-second drill episodes or ~6,500 twenty-second matches per hour |
| Behaviour cloning | about 7 s per epoch over 20k recorded decisions (64×64 network) |
| Lab screen polling while a run trains | 1.8 ms every 0.5 s; game frame-time median unchanged at 16.7 ms (60 fps) |

## 10. Reproducible small examples

```powershell
# 1. ES learns the drill (approach and hit a standing dummy), ~5 min with 3 worker processes
& $g --headless --path game --fixed-fps 120 -- --lab-worker docs/evidence/lab/jobs/es_drill_seed101.json --lab-out runs/es101
# 2. record a teacher (Bot: Regular vs Rookie), then clone it
& $g --headless --path game --fixed-fps 120 -- --lab-worker docs/evidence/lab/jobs/record_teacher_regular.json --lab-out runs/rec
& $g --headless --path game --fixed-fps 120 -- --lab-worker docs/evidence/lab/jobs/bc_clone_regular.json --lab-out runs/bc
# 3. evaluate a shipped policy against the fixed baselines
#    {"kind": "eval", "target": {"policy": "dev_biped_es_drill"}, "eval": {"opponents": ["idle", "bot_rookie"]}}
```
Each run folder then holds `report.json`, `metrics.jsonl` and the trained `best.policy.json`
(also added to the policy library unless `output.save_to_library` is false). Same job + same
seed reproduces the same run (fixed-step worker processes).

## 11. Tests (`game/src/test/lab/`, run `-- --test lab`)

| File | Covers |
|---|---|
| test_policy_contract.gd | obs/act names and layout, bounds, determinism, perception-only and lag, fighter-space frame, wall rays, apply ↔ classify round trip for every action, masks/sampling, recorder reproduces a live policy's actions exactly |
| test_policy_mlp.gd | parameter layout, deterministic init, fast path = reference, backprop = finite differences (tanh, relu), ES noise reproducibility, centred ranks, ES on a synthetic objective, no step without signal |
| test_policy_io.gd | exact save/load round trip, rejection of truncated/garbage/edited/tampered/newer/incompatible/malformed/oversized/NaN files, inert unknown fields, .bak recovery, library save/rename/export/import (id collision)/delete, match fallback |
| test_lab_bc.gd | dataset shards round trip + damaged shard handling, BC overfits a tiny dataset, BC generalises on held-out episodes and beats the majority baseline |
| test_lab_recording.gd | a normal MatchScene match with the recording switch on, driven by simulated device input, writes human-labelled light/guard/move samples; with the switch off nothing changes |
| test_policy_inference.gd | 8 policy fighters in a live match stay within the inference budget |
| test_lab_worker.gd | the real worker process: pause/resume/cancel, kill + resume from the newest checkpoint with an unbroken curve, ES improves on the drill on held-out test seeds with no helper share dropped, the helper heartbeat rule, a silent worker whose process still runs is neither "interrupted" nor resumable twice |
| test_policy_samples.gd | the shipped sample policies validate, are listed and usable by their fighter, and the drill sample lands hits on fresh standing-dummy episodes where an untrained network does not |

Windowed tools (not part of `--test`):

- `lab_ui_capture.gd` drives the Lab screen. It measures frame times without and with a
  training run started from the Train tab, and exercises pause/resume/cancel through the
  screen's buttons. `--static` captures every tab; `--runs` captures the Runs tab of every run
  folder.
- `lab_match_capture.gd` spectates and fights a policy through the Policies tab.
- `lab_evidence_summary.gd` collects run folders into `summary.json`.

## 12. Limitations and known gaps

- Policies are per fighter; a policy only plays the creature it was trained for (by design: the
  observation is generic, the learned behaviour is not). The shipped samples are for the
  engine bring-up fighter `dev_biped`; the roster fighters need their own training runs.
- obs_v1 describes fighters, walls, projectiles and zones — not bonus-mode objectives (balls,
  spotlights, waves). Policies play standard fights; in objective modes they fight but ignore
  the objective (an obs_v2 with mode features would be needed).
- Training speed is bound by the physics simulation (~14–16 simulated seconds per wall second
  per worker process; ~30× real time with 3 processes on a 4-core PC). Hours of training are
  needed for strong play against the harder bot tiers.
- A low-priority worker yields to everything else. On a PC whose cores are all busy it can wait
  minutes for CPU. The Runs tab then says so; the run is not shown as interrupted and cannot be
  started twice, and it continues when CPU frees up.
- ES with small populations learns coarse behaviours; fine timing (parries) is rare without
  long runs or a technician-style reward. BC copies its teacher's mistakes and cannot exceed it.
- Bit-exact reproducibility holds for a fresh fixed-step worker process (same build, machine,
  job, seed); runs on different machines or builds may differ slightly.
- Process priority lowering needs PowerShell (Windows) or `renice` (Linux/macOS); if unavailable
  the worker continues at normal priority and says so in its log.
- The worker's CPU figure is the coordinator's main-thread utilisation (busy time per wall time),
  not an OS process counter; memory is Godot's static allocator usage.
