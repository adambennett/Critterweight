# AI Lab: proof of learning and measurements

Evidence for LAB-01, LAB-02 and LAB-04…LAB-10 (`docs/REQUIREMENTS.md`). The user guide and
technical reference is `docs/AI_LAB.md`.

Every number here comes from the files in this folder. Each run was made by the real worker
process (`--lab-worker <job>`), the same code path the Lab screen launches, with the exact
commands under "Reproduce", and its report counts every evaluated episode.

| | |
|---|---|
| Date | 2026-10-15 |
| Code | branch `worktree-agent-a42cbda669239d832` (the AI Lab review fixes). The training runs (sections 1–3) were made at `cfb471e`. Main was then merged twice (`fd1e051`, `b4103b1`); after each merge the determinism job reproduced its metrics and test results exactly, and after the second the Regular-clone evaluation against Bot: Rookie (with Bot: Regular as reference) reproduced exactly too (`determinism/`). Publishing, evaluation (section 4), captures and measurements were made after the first merge. |
| Machine | Intel i7-7700K (4 cores, 8 threads), 32 GB, Windows 10 |
| Engine | Godot 4.5.1 (editor binary, console variant), headless workers with `--fixed-fps 120` |
| Load | The PC also ran other agents' build and test jobs, with the CPU at 40–100 % throughout. Results do not depend on load (fixed-step workers); throughput and timing numbers do, and are pessimistic. |

## Why every number was regenerated

An independent review of the Lab found defects that changed what the numbers meant. They are
fixed, and every run in this folder was made again with the fixed code:

- **Evaluation episodes were not all distinct.** The arena's standard spawns ignored the seed,
  so a deterministic policy against the standing dummy replayed one episode and each copy was
  counted as an independent sample; "swapped" did not swap on The Gullet. Standard spawns are
  now jittered per seed (±0.35 m, ±25°) and swapped really exchanges the sides.
- **Random spawns placed the opponent on one fixed point** on The Gullet (a format-2 arena); only
  the learner's position was random. The opponent is now placed `dist` metres away, as
  documented. This changed the training episodes, so all training runs were redone.
- **Intervals used 1.96 for any n** (zero width for one episode). They are now Student-t
  intervals, and two conditions played on the same episodes are compared with a paired test.
- **ES selection ignored the generations after the last validation step.** It now validates θ
  and the last elite when training stops, and says so when the starting network is kept.
- **Behaviour cloning reported its early-stopping split as "held-out accuracy".** Recorded
  episodes are now split train / validation / test, and the test accuracy is reported.
- **Recording the same teacher twice stored identical episodes**, which could leak into the
  validation split. Recordings now continue the dataset's seed numbering, and copies load once.

## Files

| Path | Contents |
|---|---|
| `jobs/*.json` | The exact job files. Each one runs again with the command under "Reproduce". |
| `runs/<run>/` | `report.json` (final evaluation), `metrics.jsonl` (learning curve), `job_effective.json` (job after normalisation), `progress.json` / `status.json` (final counters, including helper shares re-run as `reassigned` / `late`), and the worker logs as `worker_r<k>.log.txt`. Paths are relative to the game folder, as the commands gave them. |
| `summary.json` | Every run's key numbers, produced by `src/test/lab/lab_evidence_summary.gd`. |
| `curves/*.jpg` | The Lab's **Runs** tab for each training run: state, counters, learning curve, checkpoints and report. |
| `bench/*.json` | Inference cost, single-process throughput, an A/B inference comparison with the build before this branch, and CPU-share measurements. |
| `ui/` | Lab screen captures, plus `ui_report.json`: frame times and pause/resume/cancel driven through the UI. |
| `match/` | "Spectate this bot" and "Fight this bot" with the shipped clone, plus `match_report.json`. |
| `determinism/` | The same ES job with 3 processes and with 1 (before and after each merge of main), compared, plus a bot evaluation re-run after the last merge. |

Shipped sample policies built from these runs are in `game/content/core/policies/`:
`dev_biped_es_drill` (from `es_drill_seed303`), `dev_biped_bc_regular` (from `bc_regular`) and
`dev_biped_bces_aggressive` (the last mean network of `bc_then_es`, see section 3). Section 4
evaluates the shipped files themselves.

## 1. Evolution strategies on the controlled drill task (3 seeds)

**Task.** `dev_biped` against a standing dummy that never moves or fights back, in 6-second
rounds. Training uses random spawns 2–4.5 m apart. The reward is the *Drill* preset: damage
dealt + hits + 0.5 × approach. Approach is potential-based, so it cannot be farmed.

**Learner.** An MLP 118-32-32-21 (tanh, 5,557 parameters) with near-zero initial outputs
(`out_scale` 0.01), acting by argmax.

**ES.** 12 mirrored pairs (24 candidates) × 1 episode per generation, σ 0.05, Adam lr 0.02,
25 generations. Each generation runs 3 worker processes × 2 worlds.

**Selection and test.** Every 5 generations, θ and the generation's best candidate play
8 validation episodes, and the best validated network is kept (the starting network competes
too). The final report plays 20 held-out test episodes — 10 random spawns and 10 jittered
standard/swapped corner spawns that training never uses — with both the starting network and
the selected one, and the hand-written scripted "jabber" plays the same episodes. Differences are
paired over those 20 episodes.

| Seed | Starting network: test reward (95 % CI) | Trained: test reward (95 % CI) | Trained − start, paired (95 % CI) | Hits / damage per episode (start → trained) | Scripted jabber, same episodes | Trained − jabber, paired | Selected | Wall time |
|---|---|---|---|---|---|---|---|---|
| 101 | −0.82 (−0.92..−0.72), win 0 % | **47.63** (41.92..53.34), win 100 % | **+48.45** (42.77..54.13), t = 17.9 | 0.0 / 0.0 → 2.8 / 43.1 | 51.83 (48.44..55.22) | −4.20 (−9.63..1.23) | gen 5, elite | 279 s |
| 202 | 13.71 (6.81..20.61), win 50 % | **56.84** (50.73..62.95), win 100 % | **+43.13** (35.16..51.10), t = 11.3 | 0.9 / 11.5 → 3.5 / 51.6 | 50.96 (47.78..54.14) | +5.88 (−0.31..12.08) | gen 10, elite | 258 s |
| 303 | 10.27 (8.70..11.83), win 100 % | **46.93** (37.43..56.43), win 100 % | **+36.67** (27.26..46.07), t = 8.2 | 1.6 / 9.6 → 3.4 / 41.9 | 50.70 (47.09..54.30) | −3.76 (−13.78..6.26) | gen 25, elite | 267 s |

(n = 20 test episodes per row, all distinct. "Win" against the dummy is a decision on damage,
because the dummy never attacks.)

- **All three seeds improved, on episodes training never saw.** The paired gain is +36.7 to
  +48.5 reward (mean **+42.7**), every 95 % interval far above zero (t 8.2–17.9).
- **The population learned, not just the selected network.** Mean training fitness over the
  first 3 generations vs the last 3:
  - seed 101: 9.3 → 46.2
  - seed 202: 9.7 → 58.3
  - seed 303: 9.2 → 44.8

  Validation reward of θ went from −0.68, 33.0 and 10.2 at generation 0 to 51.8, 51.6 and 57.9
  at generation 25 (curves in `curves/es_drill_seed*.jpg` and `runs/*/metrics.jsonl`).
- **What it learned.** Each seed learned to close the distance and land heavy blows: about 3
  hits for 42–52 damage per 6-second drill, where the jabber lands 9 light hits for about 40.
  On reward the trained policies are level with the hand-written jabber: none of the three
  paired differences is significant.
- **Determinism** (`determinism/seed101_processes_and_merge.json`). Seed 101 was run again in
  one process for 10 generations (`runs/es_drill_seed101_1worker`), before and after each merge
  of main (`..._postmerge` is the first). All of these runs have identical per-generation fitness
  for generations 1–10, identical validation rewards, the same selected network (generation 5's
  elite) and the same test results; the one-process runs have identical metric lines apart
  from their wall-clock fields.
  (Helpers send their results as JSON text, so double-precision statistics of the 3-process run
  can differ in the last printed digit.) Distributing episodes over processes does not change
  the result, and the merge did not change the simulation.

## 2. Behaviour cloning

**Recording.** A scripted teacher plays as `dev_biped` against Bot: Rookie, with 20-second
rounds in the sparring arena. Every 15 Hz decision is labelled with the act_v1 inverse mapping.
Each episode is stored with its recording index and seed; the reports confirm that every
recorded episode reached the dataset (`episodes_stored` 90 and 60; the helpers' shards were
committed: 10 and 8).

**Training.** An MLP 118-64-64-21 (13,141 parameters) trained with masked cross-entropy on the
move and button heads. The recorded matches are split by whole episodes: 60 % train, 20 %
validation (early stopping, patience 8), 20 % test (reported only). Minibatch 128, Adam
lr 0.003.

**Test.** Accuracy is measured on the test matches. Then the clone and the teacher play the
same 12 new test matches against Rookie; the clone samples its actions.

| | Teacher: Bot Regular (`bc_regular`) | Teacher: scripted jabber (`bc_jabber`) |
|---|---|---|
| Recorded | 90 matches, 26,912 decisions. Teacher won 68 % [58–77]. | 60 matches, 17,170 decisions. Teacher won 57 % [44–68]. |
| Split: matches (decisions) train / validation / test | 54 / 18 / 18 (16,117 / 5,400 / 5,395) | 36 / 12 / 12 (10,517 / 3,226 / 3,427) |
| Validation loss: untrained → best | 4.67 → **1.61** (epoch 13 of 21, early stop) | 4.71 → **0.39** (epoch 15 of 23, early stop) |
| Test accuracy: move / button / both | **67.4 % / 82.7 % / 55.6 %** | **95.6 % / 88.0 % / 84.2 %** |
| Majority-class baseline on the test matches | 39.6 % / 75.8 % / 28.5 % | 80.0 % / 88.1 % / 70.1 % |
| Untrained network on the test matches: both heads | 1.6 % | 0.0 % |
| Action-distribution distance to the teacher (TVD, 0 = identical): move / button | 0.093 / 0.063 | 0.049 / 0.007 |
| Clone in 12 test matches | reward 83.0 ± 34.6, win 67 % [39–86] | reward 64.5 ± 31.1, win 42 % [19–68] |
| Teacher in the same 12 matches | reward 64.0 ± 26.5, win 67 % [39–86] | reward 44.9 ± 27.7, win 17 % [5–45] |
| Clone − teacher, paired (95 % CI) | +19.1 (−9.9..48.0), not significant | +19.6 (−10.7..49.8), not significant |

- **Training worked on both datasets.** Validation loss fell 66 % and 92 %, and on test
  matches the clones beat the majority class clearly on the move head (+28 and +16 points) and
  for both heads together (+27 and +14 points).
- **The button head is the weak spot.** The jabber's buttons are 88 % "none", and its clone's
  button accuracy (88.0 %) is no better than always predicting "none" (88.1 %). The Regular
  clone's button head beats its baseline by 7 points.
- **The clones behave like their teachers.** The action-frequency distances are small. In
  matches, the clones' outcomes are statistically indistinguishable from the teachers' (n = 12,
  paired intervals include 0): no evidence that a clone is stronger than its teacher.

## 3. Clone, then evolve (BC → ES)

**Setup.** The run starts from the Bot Regular clone above. ES optimises the *Aggressive*
objective against Rookie in 20-second matches: 12 pairs, σ 0.02, lr 0.01, 16 generations,
3 worker processes; validation every 4 generations on 8 matches.

**Result: ES did not improve the clone in this run.** The clone's validation reward (86.6) was
never beaten: θ scored 59.3, 78.6, 82.4 and 75.6 at generations 4, 8, 12 and 16, the elites
56.1, 52.7, 67.5 and 70.6. Population fitness stayed flat (68.1 over the first 3 generations,
70.4 over the last 3). The run therefore kept the clone, and its report and message say so
(`selected_initial`: "no trained network beat the starting network on validation"); its final
test compares the clone with itself (72.3 ± 30.2, win 80 % [58–92] on 20 test matches; Bot:
Regular on the same matches 72.6 ± 24.4, win 85 % [64–95]).

Matches against a bot are noisy and 16 generations is a short run. The shipped
`dev_biped_bces_aggressive` is this run's last mean network (`final.policy.json`, not selected),
so the sample shows what 16 generations changed; section 4 tests it against the clone: no
significant difference. Its description says so.

## 4. The shipped sample policies on fresh test seeds

Evaluation jobs (`jobs/eval_*.json`) play the shipped files themselves, with their saved play
settings, on test seeds of new job seeds (5001–5003): 15 random-spawn and 15 jittered
standard/swapped episodes per policy (n = 30), each compared on the same episodes.

| Policy, opponent | Policy: reward (95 % CI), win | Comparison on the same episodes | Paired difference (95 % CI) | Scripted reference, same episodes: reward; paired difference |
|---|---|---|---|---|
| Drill Hitter (ES), standing dummy | **51.3** (44.3..58.3), 100 % [89–100] | untrained network of the same shape: 14.3 (14.1..14.5) | **+37.0** (29.9..44.1), t = 10.7 | jabber 50.3 (48.2..52.3); +1.0 (−6.0..8.1) |
| Regular Clone (BC), Bot: Rookie | 78.9 (68.2..89.5), 83 % [66–93] | untrained network: 71.9 (60.0..83.7), 70 % [52–83] | +7.0 (−8.4..22.3), not significant | Bot Regular 65.7 (55.8..75.6), 70 %; +13.2 (−0.5..26.8) |
| Regular Clone + ES, Bot: Rookie | 83.4 (73.2..93.5), 87 % [70–95] | the BC clone: 80.7 (70.3..91.0), 80 % [63–90] | +2.7 (−10.7..16.2), not significant | Bot Regular 69.6 (58.5..80.8), 70 %; +13.7 (−0.8..28.3) |

- The drill policy clearly learned its task: +37 over an untrained network of the same shape,
  and level with the hand-written jabber.
- Against Rookie, the Aggressive reward does not separate the clone from an untrained network
  with 30 matches: Rookie is weak enough that random button presses win 70 % of the time. The
  clone's evidence is imitation (section 2), not a higher reward against Rookie.
- The BC → ES sample is not measurably different from the clone it started from.

## 5. Measurements

**Inference cost** (LAB-09; `bench/inference_*.json`). 8 policy-controlled fighters in a live
match, decisions staggered at 15 Hz.

| Network | Per 120 Hz tick, 8 fighters | Per decision (encode + forward) | Worst decision | Machine load |
|---|---|---|---|---|
| 32×32 (5,557 params) | **263.2 µs** | 259.4 µs (158.0 + 78.3) | 1,894 µs | 86 % |
| 64×64 (13,141 params) | **340.0 µs** | 335.1 µs (164.4 + 145.5) | 2,176 µs | 93 % |

These wall-clock timings were taken with the PC saturated by other jobs, and they exceed the
documented budget of 250 µs per tick. Eight 32×32 runs of this build over the session gave
211–326 µs. Run
alternately with the build from before this branch under the same load
(`bench/inference_ab.json`), the old build measured 187–302 µs and this one 213–308 µs: the
inference code (unchanged by this branch) costs the same. An earlier measurement of the same
code on a quieter PC gave 138.5 µs. `test_policy_inference.gd` checks the 32×32 network on
every test run, with a 1.5× allowance for a busy machine.

**Training throughput** (simulated seconds per wall second; episodes include world setup and
teardown):

| Workload | Processes × worlds | Sim speed | Episodes / hour |
|---|---|---|---|
| Bench: policy vs Regular/jabber, 10 s rounds (`bench/throughput_1proc.json`, at 100 % load) | 1 × 2 | 7.4× | 2,400 |
| ES drill, 6 s rounds, `es_drill_seed101_1worker` | 1 × 2 | 9.1× | 5,481 |
| ES drill, 6 s rounds, `es_drill_seed101` / `202` / `303` | 3 × 2 | 16.1× / 17.4× / 16.8× | 9,643 / 10,440 / 10,101 |
| Recording, 20 s matches, `rec_regular` / `rec_jabber` | 3 × 2 | 18.8× / 15.1× | 3,397 / 2,864 |
| BC → ES, 20 s matches, `bc_then_es` | 3 × 2 | 17.9× | 3,268 |

Throughput scales with worker processes, not worlds per process; on this loaded PC three
processes gave about 1.8× one process. The simulation is single-threaded GDScript + Jolt per
process. BC training itself is CPU-bound GDScript: about 11 s per epoch over 16k decisions with a
64×64 network (including the validation pass). No helper share had to be re-run in any of these
runs (`reassigned` 0, `late` 0).

**CPU share** (`bench/cpu_share.json`). One ES worker at three settings, its process CPU time
taken from the OS over 20 s each, with the PC at 60–87 % load:

| `cpu_share` | Main-thread work per wall time (worker report) | Process CPU, cores | Episodes / minute |
|---|---|---|---|
| 1.00 | 1.00 | 1.31 | 72 |
| 0.50 | 0.50 | 0.44 | 36 |
| 0.25 | 0.25 | 0.19 | — (the 20 s window ended before the next batch finished) |

The worker now counts whole frames (script, physics step, engine overhead) and pays off the
sleep it owes in whole milliseconds by the time it really slept, so its main thread's long-run
share matches the setting and throughput halves at 0.5. Engine threads add about 30 % of a core
at full speed and are not limited separately.

**Game responsiveness while training** (`ui/ui_report.json`). The Lab screen ran windowed
(60 fps vsync):

- First, 20 s with no worker as a baseline.
- Then 40 s while a training run started from the Train tab ran one worker at normal
  priority. That is the worst case for the game; the default is low priority.

| | Median | p95 | p99 | Frames > 33 ms | Longest frame |
|---|---|---|---|---|---|
| No worker (baseline) | 16.7 ms | 18.4 ms | 19.3 ms | 0 % | 20.0 ms |
| One worker training | 16.7 ms | 18.8 ms | 22.6 ms | 0.5 % | 168 ms |

A first capture just before this one had one 3.0 s frame when the Runs tab first appeared while
the worker started (likely a one-time cache warm-up on a fresh profile); the repeat above had
none. The screen's own polling of the run files costs **1.9 ms** (median, 2.8 ms max) every 0.5 s.

**Driving the run from the UI** works: pause → `paused` (no episodes run while paused) →
resume → `running` → cancel → `cancelled`, all through the screen's own buttons, as captured
in `ui/run_*.jpg`.

**Spectate and fight a shipped policy** (`match/match_report.json`), normal `MatchScene`
matches with fighter kind `policy`:

- **Spectate.** "Regular Clone (BC)" vs Bot: Rookie for 12 s of a 60 s round: the clone landed
  6 hits for 43 damage and took 1 hit for 3. Matches differ from run to run because the clone
  samples its actions.
- **Fight.** The clone against an idle local player: 9 hits, 74 damage in 12 s.

## Reproduce

From the repository root, with the Godot 4.5.1 console binary as `$g`. `--path game` makes the
game folder Godot's working directory, so every relative path below starts with `../` (the
runs land in `runs/`, which git ignores). These are the exact commands that made this folder's
runs; `test_lab_docs.gd` checks that every such command resolves its paths from game/.

```powershell
$g = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe"
# 1. ES on the drill (three seeds), and seed 101 again in one process (determinism check)
& $g --headless --path game --fixed-fps 120 -- --lab-worker ../docs/evidence/lab/jobs/es_drill_seed101.json --lab-out ../runs/es_drill_seed101 --user-root ../runs/home
& $g --headless --path game --fixed-fps 120 -- --lab-worker ../docs/evidence/lab/jobs/es_drill_seed202.json --lab-out ../runs/es_drill_seed202 --user-root ../runs/home
& $g --headless --path game --fixed-fps 120 -- --lab-worker ../docs/evidence/lab/jobs/es_drill_seed303.json --lab-out ../runs/es_drill_seed303 --user-root ../runs/home
& $g --headless --path game --fixed-fps 120 -- --lab-worker ../docs/evidence/lab/jobs/es_drill_seed101_1worker.json --lab-out ../runs/es_drill_seed101_1worker --user-root ../runs/home
# 2. record the teachers, clone them (same --user-root: the BC jobs find the datasets by id)
& $g --headless --path game --fixed-fps 120 -- --lab-worker ../docs/evidence/lab/jobs/record_teacher_regular.json --lab-out ../runs/rec_regular --user-root ../runs/home
& $g --headless --path game --fixed-fps 120 -- --lab-worker ../docs/evidence/lab/jobs/record_teacher_jabber.json --lab-out ../runs/rec_jabber --user-root ../runs/home
& $g --headless --path game --fixed-fps 120 -- --lab-worker ../docs/evidence/lab/jobs/bc_clone_regular.json --lab-out ../runs/bc_regular --user-root ../runs/home
& $g --headless --path game --fixed-fps 120 -- --lab-worker ../docs/evidence/lab/jobs/bc_clone_jabber.json --lab-out ../runs/bc_jabber --user-root ../runs/home
# 3. BC -> ES, starting from ../runs/bc_regular/best.policy.json (model.init_policy in the job)
& $g --headless --path game --fixed-fps 120 -- --lab-worker ../docs/evidence/lab/jobs/bc_then_es.json --lab-out ../runs/bc_then_es --user-root ../runs/home
# 4. evaluate the shipped sample policies (built-in ids) on fresh test seeds
& $g --headless --path game --fixed-fps 120 -- --lab-worker ../docs/evidence/lab/jobs/eval_es_drill.json --lab-out ../runs/eval_es_drill --user-root ../runs/home
& $g --headless --path game --fixed-fps 120 -- --lab-worker ../docs/evidence/lab/jobs/eval_bc_regular.json --lab-out ../runs/eval_bc_regular --user-root ../runs/home
& $g --headless --path game --fixed-fps 120 -- --lab-worker ../docs/evidence/lab/jobs/eval_bces_aggressive.json --lab-out ../runs/eval_bces_aggressive --user-root ../runs/home
# benches and the summary
& $g --headless --path game --fixed-fps 120 -- --lab-worker --lab-bench inference --lab-out ../runs/bench32.json
& $g --headless --path game --fixed-fps 120 -- --lab-worker --lab-bench inference --hidden 64,64 --lab-out ../runs/bench64.json
& $g --headless --path game --fixed-fps 120 -- --lab-worker --lab-bench throughput --lab-out ../runs/throughput.json
& $g --headless --path game -s res://src/test/lab/lab_evidence_summary.gd -- --runs "../runs/es_drill_seed101;../runs/es_drill_seed202;../runs/es_drill_seed303;../runs/es_drill_seed101_1worker;../runs/rec_regular;../runs/rec_jabber;../runs/bc_regular;../runs/bc_jabber;../runs/bc_then_es;../runs/eval_es_drill;../runs/eval_bc_regular;../runs/eval_bces_aggressive" --out ../runs/summary.json
# windowed checks (not part of --test); give absolute folders
& $g --path game -s res://src/test/lab/lab_ui_capture.gd -- --user-root <fresh dir> --out <dir> --train-seconds 40
& $g --path game -s res://src/test/lab/lab_match_capture.gd -- --user-root <fresh dir> --out <dir> --policy dev_biped_bc_regular
& $g --path game -s res://src/test/lab/lab_ui_capture.gd -- --user-root <dir whose lab/runs holds run folders> --out <dir> --runs
```

The shipped sample policies were published from these runs with
`--lab-worker --lab-publish ../runs/<run>/<file>.policy.json --id <id> --name <name> --description <text> --lab-out <file>`
(es_drill_seed303 `best` → `dev_biped_es_drill`, bc_regular `best` → `dev_biped_bc_regular`,
bc_then_es `final` → `dev_biped_bces_aggressive`); step 4 needs them in
`game/content/core/policies/`.

A fresh fixed-step worker process makes the same job and seed reproduce the same run on the
same build and machine — record into a fresh `--user-root`, since a dataset that already holds
episodes continues its numbering. A different machine or build may differ slightly.
