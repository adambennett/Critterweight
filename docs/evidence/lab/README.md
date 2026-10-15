# AI Lab: proof of learning and measurements

Evidence for LAB-01, LAB-02 and LAB-04…LAB-10 (`docs/REQUIREMENTS.md`). The user guide and
technical reference is `docs/AI_LAB.md`.

Every number here comes from the files in this folder. Each run was made by the real worker
process (`--lab-worker <job>`), the same code path the Lab screen launches, and its report
counts every evaluated episode.

| | |
|---|---|
| Date | 2026-10-15 |
| Code | branch `worktree-agent-a4da24ad1665fd51d` at merge `f9422fd` (main `d29ebd9` merged in). Later commits change only UI and liveness plumbing, not training. |
| Machine | Intel i7-7700K (4 cores, 8 threads), 32 GB, Windows 10 |
| Engine | Godot 4.5.1 (editor binary, console variant), headless workers with `--fixed-fps 120` |
| Load | The PC also ran other build and test jobs, with the CPU at 68–100 % for most of the session. That makes throughput lower and frame times noisier than on an idle PC (see "Measurements"). |

## Files

| Path | Contents |
|---|---|
| `jobs/*.json` | The exact job files. Each one runs again with the command under "Reproduce". |
| `runs/<run>/` | `report.json` (final evaluation), `metrics.jsonl` (learning curve), `job_effective.json` (job after normalisation), `progress.json` / `status.json` (final counters), `worker_r0.log`. Local paths are replaced with `<evidence>`. |
| `summary.json` | Every run's key numbers, produced by `src/test/lab/lab_evidence_summary.gd`. |
| `curves/*.jpg` | The Lab's **Runs** tab for each training run: state, counters, learning curve, checkpoints and report. |
| `bench/*.json` | Inference cost and single-process throughput (`--lab-bench`). |
| `ui/` | Lab screen captures, plus `ui_report.json`: frame times and pause/resume/cancel driven through the UI. |
| `match/` | "Spectate this bot" and "Fight this bot" with a shipped policy, plus `match_report.json`. |
| `determinism/` | Worker logs of the same ES job run twice: once with its helper processes dropped, once with them working. |

Shipped sample policies built from these runs are in `game/content/core/policies/`:
`dev_biped_es_drill` (from `es_drill_seed303`), `dev_biped_bc_regular` (from `bc_regular`) and
`dev_biped_bces_aggressive` (from `bc_then_es`).

## 1. Evolution strategies on the controlled drill task (3 seeds)

**Task.** `dev_biped` against a standing dummy that never moves or fights back, in 6-second
rounds. Training uses random spawns 2–4.5 m apart. The reward is the *Drill* preset: damage
dealt + hits + 0.5 × approach. Approach is potential-based, so it cannot be farmed.

**Learner.** An MLP 118-32-32-21 (tanh, 5,557 parameters) with near-zero initial outputs
(`out_scale` 0.01), acting by argmax.

**ES.** 12 mirrored pairs (24 candidates) × 1 episode per generation, σ 0.05, Adam lr 0.02,
25 generations. Each generation runs 3 worker processes × 2 worlds.

**Selection and test.** Every 5 generations, θ and the generation's best candidate play
8 validation episodes, and the best validated network is kept. The final report plays 20
held-out test episodes (10 random spawns + 10 corner spawns that training never uses) with
both the starting network and the selected one. The hand-written scripted "jabber" plays the
same test episodes as a reference.

| Seed | Starting network: test reward (95 % CI) | Trained: test reward (95 % CI) | Welch t | Hits / damage per episode (start → trained) | Scripted jabber, same episodes | Selected | Wall time |
|---|---|---|---|---|---|---|---|
| 101 | −0.76 (−0.78..−0.74), win 0 % | **47.06** (45.56..48.56), win 100 % | 62.5 | 0.0 / 0.0 → 9.0 / 37.0 | 56.24 (53.49..59.00) | gen 15, elite | 490 s |
| 202 | 23.01 (21.14..24.89), win 100 % | **51.22** (45.73..56.70), win 100 % | 9.5 | 1.3 / 20.8 → 2.6 / 47.4 | 54.77 (52.65..56.88) | gen 25, elite | 267 s |
| 303 | 12.70 (12.48..12.91), win 100 % | **52.32** (50.09..54.56), win 100 % | 34.6 | 2.0 / 12.0 → 6.9 / 44.4 | 53.53 (50.53..56.52) | gen 10, elite | 147 s |

(n = 20 test episodes per row. "Win" against the dummy is a decision on damage, because the
dummy never attacks.)

- **All three seeds improved, on episodes training never saw.** The mean gain is
  **+38.6 reward** (range +28.2 to +47.8). Every trained policy is significantly above its
  starting network, with Welch t between 9.5 and 62.5.
- **The population learned, not just the selected network.** Mean training fitness over the
  first 3 generations vs the last 3:
  - seed 101: 11.6 → 41.8
  - seed 202: 10.2 → 40.9
  - seed 303: 10.9 → 42.7

  Validation reward of θ went from −0.77, 24.3 and 12.5 at generation 0 to 47.8, 59.5 and
  42.6 at generation 25 (curves in `curves/es_drill_seed*.jpg` and `runs/*/metrics.jsonl`).
- **What it learned.** Each seed learned to close the distance and attack: seed 101 with
  light-attack strings (9 hits per episode), seed 202 with fewer, heavier hits. After
  25 generations the trained policies come within 1–9 reward points of the hand-written
  jabber. Seed 303's interval overlaps the jabber's.
- **Determinism.** Two earlier runs of seed 101 on the pre-merge build are compared in
  `determinism/`.
  - The first lost both helper processes to a liveness bug, since fixed (see
    `helpers_dropped_console_warnings.txt`), so its coordinator re-ran their episodes.
  - The second kept all three processes working.

  Both logs show the same per-generation fitness values. Distributing episodes over
  processes does not change the result.

## 2. Behaviour cloning

**Recording.** A scripted teacher plays as `dev_biped` against Bot: Rookie, with 20-second
rounds in the sparring arena. Every 15 Hz decision is labelled with the act_v1 inverse
mapping.

**Training.** An MLP 118-64-64-21 (13,141 parameters) trained with masked cross-entropy on the
move and button heads. The validation split is by whole recorded episodes. Training uses
minibatch 128, Adam lr 0.003, and early stopping with patience 8.

**Test.** The clone and the teacher then play the same 12 test matches against Rookie. The
clone samples its actions.

| | Teacher: Bot Regular (`bc_regular`) | Teacher: scripted jabber (`bc_jabber`) |
|---|---|---|
| Recorded | 90 matches, 24,388 decisions. Teacher won 64 % [54–74]. | 60 matches, 14,535 decisions. Teacher won 27 % [17–39]. |
| Split (train / validation decisions) | 19,704 / 4,684 | 11,649 / 2,886 |
| Validation loss: untrained → best | 4.68 → **1.50** (epoch 16 of 24, early stop) | 4.71 → **0.33** (epoch 31 of 39) |
| Held-out accuracy: move / button / both | **71.4 % / 81.6 % / 58.7 %** | **97.1 % / 89.0 % / 86.5 %** |
| Majority-class baseline: move / button / both | 46.5 % / 59.0 % / 27.8 % | 74.2 % / 88.2 % / 65.1 % |
| Untrained network: both heads | 1.2 % | 0.0 % |
| Action-distribution distance to the teacher (TVD, 0 = identical): move / button | 0.138 / 0.027 | 0.012 / 0.002 |
| Clone in 12 test matches | reward 97.5 ± 27.9, **win 92 %** [65–99] | reward 72.0 ± 30.1, win 75 % [47–91] |
| Teacher in the same 12 matches | reward 82.8 ± 33.4, win 75 % [47–91] | reward 53.5 ± 32.3, win 33 % [14–61] |

- **Training worked on both datasets.** Validation loss fell 68–93 %, and held-out accuracy
  is far above the majority class on the move head and for both heads together.
- **One weak spot.** The jabber's button stream is 88 % "none", so its button accuracy is
  barely above the majority class. Its move accuracy (97 %) carries that clone.
- **The clones behave like their teachers.** The action-frequency distances are small. In
  matches, the clones' outcomes are statistically indistinguishable from the teachers'
  (n = 12, overlapping intervals). The Regular clone won 11 of 12, the teacher 9 of 12, which
  is no evidence that it is stronger.

## 3. Clone, then evolve (BC → ES)

**Setup.** The run starts from the Bot Regular clone above. ES optimises the *Aggressive*
objective against Rookie in 20-second matches: 12 pairs, σ 0.02, lr 0.01, 16 generations,
3 worker processes.

| Test, 20 held-out matches vs Rookie | Reward (95 % CI) | Win |
|---|---|---|
| Clone it started from | 73.70 ± 29.50 (60.77..86.62) | 80 % [58–92] |
| After 16 generations of ES | 88.67 ± 35.68 (73.04..104.31) | 80 % [58–92] |
| Bot: Regular on the same matches | 99.06 ± 36.91 (82.88..115.23) | 85 % [64–95] |

- The population fitness rose from 65.5 to 91.1 (mean of the first 3 vs last 3 generations).
  The validation reward of the selected elite rose from 51.6 to 92–97.
- **On the held-out test the gain (+15.0) is not significant** (Welch t = 1.45). Matches
  against a bot are noisy, and 16 generations is a short run. This run demonstrates the
  pipeline, not a stronger fighter. The shipped policy says so in its description.

## 4. Measurements

**Inference cost** (LAB-09; `bench/inference_*.json`). 8 policy-controlled fighters in a
live match, decisions staggered at 15 Hz.

| Network | Per decision | Encode | Forward | Per 120 Hz tick, 8 fighters | Worst decision |
|---|---|---|---|---|---|
| 32×32 (5,557 params) | 136.5 µs | 80.8 µs | 42.9 µs | **138.5 µs** | 256 µs |
| 64×64 (13,141 params) | 166.2 µs | 81.1 µs | 72.2 µs | **168.6 µs** | 394 µs |

Both are within the documented budget of 250 µs per tick (1.5 % of a 60 fps frame).
`test_policy_inference.gd` checks the 32×32 network on every test run.

**Training throughput** (simulated seconds per wall second; episodes include world setup and
teardown):

| Workload | Processes × worlds | Sim speed | Episodes / hour |
|---|---|---|---|
| Bench: policy vs Regular/jabber, 10 s rounds (`bench/throughput_1proc.json`) | 1 × 2 | 16.3× | 5,520 |
| ES drill, 6 s rounds, `es_drill_seed303` | 3 × 2 | 30.6× | 18,340 |
| Recording, 20 s matches, `rec_regular` / `rec_jabber` | 3 × 2 | 32.9× / 32.5× | 6,565 / 7,253 |
| BC → ES, 20 s matches, `bc_then_es` | 3 × 2 | 32.3× | 6,187 |
| ES drill under heavy outside load, `es_drill_seed101` | 3 × 2 | 9.2× | 5,493 |

Throughput scales with worker processes, not worlds per process. The simulation is
single-threaded GDScript + Jolt per process. In the ES runs the coordinator spends some time
waiting at generation barriers. BC training itself is CPU-bound GDScript: about 7 s per epoch
over 20k decisions with a 64×64 network.

**Game responsiveness while training** (`ui/ui_report.json`). The Lab screen ran windowed
(60 fps vsync) on the Runs tab:

- First, 20 s with no worker as a baseline.
- Then 40 s while a training run started from the Train tab ran one worker at normal
  priority. That is the worst case for the game; the default is low priority.

| | Median | p95 | p99 | Frames > 33 ms |
|---|---|---|---|---|
| No worker (baseline) | 16.7 ms | 56.6 ms | 118.7 ms | 7.7 % |
| One worker training | 16.7 ms | 18.3 ms | 19.4 ms | 0.3 % |

The tails come from the other jobs sharing this PC, not from the worker. In this sample the
baseline happened to coincide with heavier outside load. An earlier repeat, before the Lab's
own polling was made cheaper, measured p99 63 ms without a worker and 70 ms with one.

The screen's own polling of the run files costs **1.8 ms** (median, 3.8 ms max) every 0.5 s.
Before that optimisation it was 8.3 ms, and listing 8 runs took 50–60 ms; now it takes 4 ms.

**Driving the run from the UI** works: pause → `paused` (no episodes run while paused) →
resume → `running` → cancel → `cancelled`, all through the screen's own buttons, as captured
in `ui/run_*.jpg`.

**Spectate and fight a shipped policy** (`match/match_report.json`). This sample was captured
during the same session as the other measurements.

- **Spectate.** "Regular Clone (BC)" vs Bot: Rookie for 12 s of a 60 s round. The clone landed
  9 hits for 56 damage and took 8 hits for 69. In an earlier capture it landed 11 hits for
  84 damage and took 1 hit for 6. Matches differ because the clone samples its actions.
- **Fight.** The clone against an idle local player: 7 hits, 43 damage in 6 s.

Both matches are normal `MatchScene` matches using fighter kind `policy`.

## Reproduce

From the repository root, with the Godot 4.5.1 console binary as `$g`:

```powershell
$g = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe"
$w = { param($job, $out) & $g --headless --path game --fixed-fps 120 -- --lab-worker $job --lab-out $out --user-root runs/home }
& $w docs/evidence/lab/jobs/es_drill_seed101.json runs/es_drill_seed101      # also seed202 / seed303
& $w docs/evidence/lab/jobs/record_teacher_regular.json runs/rec_regular
& $w docs/evidence/lab/jobs/bc_clone_regular.json runs/bc_regular
& $w docs/evidence/lab/jobs/record_teacher_jabber.json runs/rec_jabber
& $w docs/evidence/lab/jobs/bc_clone_jabber.json runs/bc_jabber
# BC -> ES: copy jobs/bc_then_es_template.json and set model.init_policy to runs/bc_regular/best.policy.json
& $g --headless --path game --fixed-fps 120 -- --lab-worker --lab-bench inference --lab-out bench32.json
& $g --headless --path game --fixed-fps 120 -- --lab-worker --lab-bench inference --hidden 64,64 --lab-out bench64.json
& $g --headless --path game --fixed-fps 120 -- --lab-worker --lab-bench throughput --lab-out throughput.json
& $g --headless --path game -s res://src/test/lab/lab_evidence_summary.gd -- --runs "runs/es_drill_seed101;runs/bc_regular" --out summary.json
# windowed checks (not part of --test)
& $g --path game -s res://src/test/lab/lab_ui_capture.gd -- --user-root <fresh dir> --out <dir> --train-seconds 40
& $g --path game -s res://src/test/lab/lab_match_capture.gd -- --user-root <fresh dir> --out <dir> --policy dev_biped_bc_regular
& $g --path game -s res://src/test/lab/lab_ui_capture.gd -- --user-root <dir whose lab/runs holds run folders> --out <dir> --runs
```

A fresh fixed-step worker process makes the same job and seed reproduce the same run on the
same build and machine. A different machine or build may differ slightly.
