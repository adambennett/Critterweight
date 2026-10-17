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

Open the **AI Lab** screen (main menu → AI Lab; App screen `lab`). Nine sample policies ship with the game
(`content/core/policies/`): an ES drill policy for each of the six fighters (`f_<id>_es_drill`), plus three for the
development biped:

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
   drill or another policy). An [INVALID] user file can still be deleted, or renamed (its file
   is renamed, since an unreadable file cannot carry a new name inside); built-ins are read-only.
4. **Recording** — *Record my matches for imitation learning* (off by default): while on, every
   match you play stores what you saw and did into the dataset "My <fighter> matches". You can
   also record a teacher bot headlessly (recording the same teacher again adds new episodes,
   see §7), and rename/delete datasets.

The game never trains in its own process, so menus stay responsive (measured while a worker
trains: see `docs/evidence/lab/README.md`). Closing the game stops workers at their last
checkpoint ("interrupted", within ~15 s); *Continue run* picks them up again. When a completed
run shows a trained policy beating its baseline on held-out evaluation (a paired 95 % interval
above zero on the same test episodes; for BC, test-episode accuracy clearly above the
majority-class baseline), the Lab unlocks the *Mad Scientist* achievement
(`Platform.unlock_achievement("ach_mad_scientist")`).

## 2. Training approaches

### 2.1 Evolution strategies (`kind: es`)
OpenAI-style ES (Salimans et al. 2017) on the flat network parameters θ:
mirrored Gaussian perturbations θ ± σε regenerated from per-pair seeds (worker processes rebuild
candidates from θ + seeds), every candidate plays the same training episodes (common random
numbers), fitness = mean episode reward → centred ranks → gradient estimate
Σ(r⁺−r⁻)ε/(2nσ) → Adam step with decoupled weight decay. No step is taken when every pair ties.

*Model selection.* ES optimises the noise-smoothed objective, so early on the mean θ can play
worse than its best perturbations. Every `eval.every` generations — and once more when training
stops, if generations ran since the last validation — both θ and the generation's best
candidate ("elite") play the **validation** seeds; the best validated network is kept. The
starting network is validated before the first generation and competes too: if nothing beat
it, the report (`selected_initial`), the run's message and the policy's metadata say that the
saved policy is the starting network. The final report evaluates the initial network and the
selected one on separate **test** seeds (and optionally a scripted reference on the same
episodes), with a paired test over those shared episodes. A run started from a saved policy
keeps that policy's play settings (temperature, perception lag, decision rate, button mask).

*What it learns / why it fits.* It optimises any episode-level reward (damage, survival,
parries, taunts…) through the non-differentiable physics, needs no recordings, parallelises over
worker processes trivially, and works with the deterministic (argmax) policies used in matches.
Cost: many episodes; it learns coarse behaviours first (approach, attack rhythm, guarding).

### 2.2 Behaviour cloning (`kind: bc`)
Supervised learning of the act_v1 heads from recorded (observation, action) pairs:
masked cross-entropy on the move head and the button head (optionally class-balanced),
minibatch Adam + L2. The recorded **episodes** are split three ways (copies of an episode count
as one, see §7): `val_frac` (20 %) validate — early stopping on validation loss, best weights
kept — `test_frac` (20 %) test, the rest train. No episode is in two splits and nothing is
trained on validation or test data; the reported **test accuracy** comes from episodes that
influenced neither the weights nor the stopping point (validation accuracy is reported too,
labelled as the early-stopping split). A dataset needs at least **6 episodes** (rounds); smaller
ones are refused with that message. The report shows the split (`split.mode` "episodes" and the
episode counts per part). After training the clone and — when the dataset came from a scripted
teacher — the teacher itself play the same test episodes; the report compares outcomes (with a
paired test) and action distributions (total variation distance) next to the test accuracy, the
majority-class baseline and the untrained network.

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
delays and mistakes; never omniscient). `policy:<file>` plays a saved policy. `build:<json>`
plays one of the profile's **saved campaign builds** (`profile.campaign.saved_builds`: the fighter
with the techniques and supplements it finished a run with, composed by the campaign's
`BuildApplier`; no Cannery upgrades, no Dose) piloted by a Pro bot — the whole build travels inside
the opponent kind, so jobs and workers rebuild it exactly.
Scenario presets (`src/lab/lab_scenarios.gd`): *Drill: standing dummy*, *Drill: patrolling
dummy*, *Sparring: jabber*, *Sparring: jabber + turtle*, *Bots: Rookie + Regular*, *Bots: Pro +
Champion*, and — with the Cannery's **Boiler Room Key** (`meta_boiler_room_key`, Teddy's ledger) —
*My saved builds* (the six most recent saved builds as opponents; `LabScenarios.preset_ids_for`);
every field can be overridden (opponents, round length, random vs standard spawns, spawn distance,
arena). Spawns: *random* puts the learner anywhere in the inner part of the
arena and the opponent `dist` metres away; *standard* uses the arena's standard opposite spawn
points, jittered per episode seed (±0.35 m, ±25°); *swapped* exchanges the two sides. (Before
this fix, format-2 arenas such as The Gullet placed the opponent of every random-spawn episode
on one fixed spawn point and "swapped" did not swap.)

Every episode is a fresh physics world (SubViewport with its own World3D) running a real
`MatchSim` with the standard `MatchMode` (one round; KO or decision at the time limit). Two
rules differ from a broadcast match and are set through the normal rules dictionary: the
cosmetic intro is a 0.2 s settle (`intro_time`; round-start hooks still fire) and a tie at the
time limit is a draw (`sudden_death: false`) so every episode has a bounded length.

Seeds come from disjoint named streams: `train:<job seed>:<generation>:<k>`,
`val:<job seed>:<i>` (model selection only), `test:<job seed>:<i>` (final reports only) and
`rec:<job seed>:<index>` (teacher recordings). Evaluation additionally plays the arena's standard
spawns (jittered, alternating sides), a layout random-spawn training never uses.

Every evaluation episode starts differently, so **n counts distinct episodes** (before the
jitter, a deterministic policy against the standing dummy replayed the standard-spawn episode
n times and each copy was counted). Reports give n, mean ± std and a 95 % confidence interval
of reward, damage dealt/taken and hits — a **Student-t** interval (t quantile for n − 1 degrees
of freedom; no interval at all for n < 2) — and win rate with a Wilson 95 % interval, per
opponent. Every evaluated episode counts, nothing is cherry-picked. Two conditions played on the
same episodes (initial vs trained network, a policy vs its comparison or the scripted reference,
a clone vs its teacher) are compared with a **paired test** over those episodes: mean difference,
its 95 % interval, t and n (`paired`, `paired_compare`, `paired_reference`, `paired_teacher`);
"significant" means the interval excludes 0. (Welch's unpaired t is still reported as `welch_t`.)
Evaluation jobs (`kind: eval`) play the policy exactly as saved (its action mode, temperature,
perception lag, decision rate and button mask) and compare it with a random network of the same
shape and settings and/or a scripted reference on the same test episodes. *Evaluate vs baselines*
scores with the policy's own training objective, including edited reward weights. Evaluation and
recording jobs run in short batches and stop at their time or episode limit with a partial
report (`complete: false`, `stop_reason`, played vs planned episodes).

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
results before/after with the paired comparison; BC: test-episode accuracy (`test_accuracy`),
validation accuracy (`val_accuracy`, the early-stopping split), the split, baselines,
action-distribution distance). Policies saved by earlier builds only carry `val_accuracy`; the
Lab labels it as validation accuracy.

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
source, optional teacher statistics, `next_episode`) + `shard_*.bin` (one recording session each;
header `CWDS`, format, obs size, count; float32 observations, u8 move, u8 button, u32 episode and
— shard format 2 — u32 seed per sample). Format 1 shards (no seed column, written by earlier
builds) still load; new shards are format 2, which earlier builds reject. Reading validates
header, exact length, finite values and label ranges; a damaged shard is skipped and reported.
`PolicyRecorder` wraps any input source and labels each 15 Hz window with the act_v1 inverse
mapping; the in-game switch wraps the local player only (`LabRecording`).

*Seeds and copies.* Each teacher recording run continues the dataset's numbering: episode k of a
run is recording index `first + k` (stored in the episode column) with seed
`rec:<job seed>:<first + k>` (stored in the seed column), where `first` follows everything the
dataset already holds (`meta.next_episode`, reserved when the run starts, and the highest index
in its shards). Recording the same teacher again — same job seed or not — therefore adds new
episodes. *Continue run* re-uses the run's reservation (kept in its checkpoint) and skips every
episode whose seed the dataset already has. Loading drops exact copies of an episode (identical
samples, e.g. a teacher recorded twice by an earlier build) and gives each remaining episode a
split unit — its seed when known, else its content hash — so copies of an episode always land in
the same behaviour-cloning split. Human recordings have no seed (0).

## 8. Worker processes, jobs, files

```text
<game> --headless --fixed-fps 120 -- --lab-worker <job.json> [--lab-out <run dir>] [--user-root <dir>]
```
(from source: `godot --headless --path game --fixed-fps 120 -- --lab-worker <job.json>`).
**`--path game` makes the game folder Godot's working directory**, so relative paths in a
command run from the repository root must start with `../` (`--lab-worker ../docs/evidence/lab/jobs/…`,
`--lab-out ../runs/…`) or be absolute; a worker that cannot find its job file says so.
`--fixed-fps 120` makes every frame exactly one 120 Hz tick, as fast as the CPU allows. The game
launches workers with `OS.create_process(OS.get_executable_path(), …)`, its own pid, and a
private `--user-root` per process (so workers never write the player's profile or settings).

Rank 0 (coordinator) runs the job and starts `limits.workers − 1` helper processes the first
time the job hands out episodes (a behaviour-cloning job therefore has no helpers while its
network trains). It distributes episodes through `gen/task_*.json` / `result_*.json` and re-runs
a helper's share itself when the helper
- dies or stops heart-beating (helpers rewrite `gen/hb_r<k>.json` every second, also while the
  run is paused; silence for `limits.heartbeat_s` = 20 s means gone, and after a resume every
  helper gets a fresh 20 s grace period), or
- does not deliver its results in time: once the coordinator has finished its own share, a
  helper gets 3× that time (scaled to its share size, at least `limits.straggler_s` = 30 s, pauses
  excluded), counted from the batch's submission — or, for a helper still starting its process,
  from its first heartbeat (the boot itself is covered by a 60 s startup timeout). A late result
  is ignored; a helper that misses twice in a row gets no work for the next 5 batches.

A helper that heart-beats again gets work from the next batch. Helpers exit when the
coordinator is gone (they read its progress heartbeat, and ask the OS only when that is stale).
A crashed, stalled or stuck helper therefore costs time, never results — and never hangs a run.
Recording batches: helpers write their shards into `gen/stage_<task>_r<k>/`; the coordinator
moves them into the dataset only when it accepts that helper's result for the current batch,
so a re-run share is never stored twice.
An idle helper looks for new work every 20–250 ms (growing while idle) and sleeps 20 ms per
frame; the coordinator checks that the game is still running every 15 s through the OS (on
Windows a `tasklist` call of ~0.1 s), so closing the game stops its workers within ~15 s.

Job file (all fields optional except where noted; defaults in `src/lab/lab_job.gd`):

```json
{"kind": "es|bc|eval|record", "name": "", "creature": "dev_biped", "opponent_creature": "", "seed": 1,
 "objective": {"preset": "aggressive", "weights": {"damage_dealt": 1.0}},
 "scenario": {"preset": "drill_dummy", "opponents": ["idle"], "round_time": 8, "spawn": "random", "dist": [2, 4.5], "arena": "the_gullet"},
 "eval": {"opponents": [], "episodes": 6, "val_episodes": 6, "every": 5, "standard_spawns": true, "reference": ""},
 "model": {"hidden": [32, 32], "activation": "tanh", "init_policy": "", "mode": "", "out_scale": 0.01},
 "es": {"pairs": 12, "sigma": 0.05, "lr": 0.02, "l2": 0.005, "episodes_per_candidate": 1},
 "bc": {"datasets": ["<dataset id or folder>"], "epochs": 60, "batch": 128, "lr": 0.003, "val_frac": 0.2, "test_frac": 0.2, "patience": 8, "rollouts": 6, "balance": false},
 "record": {"teacher": "bot_regular", "episodes": 40, "dataset_id": "", "dataset_name": ""},
 "target": {"policy": "<eval: policy id or file>", "compare": "random_init"},
 "limits": {"max_wall_s": 1800, "max_generations": 60, "max_epochs": 60, "max_episodes": 0,
            "workers": 1, "worlds": 2, "low_priority": true, "cpu_share": 1.0, "max_memory_mb": 3072,
            "heartbeat_s": 20, "straggler_s": 30}}
```

Job format changes are additive: every field has a default, so older job files run unchanged.
Added in this version: `bc.test_frac` (episodes held out for the reported test accuracy),
`limits.heartbeat_s` and `limits.straggler_s` (helper liveness and delivery deadline; tests lower
them). `max_wall_s` and `max_episodes` now also end evaluation and recording jobs (after the
current short batch, with a partial report that says so).
Behaviour change for existing jobs: recording jobs continue the dataset's episode numbering
(see §7), behaviour cloning needs at least 6 recorded episodes and splits them three ways, and
evaluation's standard spawns are jittered per seed (§4).

Run folder (`<user data>/lab/runs/<run id>/`): `job.json`, `job_effective.json` (normalised),
`status.json`, `progress.json` (rewritten every 0.5 s — the heartbeat the UI uses),
`metrics.jsonl` (one line per generation / epoch / validation), `control.json`
(`{"desired": "run|pause|cancel", "snapshot_seq": n}`), `checkpoints/ckpt_<n>.json` (last 3,
Saves envelopes), `report.json`, `best.policy.json`, `final.policy.json`, `worker_r<k>.log`,
`gen/` (task/result/heartbeat files, helper staging folders), `home_r<k>/`. `progress.json`
also counts helper shares re-run because the helper was gone (`reassigned`) or late (`late`).

**Pause** freezes the physics spaces of running episodes immediately; **cancel** stops at once
keeping the last checkpoint; **limits** (time, generations/epochs, episodes, memory) end training
gracefully: final evaluation, policies saved, status `completed`. **Crash/kill recovery**: the UI
sees a stale heartbeat → `interrupted`; resuming loads the newest valid checkpoint (damaged ones are
skipped), truncates later metric lines, respawns helpers and continues. **Priority**: workers
lower their own priority (`low_priority`, Windows via PowerShell, Linux/macOS via `renice`) and
can leave a fraction of the CPU to other programs (`cpu_share`: frames are measured including
the physics step and engine overhead, and the sleep owed is paid off in whole milliseconds by
the time actually slept, so the long-run share matches the setting; see §12).

Defaults are deliberately modest: 1 worker in jobs written by hand; the UI suggests
`min(3, cores/2 − 1)` workers, 2 matches per worker, 20-minute limit, low priority.
GPU: not used — the networks are tiny and the work is dominated by the physics simulation, which
runs on the CPU; no paid services, accounts or Python are involved.

## 9. Measurements (dev PC: i7-7700K 4C/8T, Windows 10)

Numbers and raw files: `docs/evidence/lab/README.md`. Reproduce:

```powershell
$g = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe"
# from the repository root; --path game makes game/ the working directory, hence ../
& $g --headless --path game --fixed-fps 120 -- --lab-worker --lab-bench inference --lab-out ../bench32.json   # 8 policy fighters
& $g --headless --path game --fixed-fps 120 -- --lab-worker --lab-bench inference --hidden 64,64 --lab-out ../bench64.json
& $g --headless --path game --fixed-fps 120 -- --lab-worker --lab-bench throughput --lab-out ../throughput.json   # one worker process
```

**Inference budget** (LAB-09): mean policy cost per 120 Hz physics tick for 8 policy-controlled
fighters ≤ 0.25 ms (1.5 % of a 60 fps frame), decisions staggered at 15 Hz. The forward pass is
compiled into 4×4 `Projection` blocks (one native mat×vec = 16 multiply-adds per interpreted
step, zero input blocks skipped). Tested by `test_policy_inference.gd`.

Measured on 2026-10-15 with the PC saturated by other build and test jobs (CPU 40–100 %), so
these numbers are pessimistic; wall-clock timings in particular inflate under load.

| What | Result |
|---|---|
| Inference, 8 fighters, 32×32 network | 263 µs per tick at 86 % load (211–326 µs over eight runs; the build before the review fixes measured the same under the same load; 138.5 µs earlier on a quieter PC) |
| Inference, 8 fighters, 64×64 network | 340 µs per tick at 93 % load |
| Throughput, 1 worker process × 2 worlds | 7.4–9.1 simulated seconds per wall second (2,400 ten-second or 5,480 six-second episodes per hour) |
| Throughput, 3 worker processes | 15–19× real time: ~10,000 six-second drill episodes or ~3,300 twenty-second matches per hour |
| Behaviour cloning | about 11 s per epoch over 16k recorded decisions (64×64 network, with the validation pass) |
| CPU share 50 % / 25 % | main-thread duty 0.50 / 0.25, episodes per minute halved at 50 % (process CPU incl. engine threads: 1.31 / 0.44 / 0.19 cores at 100 / 50 / 25 %) |
| Lab screen polling while a run trains | 1.9 ms every 0.5 s; game frame-time median unchanged at 16.7 ms (60 fps) |

## 10. Reproducible small examples

```powershell
# from the repository root (--path game makes game/ the working directory, hence ../)
# 1. ES learns the drill (approach and hit a standing dummy), ~5 min with 3 worker processes
& $g --headless --path game --fixed-fps 120 -- --lab-worker ../docs/evidence/lab/jobs/es_drill_seed101.json --lab-out ../runs/es101 --user-root ../runs/home
# 2. record a teacher (Bot: Regular vs Rookie), then clone it (same --user-root: the dataset is found by id)
& $g --headless --path game --fixed-fps 120 -- --lab-worker ../docs/evidence/lab/jobs/record_teacher_regular.json --lab-out ../runs/rec --user-root ../runs/home
& $g --headless --path game --fixed-fps 120 -- --lab-worker ../docs/evidence/lab/jobs/bc_clone_regular.json --lab-out ../runs/bc --user-root ../runs/home
# 3. evaluate a shipped policy against the fixed baselines
& $g --headless --path game --fixed-fps 120 -- --lab-worker ../docs/evidence/lab/jobs/eval_es_drill.json --lab-out ../runs/eval_drill --user-root ../runs/home
```
Each run folder then holds `report.json`, `metrics.jsonl` and the trained `best.policy.json`
(also added to the policy library of that `--user-root` unless `output.save_to_library` is
false). Same job + same seed reproduces the same run (fixed-step worker processes) — recording
into a fresh `--user-root`, since a dataset that already holds episodes continues its numbering.

## 11. Tests (`game/src/test/lab/`, run `-- --test lab`)

| File | Covers |
|---|---|
| test_policy_contract.gd | obs/act names and layout, bounds, determinism, perception-only and lag, fighter-space frame, wall rays, apply ↔ classify round trip for every action, masks/sampling, recorder reproduces a live policy's actions exactly |
| test_policy_mlp.gd | parameter layout, deterministic init, fast path = reference, backprop = finite differences (tanh, relu), ES noise reproducibility, centred ranks, ES on a synthetic objective, no step without signal |
| test_policy_io.gd | exact save/load round trip, rejection of truncated/garbage/edited/tampered/newer/incompatible/malformed/oversized/NaN files, inert unknown fields, .bak recovery, library save/rename/export/import (id collision)/delete, [INVALID] user files can be renamed and deleted, content-package policies are size-capped before reading, match fallback |
| test_lab_bc.gd | dataset shards round trip + damaged shard handling, BC overfits a tiny dataset, BC generalises on held-out episodes and beats the majority baseline, the three-way episode split, too-small datasets refused, the BC job reports test-episode accuracy and its split |
| test_lab_datasets.gd | identical re-recordings (format 1 shards) load once with no held-out sample equal to a training sample, copies of a seeded episode share a split, recording the same teacher twice adds new seeds (helper shards committed once), *Continue run* records nothing twice |
| test_lab_stats.gd | Student-t intervals (none for n < 2), the paired test, jittered/swapped/random spawns, standard-spawn episodes of a deterministic policy are not repeats |
| test_lab_recording.gd | a normal MatchScene match with the recording switch on, driven by simulated device input, writes human-labelled light/guard/move samples; with the switch off nothing changes |
| test_policy_inference.gd | 8 policy fighters in a live match stay within the inference budget |
| test_lab_worker.gd | the real worker process: pause/resume/cancel, kill + resume from the newest checkpoint with an unbroken curve, ES improves on the drill on held-out test seeds with no helper share dropped, the helper heartbeat rule, a silent worker whose process still runs is neither "interrupted" nor resumable twice |
| test_lab_worker_faults.gd | a long pause keeps the helpers, a helper that never delivers cannot hang a run, evaluation/recording stop at the time limit with a partial report, ES validates the last generations before selecting, evaluation plays a policy as saved and with its own objective, BC starts helpers only for the rollouts, idle helpers back off, helpers exit when the coordinator dies, the CPU share holds over the long run, straggler and grace rules |
| test_lab_docs.gd | every documented `--path game` command resolves its paths from the game folder |
| test_policy_samples.gd | the shipped sample policies validate, are listed and usable by their fighter, and the drill sample lands clearly more hits on fresh standing-dummy episodes than an untrained network of the same shape |

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
- Training speed is bound by the physics simulation (7–9 simulated seconds per wall second per
  worker process on the busy dev PC, more on idle cores; 15–19× real time with 3 processes on
  that 4-core PC). Hours of training are
  needed for strong play against the harder bot tiers.
- CPU share below 100 %: each worker measures whole frames (its script, the physics step and
  engine overhead) and sleeps off the accumulated difference in whole milliseconds, counting the
  time it really slept, so the long-run share matches the setting (`test_cpu_throttle_…`). Within
  a second the pattern is bursty (a few ms of work, then a sleep); the share counts the main
  thread's wall time, so engine worker threads (if any) are not limited by it.
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
