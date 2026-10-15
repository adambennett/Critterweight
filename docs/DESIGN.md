# CRITTERWEIGHT — engineering design

Creative specifications live in `docs/design/` (GAME_PITCH, ROSTER, ELEMENTS, ENEMIES_BOSSES, ARENAS,
CAMPAIGN, HUB, MODES, ANNOUNCER_AND_TUTORIAL, ART_DIRECTION, AUDIO_DIRECTION). This file records how the engine
realises them and the committed numeric targets.

## 1. Platform targets and budgets (committed early, see DEL-09)
| Item | Target |
|---|---|
| Windows | Windows 10 22H2 / 11, x86-64, Vulkan (Forward+); D3D12 not required |
| Linux | Ubuntu 24.04 LTS x86-64 and SteamOS 3 (Steam Deck) via the native Linux export (Vulkan). Proton as fallback only |
| Minimum HW | 4 cores x86-64 (Steam Deck Zen 2 class), 8 GB RAM, Vulkan 1.2 GPU with 2 GB (Deck APU / GTX 1050 class) |
| Recommended | 6+ cores, 16 GB RAM, GTX 1660 / RX 5600 class |
| Measured dev PC | i7-7700K (4C/8T), 32 GB, RTX 4070 Ti SUPER, Windows 10 22H2 — the "mainstream PC baseline" numbers are measured here and labeled as such |
| Graphics presets | Deck (1280x800, shadows low, AO off, effects medium), Low, Medium, High, Ultra |
| Frame budget | 60 fps (16.6 ms). Simulation ≤ 3 ms for 8 fighters on the dev PC (≤ 4 ms Deck estimate, unverified) |
| Fighters per match | 2 (duel) standard, 4 FFA/teams standard, **8 maximum** |
| Server | 1 match per process; 8 players + 4 spectators; 120 Hz sim; target < 35% of one core at 8 fighters |
| Memory | < 2 GB RAM for the client in busy scenes |
| Loading | main menu < 10 s cold, match < 5 s |

## 2. Combat model (D-003)
- **Fighter space**: +Z forward, +Y up, +X = creature's left. Bodies, poses and moves are authored in this space.
- **Rig**: segments (capsule/sphere/box) with masses; `Generic6DOFJoint3D` springs chase targets; root hover +
  anchor spring (upright/facing) + velocity drive. Muscle tone (global + per segment) scales stiffness.
- **Motor**: base pose (stance ↔ guard blend), move overlay (keyframed effector targets → two-bone IK, joint
  rotations), procedural gait (biped/avian/quadruped/crab step groups; serpent undulation; hopper bounce), look-at.
- **State machine** (Fighter): neutral, attack, ability, guard, dodge, hitstun, guard-break, knockdown → down →
  get-up, grabbing/held, taunt, celebrate, KO, downed (co-op revive), inactive.
- **Hit validation** (Combat): weapon spheres active only in hit windows; contact with closing speed ≥ vmin;
  quality q = (vn − vmin)/(vref − vmin); damage = base × (0.55 + 0.6q) × (0.75 + 0.25·clean) × part × charge ×
  power/defense × JUICE × element × counter × combo scaling × OTG; guard (front arc 80°, or guard-part contact)
  → 15% chip + stamina drain; parry (guard press ≤ 0.12 s before contact) → attacker staggered.
- **Anti-infinite**: combo damage scaling (−8%/hit, min 50%), stun scaling (−12%/hit, min 35%), stun budget 2.2 s
  → automatic burst (shove + 0.6 s invulnerability), wake-up invulnerability 0.5 s, max 2 OTG hits at 40%.
- **Resources**: health, stamina (actions, guard drain, low-stamina slowdown), poise (empty → knockdown), hype
  (0–100 → JUICE ultimate, then a short "crash"), ability cooldowns.
- **Grab layer**: grab beats guard; strikes beat grab startup; hold ≤ 1.6–2.0 s; pummel; directional throws;
  mash escape; grab-vs-grab tech; wall slams when thrown bodies hit the fence fast.

## 3. Camera, controls, assistance
- Broadcast camera frames all fighters from an elevated 3/4 view perpendicular to the player's engagement line,
  never flipping sides; right stick / Z,C nudges yaw; trauma shake scaled by the accessibility setting.
- Movement is camera-relative; facing is auto (soft lock-on to the nearest enemy in the movement direction, sticky
  1 s; R3/Tab switches). Attacks snap toward the target within 70°; lunges close small gaps.
- Default pad: LS move · X Light · Y Heavy (hold = charge) · LT Guard (tap = parry) · A Dodge · B Grab ·
  LB/RB Abilities · RT JUICE · D-Up Taunt · RS camera / R3 target · Menu pause. KBM: WASD, J/LMB, K/RMB, Shift,
  Space, F/MMB, Q, E, R, T, Tab, Z/C, Esc. Everything rebindable; guard hold/toggle option.
- Input buffer 0.15 s; light string L1→L2→L3 with cancel windows; Heavy in the window = Finisher; Light during
  dodge = Dash Attack.

## 4. Content targets (committed; see CNT-04)
| Content | Target |
|---|---|
| Playable fighters | 6 (Stoke, Dredge, Gusto, Dozer, Slurry, Jitters) |
| NPC-only | 2 minion types + 3 bosses (2 phases each) |
| Elements / reactions | 6 / 11 (+ zone versions) |
| Arena bases | 4: The Gullet (primary cage), Drydock, The Crusher, The Rooftop; 6 example editor layouts |
| Campaign | 3 acts × (6 rows + boss), ≥8 normal + 3 elite encounter templates per act, ≥24 events, ≥36 supplements + 36 techniques, 25–40 min runs |
| Difficulty | 4 presets (Sparring, Amateur, Pro, Title Shot); ladder The Dosage, Dose 1–10 |
| Fight Camp | ≥20 permanent upgrades; hub The Cannery: ≥5 spaces, ≥6 NPCs, ≥4 activities, ≥8 secrets |
| Bonus modes | 4 (MODES.md) |
| Bots | 5 skill tiers: Punching Bag, Journeyman, Contender, Headliner, Hall-of-Famer |
| Audio | ≥7 music tracks, full SFX set, ≥150 announcer lines (subtitled babble) |
| AI Lab | 2 training approaches (evolution strategies, behaviour cloning) + sample policies |

## 5. Campaign, co-op and modes
See docs/design/CAMPAIGN.md, MODES.md, HUB.md. Engine notes are added here as systems land.
