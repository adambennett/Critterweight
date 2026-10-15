# Creatures — bodies, naming scheme and measurements

Physical bodies for the six fighters (`game/content/core/creatures/`), two minions
(`game/content/core/minions/`) and three bosses (`game/content/core/bosses/`). Every file is a complete
creature (body, stats, `art`, **stub** moves marked `"_stub": true` — the lead/kit authors replace
movesets against the chain and weapon names below). Models: `docs/ART_PIPELINE.md`.

Conventions (docs/DESIGN.md "Fighter space"): +Z forward, +Y up, +X = the creature's LEFT, metres, kg.
Rest pose = standing on the floor at y = 0, every segment's rest orientation identity, rigid body origin =
joint pivot. The first segment is the root (hover spring + upright spring).

## 1. Naming scheme (stable; author movesets against these)

| Thing | Pattern | Examples |
|---|---|---|
| Segments | `<part>_<side>`; sides `l`/`r`, quadruped/crab legs `fl fr bl br`; upper/lower limbs `uarm_l`/`farm_l`, `thigh_l`/`shin_l`, `uwing_l`/`lwing_l`, `uclaw_r`/`claw_r`, `uleg_fl`/`lleg_fl`; serpent spine `head, body1 … bodyN` (body1 nearest the head), bosses add `neck1/neck2`, `chain`, `plug` | `pelvis`, `chest`, `head`, `tail`, `coil`, `antenna_l` |
| limb2 chains | `arm_l`/`arm_r` (arms **and** crab claws), `wing_l`/`wing_r`, `leg_l`/`leg_r`, `leg_fl`/`leg_fr`/`leg_bl`/`leg_br` | legs carry `"leg": true` + `group` (0/1 alternate) |
| Weapons | `fist_l/r`, `knee_l/r`, `foot_l/r`, `head`, `belly`, `shoulder_l/r`, `claw_crusher`/`claw_cutter` (Dredge), `claw_gavel` (Snappington), `shell_edge`, `shell_side_l/r`, `shell_dome`, `wing_edge_l/r`, `wing_mid_l/r`, `beak`, `body`, `snout`, `horn`, `hoof_fl/fr/bl/br`, `body_slam`, `fang`, `jaws`, `tail_tip`, `coil`, `coil_low`, `body_upper`, `slap_l/r`, `hug`, `cap`, `antenna_l/r`, `pipe`, `pipe_mid`, `lid`, `paw_*`, `nub_l/r` | per creature below |
| Poses | `stance`, `guard` (required by the engine); moves add their own keyframes | |
| Hurt multipliers | heads 1.3–1.5, eyestalks 1.5, shells/plates 0.6–0.7, limbs 0.4–0.7, core 0.9–1.0 | |
| Guard flags | parts that physically block while guarding: arms/claws/wings/lid, the crab shells | |

### IK poles

Each limb2 chain's `pole` is the direction its elbow/knee bends toward. **It must contain the rest bend**
(the perpendicular from the shoulder→effector line to the rest elbow); otherwise the IK fights the rest
pose and applies a constant torque (Dredge tilted 13° and drifted until this was fixed). `BodyDef` now
derives the pole from the rest geometry when a chain omits it; straight-at-rest limbs (Stoke's arms) must
state one. Poses may override poles per target.

### Joint-spring limits that shape the bodies

Jolt's 6-DOF angular springs are Euler-XYZ springs (D-009): rotations near ±90° about the middle (Y)
axis, or large compound rotations (> ~70°) from rest, settle at false equilibria. Bodies are therefore
authored with their **rest pose already close to the fighting posture** (Dredge's claws forward and
raised, Gusto's wings half-folded in `stance`), and movesets should keep per-joint rotations within
~70° of rest, favouring X (pitch) and Z (roll) for the big swings. Kit authors: see the per-creature notes.

### Spawn gaps

Long bodies interpenetrate at the probe's default 1.1 m spawn gap (Dredge's claws reach 1.1 m, Dozer's
snout 1.27 m, Bilge 2.4 m). Use `--gap 3.2` (fighters) / `--gap 6` (bosses) when probing.

## 2. Probe results (stand / walk, `--fixed-fps 120`, 2026-10-15)

| Creature | Stand uprightness (min after 0.6 s) | Head height | Walk uprightness | Max |ω| walking |
|---|---|---|---|---|
| f_stoke | 1.000 | 1.26–1.27 | 0.992 | 11.7 |
| f_dredge | 1.000 | 0.82 | 0.995 | 11.1 |
| f_gusto | 0.995 | 1.63–1.66 | 0.988 | 13.1 |
| f_dozer | 1.000 | 0.76–0.77 | 0.992 | 13.7 |
| f_slurry | 1.000 | 1.42 | 0.991 | 7.7 |
| f_jitters | 1.000 | 0.82 (no head segment: root + 0.4) | 0.990 | 1.6 |
| npc_kid_lamprey | 1.000 | 1.09 | 0.995 | 3.8 |
| npc_scrapling | 1.000 | 0.68 | 0.928 | 23.0 |
| npc_blister | 1.000 | 0.73 | 0.992 | 12.3 |
| boss_bilge | 1.000 | 1.63–1.65 | 0.991 | 11.7 |
| boss_conduit | 1.000 | 2.91–2.92 | 0.992 | 6.5 |
| boss_snappington | 1.000 | 1.17 | 0.995 | 8.6 |

(Max angular velocity is the fastest segment while stepping/turning; the standing values are ≤ 2.9.)

## 3. Per-creature notes

### Stoke — biped, 12 segments, 85 kg, 1.5 m (crest to 1.65)
Root `pelvis` (hover 0.62). `chest` carries the boiler + shoulders, `head` the stovepipe crest. Chains
`arm_l/arm_r` (`uarm_*` + `farm_*`, fists at the effector), `leg_l/leg_r`. Weapons `fist_l/fist_r`
(hit spheres r 0.18 around the 0.12 m wraps — kit pass, see docs/kits/f_stoke.md), `knee_l/r`, `foot_l/r`, `head`, `belly` (furnace door, Steam Vent origin),
`shoulder_l/r`. Stance = boxing guard (fists chin-high, 5° forward lean); guard = fists in front of the
face, −6 cm crouch. Fist reach from the root ≈ 1.0 m straight (shoulder 0.38 m out, arm 0.65 m) — the
ROSTER's 1.0–1.1 m with the chest turn/lunge; within the 1.6 m cap. Gore: a tooth.

### Dredge — crab, 14 segments, 160 kg, 1.11 m tall, 2.0 m wide
Root `shell` (hover 0.55, `part: shell`, guard). `head` = the eyestalks (hurt 1.5). Claws are chains
`arm_l` (cutter: `uclaw_l` + `claw_l`) and `arm_r` (crusher: `uclaw_r` + `claw_r`, 26 kg), rest pose
already forward-and-raised. Legs `leg_fl/bl/fr/br` (`uleg_*` + `lleg_*`), knees up and out, groups
fl+br / fr+bl. Weapons `claw_crusher` (r 0.11, grab weapon, 1.15 m at rest, 1.59 m max), `claw_cutter`,
`shell_edge` (front rim, Scuttle Check), `shell_side_l/r` (sideways dash), `head`. Gait `crab`
(sideways walking is a stat/AI matter: the gait steps toward any velocity). Gore: the cutter's tip.

### Gusto — avian, 12 segments, 55 kg, 1.84 m (crest 1.9)
Root `torso` (hover 1.05), `neck`, `head` (+ beak capsule), wings as chains `wing_l/wing_r`
(`uwing_*` + `lwing_*`, `part: wing`, guard), long legs `leg_l/leg_r` (`thigh_*` + `shin_*`, knees bend
backward, pole −Z), `tail`. Weapons `wing_edge_l/r` (tips, r 0.17), `wing_mid_l/r`, `beak`, `head`,
`foot_l/r`, `body`. Stance = wings half-folded at the sides (so every wing swing starts close to rest);
guard = wings crossed in front. Wing reach 1.16 m from the root axis to the tip + 0.17 radius; the 1.5 m
ROSTER figure is reached with the torso turn and lunge. Gore: three tail feathers.

### Dozer — quadruped, 13 segments, 140 kg, 1.2 m shoulder, 2.2 m long
Root `chest` (hover 0.78), `pelvis`, `neck`, `head` (skull + shovel box + horn capsule), legs
`leg_fl/fr/bl/br` (`thigh_*` + `shin_*`, groups diagonal), `tail`. Weapons `snout` (r 0.24, 1.26 m
ahead), `horn`, `head`, `hoof_fl/fr/bl/br`, `shoulder_l/r` (plates), `body_slam`. No arm chains: all
attacks are neck/head joint rotations + lunges. Guard = head down (snout as shield), −6 cm. Gore: horn tip.

### Slurry — serpent, 7 segments, 95 kg, 1.72 m reared (crest 1.9), 3.2 m long
Root `body3` (hover 0.30) at the rise; up the S: `body2` → `body1` → `head`; back along the floor:
`body4` → `body5` → `body6` (`part: tail`, waves). Serpent gait waves every `core` segment. No chains:
moves are joint eulers (the Tail Sweep stub rotates `body3…body6` about Y). Weapons `head`, `fang`
(jaws), `tail_tip` (1.46 m behind at rest, 1.56 m max), `coil` (`body2`, grab), `coil_low` (`body3`),
`body_upper` (`body1`, Rear & Crash). Link lengths were trimmed so no weapon point exceeds 1.6 m from the
root even fully straightened. Gore: a fang.

### Jitters — hopper, 6 segments, 45 kg, 0.9 m (bulbs 0.97)
Root `body` (hover 0.42; the hopper gait bounces the hover height by `step_height` 0.18), `coil`
(inner core, `collide: false`), single-segment `arm_l/arm_r` (joint-driven, guard), `antenna_l/r`
(`part: fin`, soft springs). Weapons `slap_l/r`, `body_slam`, `hug` (grab), `cap`, `antenna_l/r`
(Arc Lash origin). No head segment: `head_pos()` falls back to root + 0.4 m. Gore: the battery cap.

### Kid Lamprey (`npc_kid_lamprey`) — biped, 13 segments, ~60 kg, 1.41 m
Tutorial / Ring Sparring partner (kit: `docs/kits/npc_kid_lamprey.md`). Root `pelvis` (hover 0.55),
`chest`, `head` (hood + sucker mouth), sleeves as chains `arm_l/arm_r` (`uarm_*` + `farm_*`), legs
`leg_l/leg_r` (`thigh_*` + `shin_*`, sneaker boxes), eel tail `tail1 → tail2` behind. Weapons
`fist_l/fist_r` (r 0.12), `mouth`, `hood`, `shoulder_l/r`, `body`, `tail_tip`. Stance = sleeves at the
chin; guard = forearms over the hood. Skinned forge model (`tools/forge/defs/creatures/npc_kid_lamprey.js`,
9 000 tris). Gore: a tooth.

### Scrapling (`npc_scrapling`) — biped, 8 segments, 40 kg, 1.0 m
`torso` root (hover 0.42), `head`, single-segment `arm_l` (carries the **lid** box, guard) and `arm_r`
(carries the **pipe** capsule), `leg_l/leg_r` chains. Weapons `pipe` (tip), `pipe_mid`, `lid`, `head`,
`body`. Guard = crouch behind the lid. Gore: the lid.

### Blister (`npc_blister`) — hopper, 3 segments, 25 kg, 0.7 m
`core` root (hover 0.33), `nub_l/nub_r` (`part: tail`, flop). Weapons `body`, `nub_l/r`. Kit (Hop, Belly Bump, Inflate & Pop,
Death Pop, live bomb): `docs/kits/minions.md`.

### Bilge (`boss_bilge`) — quadruped, 15 segments, 320 kg, 2.08 m shoulder, 4 m long
Dozer's plan plus `neck1`, `neck2` and a cosmetic `chain` segment (`part: tail`, `collide: false`,
hangs from the collar). Weapons `jaws`, `head`, `paw_fl/fr/bl/br`, `body_slam`, `belly` (Belly Flop),
`shoulder_l/r`, `tail_tip`. Kit: `docs/kits/bosses.md`.

### Conduit (`boss_conduit`) — serpent, 9 segments, 260 kg, 3.3 m reared, ~7 m long
Slurry's plan with longer links: `body4` root (hover 0.42), `body3…body1`, `head`; rear `body5…body7`,
`plug` (`part: tail`, the three-pin plug box). Weapons `head`, `jaws`, `tail_tip` (plug, r 0.32), `coil`,
`coil_low`, `body_upper`, `body_base`.

### Commissioner Snappington (`boss_snappington`) — crab plan, 16 segments, 480 kg, 1.44 m shell top
`shell` root (hover 0.8, guard), `neck` + `head` (beak), claws `arm_l/arm_r` (`uclaw_*` + `claw_*`; the
right claw carries the gavel), legs `leg_fl/bl/fr/br`, `tail`. Weapons `claw_gavel` (r 0.3), `claw_l`,
`beak`, `head`, `shell_edge`, `shell_dome` (Shell Spin, r 0.9), `shell_side_l/r`, `leg_tip_fl/fr`.
Guard = Withdraw (neck folded 38°, −16 cm). Bosses are exempt from the 1.6 m cap.

## 4. Models (forge output, `tools/forge/build/stats.json`)

| Model | Triangles | Vertices | Size | Gore tris |
|---|---|---|---|---|
| f_stoke | 12 000 | 10 237 | 684 KB | 300 |
| f_dredge | 14 000 | 11 936 | 795 KB | 300 |
| f_gusto | 12 000 | 9 627 | 652 KB | 360 |
| f_dozer | 14 000 | 11 454 | 767 KB | 300 |
| f_slurry | 13 000 | 10 307 | 693 KB | 300 |
| f_jitters | 10 000 | 7 998 | 545 KB | 400 |
| npc_kid_lamprey | 9 000 | 7 658 | 515 KB | — |
| npc_scrapling | 1 900 | 1 819 | 131 KB | 300 |
| npc_blister | 1 500 | 1 045 | 79 KB | 200 |
| boss_bilge | 18 000 | 14 225 | 953 KB | 300 |
| boss_conduit | 16 000 | 14 254 | 942 KB | 300 |
| boss_snappington | 18 000 | 17 403 | 1 148 KB | 500 |
| hub NPCs (8) | 7 000–12 000 each | | 346–763 KB | — |
| crowd fans (2) | 520 each | 411 / 431 | 29 / 31 KB | — |

Vertex counts include the duplicated vertices at crisp colour seams; Godot splits the mesh into one
surface per material (skin / iron / cloth / eye / glow / team ...).

## 5. Measured geometry (generated by `node tools/forge/measure.js --md`)

Chain bone lengths, effector distances and every weapon's rest / maximum distance from the root pivot
(ROSTER reach cap 1.6 m for fighters; `(!)` would mark a fighter weapon over the cap — none remain).

### Dozer (`f_dozer`) — quadruped, 13 segments, 140 kg, top 1.20 m, hover 0.78 m

| Segment | Parent | Part | Mass | Hurt | w0 | Guard |
|---|---|---|---|---|---|---|
| `chest` | - | core | 48 | 0.9 | 30 |  |
| `pelvis` | chest | core | 34 | 0.9 | 30 |  |
| `neck` | chest | core | 8 | 1 | 32 |  |
| `head` | neck | head | 16 | 1.3 | 30 |  |
| `thigh_fl` | chest | leg | 4.5 | 0.6 | 40 |  |
| `shin_fl` | thigh_fl | leg | 3 | 0.5 | 44 |  |
| `thigh_fr` | chest | leg | 4.5 | 0.6 | 40 |  |
| `shin_fr` | thigh_fr | leg | 3 | 0.5 | 44 |  |
| `thigh_bl` | pelvis | leg | 4.5 | 0.6 | 40 |  |
| `shin_bl` | thigh_bl | leg | 3 | 0.5 | 44 |  |
| `thigh_br` | pelvis | leg | 4.5 | 0.6 | 40 |  |
| `shin_br` | thigh_br | leg | 3 | 0.5 | 44 |  |
| `tail` | pelvis | tail | 4 | 0.5 | 22 |  |

| Chain | Segments | Bone 1 | Bone 2 | Leg | Effector from root (rest) | Max IK reach |
|---|---|---|---|---|---|---|
| `leg_fl` | thigh_fl+shin_fl | 0.23 m | 0.26 m | yes | 0.38 m | 0.86 m |
| `leg_fr` | thigh_fr+shin_fr | 0.23 m | 0.26 m | yes | 0.38 m | 0.86 m |
| `leg_bl` | thigh_bl+shin_bl | 0.23 m | 0.24 m | yes | 0.74 m | 1.20 m |
| `leg_br` | thigh_br+shin_br | 0.23 m | 0.24 m | yes | 0.74 m | 1.20 m |

| Weapon | Segment | Radius | Rest distance from root | Max distance from root |
|---|---|---|---|---|
| `snout` | head | 0.24 m | 1.06 m | 1.32 m |
| `horn` | head | 0.11 m | 0.98 m | 1.19 m |
| `head` | head | 0.20 m | 0.86 m | 1.07 m |
| `hoof_fl` | shin_fl | 0.11 m | 0.39 m | 0.97 m |
| `hoof_fr` | shin_fr | 0.11 m | 0.39 m | 0.97 m |
| `hoof_bl` | shin_bl | 0.11 m | 0.74 m | 1.31 m |
| `hoof_br` | shin_br | 0.11 m | 0.74 m | 1.31 m |
| `shoulder_l` | chest | 0.26 m | 0.39 m | 0.68 m |
| `shoulder_r` | chest | 0.26 m | 0.39 m | 0.68 m |
| `body_slam` | chest | 0.40 m | 0.30 m | 0.70 m |

### Dredge (`f_dredge`) — crab, 14 segments, 160 kg, top 1.11 m, hover 0.55 m

| Segment | Parent | Part | Mass | Hurt | w0 | Guard |
|---|---|---|---|---|---|---|
| `shell` | - | shell | 78 | 0.7 | 30 | yes |
| `head` | shell | head | 4 | 1.5 | 26 |  |
| `uclaw_l` | shell | arm | 7 | 0.6 | 44 | yes |
| `claw_l` | uclaw_l | arm | 9 | 0.5 | 46 | yes |
| `uclaw_r` | shell | arm | 10 | 0.6 | 36 | yes |
| `claw_r` | uclaw_r | arm | 16 | 0.6 | 36 | yes |
| `uleg_fl` | shell | leg | 5 | 0.5 | 40 |  |
| `lleg_fl` | uleg_fl | leg | 4 | 0.4 | 44 |  |
| `uleg_bl` | shell | leg | 5 | 0.5 | 40 |  |
| `lleg_bl` | uleg_bl | leg | 4 | 0.4 | 44 |  |
| `uleg_fr` | shell | leg | 5 | 0.5 | 40 |  |
| `lleg_fr` | uleg_fr | leg | 4 | 0.4 | 44 |  |
| `uleg_br` | shell | leg | 5 | 0.5 | 40 |  |
| `lleg_br` | uleg_br | leg | 4 | 0.4 | 44 |  |

| Chain | Segments | Bone 1 | Bone 2 | Leg | Effector from root (rest) | Max IK reach |
|---|---|---|---|---|---|---|
| `arm_l` | uclaw_l+claw_l | 0.37 m | 0.47 m |  | 1.10 m | 1.40 m |
| `arm_r` | uclaw_r+claw_r | 0.42 m | 0.50 m |  | 1.16 m | 1.48 m |
| `leg_fl` | uleg_fl+lleg_fl | 0.43 m | 0.74 m | yes | 1.06 m | 1.73 m |
| `leg_bl` | uleg_bl+lleg_bl | 0.43 m | 0.74 m | yes | 1.06 m | 1.73 m |
| `leg_fr` | uleg_fr+lleg_fr | 0.43 m | 0.74 m | yes | 1.06 m | 1.73 m |
| `leg_br` | uleg_br+lleg_br | 0.43 m | 0.74 m | yes | 1.06 m | 1.73 m |

| Weapon | Segment | Radius | Rest distance from root | Max distance from root |
|---|---|---|---|---|
| `claw_crusher` | claw_r | 0.11 m | 1.15 m | 1.59 m |
| `claw_cutter` | claw_l | 0.11 m | 1.09 m | 1.51 m |
| `shell_edge` | shell | 0.40 m | 0.44 m | 0.84 m |
| `shell_side_l` | shell | 0.36 m | 0.62 m | 0.98 m |
| `shell_side_r` | shell | 0.36 m | 0.62 m | 0.98 m |
| `head` | head | 0.14 m | 0.42 m | 0.74 m |

### Gusto (`f_gusto`) — avian, 12 segments, 55 kg, top 1.84 m, hover 1.05 m

| Segment | Parent | Part | Mass | Hurt | w0 | Guard |
|---|---|---|---|---|---|---|
| `torso` | - | core | 18 | 1 | 30 |  |
| `neck` | torso | core | 3 | 1.1 | 30 |  |
| `head` | neck | head | 4 | 1.4 | 30 |  |
| `uwing_l` | torso | wing | 2.5 | 0.5 | 46 | yes |
| `lwing_l` | uwing_l | wing | 2 | 0.5 | 50 | yes |
| `uwing_r` | torso | wing | 2.5 | 0.5 | 46 | yes |
| `lwing_r` | uwing_r | wing | 2 | 0.5 | 50 | yes |
| `thigh_l` | torso | leg | 6 | 0.6 | 42 |  |
| `shin_l` | thigh_l | leg | 4 | 0.5 | 46 |  |
| `thigh_r` | torso | leg | 6 | 0.6 | 42 |  |
| `shin_r` | thigh_r | leg | 4 | 0.5 | 46 |  |
| `tail` | torso | tail | 1 | 0.4 | 22 |  |

| Chain | Segments | Bone 1 | Bone 2 | Leg | Effector from root (rest) | Max IK reach |
|---|---|---|---|---|---|---|
| `wing_l` | uwing_l+lwing_l | 0.41 m | 0.53 m |  | 1.14 m | 1.16 m |
| `wing_r` | uwing_r+lwing_r | 0.41 m | 0.53 m |  | 1.14 m | 1.16 m |
| `leg_l` | thigh_l+shin_l | 0.41 m | 0.48 m | yes | 0.15 m | 1.00 m |
| `leg_r` | thigh_r+shin_r | 0.41 m | 0.48 m | yes | 0.15 m | 1.00 m |

| Weapon | Segment | Radius | Rest distance from root | Max distance from root |
|---|---|---|---|---|
| `wing_edge_l` | lwing_l | 0.17 m | 1.10 m | 1.33 m |
| `wing_edge_r` | lwing_r | 0.17 m | 1.10 m | 1.33 m |
| `wing_mid_l` | lwing_l | 0.12 m | 0.85 m | 1.28 m |
| `wing_mid_r` | lwing_r | 0.12 m | 0.85 m | 1.28 m |
| `beak` | head | 0.10 m | 0.50 m | 1.03 m |
| `head` | head | 0.14 m | 0.28 m | 0.88 m |
| `foot_l` | shin_l | 0.12 m | 0.21 m | 1.18 m |
| `foot_r` | shin_r | 0.12 m | 0.21 m | 1.18 m |
| `body` | torso | 0.26 m | 0.20 m | 0.47 m |

### Jitters (`f_jitters`) — hopper, 6 segments, 45 kg, top 0.97 m, hover 0.42 m

| Segment | Parent | Part | Mass | Hurt | w0 | Guard |
|---|---|---|---|---|---|---|
| `body` | - | core | 30 | 1 | 30 |  |
| `coil` | body | core | 3 | 1.2 | 40 |  |
| `arm_l` | body | arm | 3 | 0.5 | 50 | yes |
| `arm_r` | body | arm | 3 | 0.5 | 50 | yes |
| `antenna_l` | body | fin | 3 | 1.2 | 24 |  |
| `antenna_r` | body | fin | 3 | 1.2 | 24 |  |

| Weapon | Segment | Radius | Rest distance from root | Max distance from root |
|---|---|---|---|---|
| `slap_l` | arm_l | 0.10 m | 0.66 m | 0.77 m |
| `slap_r` | arm_r | 0.10 m | 0.66 m | 0.77 m |
| `body_slam` | body | 0.36 m | 0.20 m | 0.56 m |
| `hug` | body | 0.30 m | 0.30 m | 0.60 m |
| `cap` | body | 0.10 m | 0.00 m | 0.46 m |
| `antenna_l` | antenna_l | 0.07 m | 0.21 m | 0.61 m |
| `antenna_r` | antenna_r | 0.07 m | 0.21 m | 0.61 m |

### Slurry (`f_slurry`) — serpent, 7 segments, 95 kg, top 1.72 m, hover 0.30 m

| Segment | Parent | Part | Mass | Hurt | w0 | Guard |
|---|---|---|---|---|---|---|
| `body3` | - | core | 20 | 0.9 | 28 |  |
| `body2` | body3 | core | 14 | 1 | 30 |  |
| `body1` | body2 | core | 12 | 1 | 32 |  |
| `head` | body1 | head | 12 | 1.4 | 32 |  |
| `body4` | body3 | core | 14 | 0.8 | 26 |  |
| `body5` | body4 | core | 12 | 0.7 | 24 |  |
| `body6` | body5 | tail | 11 | 0.6 | 24 |  |

| Weapon | Segment | Radius | Rest distance from root | Max distance from root |
|---|---|---|---|---|
| `head` | head | 0.16 m | 0.28 m | 1.53 m |
| `fang` | head | 0.10 m | 0.44 m | 1.59 m |
| `tail_tip` | body6 | 0.10 m | 1.46 m | 1.58 m |
| `coil` | body2 | 0.30 m | 0.15 m | 0.92 m |
| `coil_low` | body3 | 0.30 m | 0.08 m | 0.52 m |
| `body_upper` | body1 | 0.20 m | 0.14 m | 1.17 m |

### Stoke (`f_stoke`) — biped, 12 segments, 85 kg, top 1.53 m, hover 0.62 m

| Segment | Parent | Part | Mass | Hurt | w0 | Guard |
|---|---|---|---|---|---|---|
| `pelvis` | - | core | 12 | 0.9 | 30 |  |
| `chest` | pelvis | core | 26 | 1 | 32 |  |
| `head` | chest | head | 7 | 1.4 | 28 |  |
| `uarm_l` | chest | arm | 4 | 0.5 | 44 | yes |
| `farm_l` | uarm_l | arm | 4.5 | 0.4 | 48 | yes |
| `uarm_r` | chest | arm | 4 | 0.5 | 44 | yes |
| `farm_r` | uarm_r | arm | 4.5 | 0.4 | 48 | yes |
| `thigh_l` | pelvis | leg | 6 | 0.6 | 40 |  |
| `shin_l` | thigh_l | leg | 4.5 | 0.5 | 44 |  |
| `thigh_r` | pelvis | leg | 6 | 0.6 | 40 |  |
| `shin_r` | thigh_r | leg | 4.5 | 0.5 | 44 |  |
| `tail` | pelvis | tail | 2 | 0.5 | 20 |  |

| Chain | Segments | Bone 1 | Bone 2 | Leg | Effector from root (rest) | Max IK reach |
|---|---|---|---|---|---|---|
| `arm_l` | uarm_l+farm_l | 0.33 m | 0.32 m |  | 0.38 m | 1.03 m |
| `arm_r` | uarm_r+farm_r | 0.33 m | 0.32 m |  | 0.38 m | 1.03 m |
| `leg_l` | thigh_l+shin_l | 0.27 m | 0.26 m | yes | 0.15 m | 0.67 m |
| `leg_r` | thigh_r+shin_r | 0.27 m | 0.26 m | yes | 0.15 m | 0.67 m |

| Weapon | Segment | Radius | Rest distance from root | Max distance from root |
|---|---|---|---|---|
| `fist_l` | farm_l | 0.18 m | 0.38 m | 1.16 m |
| `fist_r` | farm_r | 0.18 m | 0.38 m | 1.16 m |
| `knee_l` | shin_l | 0.11 m | 0.19 m | 0.78 m |
| `knee_r` | shin_r | 0.11 m | 0.19 m | 0.78 m |
| `foot_l` | shin_l | 0.10 m | 0.23 m | 0.82 m |
| `foot_r` | shin_r | 0.10 m | 0.23 m | 0.82 m |
| `head` | head | 0.16 m | 0.22 m | 1.02 m |
| `belly` | chest | 0.30 m | 0.32 m | 0.82 m |
| `shoulder_l` | chest | 0.16 m | 0.32 m | 0.81 m |
| `shoulder_r` | chest | 0.16 m | 0.32 m | 0.81 m |

### Blister (`npc_blister`) — hopper, 3 segments, 25 kg, top 0.68 m, hover 0.33 m

| Segment | Parent | Part | Mass | Hurt | w0 | Guard |
|---|---|---|---|---|---|---|
| `core` | - | core | 21 | 1 | 26 |  |
| `nub_l` | core | tail | 2 | 0.8 | 18 |  |
| `nub_r` | core | tail | 2 | 0.8 | 18 |  |

| Weapon | Segment | Radius | Rest distance from root | Max distance from root |
|---|---|---|---|---|
| `body` | core | 0.30 m | 0.10 m | 0.40 m |
| `nub_l` | nub_l | 0.07 m | 0.36 m | 0.53 m |
| `nub_r` | nub_r | 0.07 m | 0.36 m | 0.53 m |

### Scrapling (`npc_scrapling`) — biped, 8 segments, 40 kg, top 0.97 m, hover 0.42 m

| Segment | Parent | Part | Mass | Hurt | w0 | Guard |
|---|---|---|---|---|---|---|
| `torso` | - | core | 17 | 1 | 32 |  |
| `head` | torso | head | 5 | 1.4 | 30 |  |
| `arm_l` | torso | arm | 5 | 0.4 | 44 | yes |
| `arm_r` | torso | arm | 4 | 0.4 | 44 |  |
| `thigh_l` | torso | leg | 2.5 | 0.6 | 42 |  |
| `shin_l` | thigh_l | leg | 2 | 0.5 | 46 |  |
| `thigh_r` | torso | leg | 2.5 | 0.6 | 42 |  |
| `shin_r` | thigh_r | leg | 2 | 0.5 | 46 |  |

| Chain | Segments | Bone 1 | Bone 2 | Leg | Effector from root (rest) | Max IK reach |
|---|---|---|---|---|---|---|
| `leg_l` | thigh_l+shin_l | 0.15 m | 0.11 m | yes | 0.10 m | 0.36 m |
| `leg_r` | thigh_r+shin_r | 0.15 m | 0.11 m | yes | 0.10 m | 0.36 m |

| Weapon | Segment | Radius | Rest distance from root | Max distance from root |
|---|---|---|---|---|
| `pipe` | arm_r | 0.10 m | 0.34 m | 0.77 m |
| `pipe_mid` | arm_r | 0.07 m | 0.29 m | 0.48 m |
| `lid` | arm_l | 0.20 m | 0.30 m | 0.76 m |
| `head` | head | 0.11 m | 0.12 m | 0.53 m |
| `body` | torso | 0.18 m | 0.14 m | 0.35 m |

### Bilge (`boss_bilge`) — quadruped, 15 segments, 320 kg, top 2.08 m, hover 1.35 m

| Segment | Parent | Part | Mass | Hurt | w0 | Guard |
|---|---|---|---|---|---|---|
| `chest` | - | core | 110 | 0.9 | 26 |  |
| `pelvis` | chest | core | 70 | 0.9 | 26 |  |
| `neck1` | chest | core | 18 | 1 | 28 |  |
| `neck2` | neck1 | core | 14 | 1 | 28 |  |
| `head` | neck2 | head | 30 | 1.3 | 28 |  |
| `chain` | neck1 | tail | 10 | 0.3 | 14 |  |
| `thigh_fl` | chest | leg | 9 | 0.6 | 34 |  |
| `shin_fl` | thigh_fl | leg | 6 | 0.5 | 38 |  |
| `thigh_fr` | chest | leg | 9 | 0.6 | 34 |  |
| `shin_fr` | thigh_fr | leg | 6 | 0.5 | 38 |  |
| `thigh_bl` | pelvis | leg | 9 | 0.6 | 34 |  |
| `shin_bl` | thigh_bl | leg | 6 | 0.5 | 38 |  |
| `thigh_br` | pelvis | leg | 9 | 0.6 | 34 |  |
| `shin_br` | thigh_br | leg | 6 | 0.5 | 38 |  |
| `tail` | pelvis | tail | 8 | 0.4 | 18 |  |

| Chain | Segments | Bone 1 | Bone 2 | Leg | Effector from root (rest) | Max IK reach |
|---|---|---|---|---|---|---|
| `leg_fl` | thigh_fl+shin_fl | 0.44 m | 0.45 m | yes | 0.51 m | 1.37 m |
| `leg_fr` | thigh_fr+shin_fr | 0.44 m | 0.45 m | yes | 0.51 m | 1.37 m |
| `leg_bl` | thigh_bl+shin_bl | 0.43 m | 0.43 m | yes | 1.22 m | 2.08 m |
| `leg_br` | thigh_br+shin_br | 0.43 m | 0.43 m | yes | 1.22 m | 2.08 m |

| Weapon | Segment | Radius | Rest distance from root | Max distance from root |
|---|---|---|---|---|
| `jaws` | head | 0.30 m | 2.10 m | 2.46 m |
| `head` | head | 0.32 m | 1.80 m | 2.17 m |
| `paw_fl` | shin_fl | 0.18 m | 0.54 m | 1.55 m |
| `paw_fr` | shin_fr | 0.18 m | 0.54 m | 1.55 m |
| `paw_bl` | shin_bl | 0.18 m | 1.20 m | 2.26 m |
| `paw_br` | shin_br | 0.18 m | 1.20 m | 2.26 m |
| `body_slam` | chest | 0.66 m | 0.50 m | 1.16 m |
| `belly` | chest | 0.70 m | 0.05 m | 1.23 m |
| `shoulder_l` | chest | 0.40 m | 0.65 m | 1.07 m |
| `shoulder_r` | chest | 0.40 m | 0.65 m | 1.07 m |
| `tail_tip` | tail | 0.15 m | 1.90 m | 2.15 m |

### Conduit (`boss_conduit`) — serpent, 9 segments, 260 kg, top 3.31 m, hover 0.42 m

| Segment | Parent | Part | Mass | Hurt | w0 | Guard |
|---|---|---|---|---|---|---|
| `body4` | - | core | 36 | 0.9 | 22 |  |
| `body3` | body4 | core | 32 | 1 | 24 |  |
| `body2` | body3 | core | 30 | 1 | 26 |  |
| `body1` | body2 | core | 28 | 1 | 26 |  |
| `head` | body1 | head | 32 | 1.4 | 26 |  |
| `body5` | body4 | core | 32 | 0.8 | 20 |  |
| `body6` | body5 | core | 28 | 0.7 | 18 |  |
| `body7` | body6 | core | 24 | 0.7 | 18 |  |
| `plug` | body7 | tail | 18 | 0.6 | 18 |  |

| Weapon | Segment | Radius | Rest distance from root | Max distance from root |
|---|---|---|---|---|
| `head` | head | 0.30 m | 0.50 m | 3.26 m |
| `jaws` | head | 0.20 m | 0.80 m | 3.44 m |
| `tail_tip` | plug | 0.32 m | 3.70 m | 4.03 m |
| `coil` | body2 | 0.40 m | 0.28 m | 2.02 m |
| `coil_low` | body3 | 0.40 m | 0.25 m | 1.37 m |
| `body_upper` | body1 | 0.30 m | 0.20 m | 2.53 m |
| `body_base` | body4 | 0.45 m | 0.10 m | 0.66 m |

### Commissioner Snappington (`boss_snappington`) — crab, 16 segments, 480 kg, top 1.44 m, hover 0.80 m

| Segment | Parent | Part | Mass | Hurt | w0 | Guard |
|---|---|---|---|---|---|---|
| `shell` | - | shell | 250 | 0.6 | 24 | yes |
| `neck` | shell | core | 20 | 1.1 | 26 |  |
| `head` | neck | head | 26 | 1.4 | 26 |  |
| `uclaw_l` | shell | arm | 18 | 0.6 | 30 | yes |
| `claw_l` | uclaw_l | arm | 24 | 0.6 | 30 | yes |
| `uclaw_r` | shell | arm | 18 | 0.6 | 30 | yes |
| `claw_r` | uclaw_r | arm | 30 | 0.6 | 30 | yes |
| `uleg_fl` | shell | leg | 12 | 0.5 | 30 |  |
| `lleg_fl` | uleg_fl | leg | 10 | 0.4 | 34 |  |
| `uleg_bl` | shell | leg | 12 | 0.5 | 30 |  |
| `lleg_bl` | uleg_bl | leg | 10 | 0.4 | 34 |  |
| `uleg_fr` | shell | leg | 12 | 0.5 | 30 |  |
| `lleg_fr` | uleg_fr | leg | 10 | 0.4 | 34 |  |
| `uleg_br` | shell | leg | 12 | 0.5 | 30 |  |
| `lleg_br` | uleg_br | leg | 10 | 0.4 | 34 |  |
| `tail` | shell | tail | 6 | 0.5 | 18 |  |

| Chain | Segments | Bone 1 | Bone 2 | Leg | Effector from root (rest) | Max IK reach |
|---|---|---|---|---|---|---|
| `arm_l` | uclaw_l+claw_l | 0.52 m | 0.67 m |  | 1.72 m | 2.12 m |
| `arm_r` | uclaw_r+claw_r | 0.52 m | 0.67 m |  | 1.72 m | 2.12 m |
| `leg_fl` | uleg_fl+lleg_fl | 0.38 m | 0.70 m | yes | 1.32 m | 1.96 m |
| `leg_bl` | uleg_bl+lleg_bl | 0.38 m | 0.70 m | yes | 1.32 m | 1.96 m |
| `leg_fr` | uleg_fr+lleg_fr | 0.38 m | 0.70 m | yes | 1.32 m | 1.96 m |
| `leg_br` | uleg_br+lleg_br | 0.38 m | 0.70 m | yes | 1.32 m | 1.96 m |

| Weapon | Segment | Radius | Rest distance from root | Max distance from root |
|---|---|---|---|---|
| `claw_gavel` | claw_r | 0.30 m | 1.72 m | 2.42 m |
| `claw_l` | claw_l | 0.22 m | 1.71 m | 2.34 m |
| `beak` | head | 0.16 m | 2.05 m | 2.26 m |
| `head` | head | 0.25 m | 1.85 m | 2.15 m |
| `shell_edge` | shell | 0.55 m | 0.95 m | 1.50 m |
| `shell_dome` | shell | 0.90 m | 0.00 m | 1.25 m |
| `shell_side_l` | shell | 0.50 m | 1.00 m | 1.50 m |
| `shell_side_r` | shell | 0.50 m | 1.00 m | 1.50 m |
| `leg_tip_fl` | lleg_fl | 0.14 m | 1.32 m | 2.10 m |
| `leg_tip_fr` | lleg_fr | 0.14 m | 1.32 m | 2.10 m |

