# Campaign systems

How the fight card (Off the Street, Fight Camp, co-op parties and The Bookie's Table) and the
persistent Career are built.
Design intent lives in `docs/design/CAMPAIGN.md`, `HUB.md`, `ENEMIES_BOSSES.md` and `ROSTER.md`;
this document describes the implementation, the data formats a modder writes, and the contracts
other subsystems plug into.

Code: `game/src/campaign/` (run logic, content, co-op, UI), `game/src/sim/modes/` (fight modes).
Data: `game/content/core/{supplements,techniques,meta_upgrades,events,encounters,boss_fights,ladder}/`.
Schemas: `game/content/schemas/{supplement,technique,meta_upgrade,event,encounter,boss_fight,ladder}.schema.json`.
Tests: `game/src/test/campaign/` (run with `-- --test campaign`).

## Architecture

```
Content (autoload) --load--> CampaignValidator (schemas + cross-checks, POST_LOAD_VALIDATORS)
        |
        v
CampaignCatalog  — typed index of campaign entries + CreatureResolver (creature ids -> JSON)
        |
        v
RunController (one run = one JSON-safe Dictionary, RunState)
   |  MapGenerator / ActMap      seeded 3 acts x (6 rows + boss)
   |  EncounterBuilder           encounter -> fight plan -> MatchSim config
   |  BuildApplier / RunRules    build packages -> patched creature + mods; economy rules
   |  RewardRoller / EventRunner / CampaignShop
   |  claim ledger + decision log (duplicate protection, replay)
   v
CampaignFlow (solo UI glue) · CoopSession (party over PartyTransport) · BookieTable (autobattler)
   |                                   |                                   |
App screens (src/campaign/ui)      LoopbackTransport / NetPartyTransport   CampaignDriver + AutoPilot
   |
App.start_match (presented)  or  HeadlessFightRunner (own physics world, SimSpeed)
   |
CampaignMatchMode / BossMode (+ CampaignHazards, BossBrain) inside MatchSim
```

* **Determinism.** Every random choice uses `RunRng` streams derived from the run seed and a
  string key (FNV-1a), never global randomness: the same seed and content produce the same card,
  plans, offers, shop stock and event rolls on every platform. Seeds are 53-bit so they survive
  JSON exactly; `seed_text` is an 11-character shareable form.
* **One state.** A run is one Dictionary (`RunState`): saved as-is, sent as the co-op ticket and
  replayable from `start_cfg` + `log` (`RunController.replay`). Screens and bots only call
  `RunController` methods; there is no other mutable campaign state.
* **Commit points.** Every state change ends in `_commit(reason)`: `changed` is emitted and the
  `autosave` callable runs (CampaignFlow saves at every committed transition).

### Run lifecycle

`map` → choose node → `fight` | `event` | `shop` | `rest` | `reward` (treasure) → pending picks →
node complete → `map`. The act boss completes the act (heal 50% / 35%, next act, intro card); the
Act 3 boss ends the run in `victory`; a lost fight (party wiped) ends it in `defeat`. Abandoning is
a defeat flagged `abandoned`. `RunController.phase()` is the single source of truth for screens.

* **Claims.** Rewards, purchases, rest choices, event decisions and fight results are recorded
  under `claims[node_id][player_id]`; a resent message, a double click or a resumed save that
  tries the same claim is rejected (`last_error`).
* **Pending picks come first.** A pick can outlive the activity that granted it (Train at a rest,
  an event's technique/reward pick, a consumable's pick in a shop): the node completes only once
  every pick is claimed, and `CampaignFlow.current_screen()` routes to the reward screen whenever
  this player has a pick pending (any phase but a fight). Screens hand back to the flow only when
  it would show something else, so no screen can bounce to itself; `RunController.advance_if_done()`
  completes a node whose activity is done (it also repairs runs saved mid-transition by older
  builds — e.g. "rest, Train taken, pick pending" resumes straight into the pick).
* **Events never softlock.** When no choice can be taken (requirements, Scrip — for a group event,
  every member must cover their share), the decider passes (`EventRunner.PASS`, "MOVE ON" on the
  event screen, chosen by the autopilot too); a pass is logged like any choice.
* **Everything that changes the outcome is logged** (decisions, fight results, a run turning
  custom), so `RunController.verify(catalog, state)` can rebuild any state from its own
  `start_cfg` + `log` and compare (floats to 1e-4; connected/bot flags and elapsed time are not
  logged); `verify_from(catalog, verified_ctrl, state)` replays only the decisions since a run
  verified earlier.
* **Play time** = time in menus + each fight's simulated time, once: `CampaignFlow` stops its wall
  clock while a presented fight runs (`begin_fight`) and restarts it when the result is applied.
* **Pacing.** The generator keeps 2–3 fights in rows 2–5 per route (12–15 fights per run with
  bosses, never more than 3 in a row); `campaign_rules.pacing` estimates 25–40 minutes per run and
  the generation tests check every route of 500 seeds against it.

### Variants, ladder, difficulty, custom runs

* **Off the Street** — no permanent power; statistics, records, history, cosmetics and The
  Dosage persist. Clout earned goes to a cosmetics-only wallet.
* **Fight Camp** — the same plus Clout for Cannery upgrades (`meta_upgrades/`, every entry tagged
  `meta_bonus`). `BuildApplier` applies them ONLY when `state.variant == "fight_camp"` (or a custom
  match that visibly enables "Gym Bonuses", `FightCamp.gym_bonus_package`). The hub uses the
  `FightCamp` API: `stations()`, `list_upgrades()`, `buy_upgrade()`, `run_options()`,
  `run_config()`, `services()`.
* **The Dosage** (`ladder/doses.json`, 10 levels, cumulative). The first clear on Amateur or
  harder opens The Dosage (Dose 1). Clearing the highest unlocked Dose unlocks the next (max 10)
  — only on the profile's OWN open ladder: a Dose above it (a co-op host's card) or below it
  unlocks nothing. Ladder progress is per variant (`profile.ladder`).
  `CampaignProgression.dose_cap(catalog, profile, variant, difficulty)` is the highest Dose a
  profile may play AND be credited for (0 while closed, 0 on difficulties without
  `dose_allowed` — Sparring); run creation clamps to it (`clamp_dose`: campaign menu, hub sign-up
  sheet, "Raise the Dose", a co-op host's own profile), and the hub sheet only offers Doses the
  chosen difficulty takes. Dose records, Dose badges/cosmetics, `best_dose`, ladder progress and
  `ach_fully_dosed` are credited only when the run's Dose is within the crediting profile's cap;
  otherwise the report carries `dose_ineligible` (the clear itself, fighter title and history
  still count) and the summary card says why. The Dose cosmetics (badges, the alternate announcer
  jacket, Lethal Dose badge/chant) are the track Fight Camp shares with Off the Street: a Fight Camp
  card's Dose clears count toward it only once the profile owns the Cannery's **Title Contender**
  (`meta_title_contender`, `CampaignProgression.title_contender`); without it they stay on the Camp
  board and the report carries `dose_cosmetics_need: "meta_title_contender"`.
* **Saved builds** (`profile.campaign.saved_builds`, newest first): every credited run saves its
  fighter, techniques and supplements; the AI Lab trains against them with the Cannery's Boiler
  Room Key (docs/AI_LAB.md §4).
* **Difficulty presets** (`ladder/difficulty.json`): Sparring, Amateur, Contender, Title Shot —
  enemy HP/damage, bot tier, reward multipliers, rest heal; Sparring records on its own board and
  disallows Doses. Bot tiers: `punching_bag … hall_of_famer` map to BotBrain profiles.
* **Custom runs** (dev stand-ins, reduced game speed, test builds, custom rules) count for
  statistics and history but never for records, ladder unlocks, cosmetics, achievements or Fight
  Camp milestone flags; Clout at 50%. The UI says so on the summary card. The live reasons
  (`CampaignFlow.LIVE_REASONS`: reduced game speed, development stand-ins) are re-checked before
  every presented fight (`RunController.mark_custom`, logged); a run that became custom stays
  custom. "Run it back" / "New card" decide afresh: live reasons as they are now, fixed reasons
  (a test build, custom rules) carried over.
* **Achievements** (Platform): `ach_off_the_street` / `ach_made_camp` (clear the variant),
  `ach_order_in_court` (beat Commissioner Snappington = clear a run), `ach_fully_dosed` (clear
  Dose 10). Granted for the active local profile only, never from The Bookie's Table.
* **Records** per fighter × board (street/camp/bookie) × difficulty × Dose × party size: fastest
  clear, fewest knockdowns suffered, biggest Scrip hoard, no-hit bosses. Campaign fights are
  started with `no_record: true` so `App._record_match` does not also count them as versus
  matches.

## Data formats

All entries live in `items` arrays of JSON files under the kind folder and carry `id` + `type`.
Mods add files with the same layout; an entry with the same id and `"override": true` replaces
the core one (campaign rules merge key by key). Load-time validation is described under
[Validation](#validation).

### Apply blocks

Supplements, side effects, techniques, meta upgrades and event outcomes change a fighter or a
run through one **apply block**:

```json
{"patches": [...], "mods": [...], "hooks": [...], "statuses": [...], "run": [...]}
```

* `patches` — [Patches](#patches) on the creature JSON (moves, abilities, stats, body).
* `mods` — `[{key, mul|add|set}]` on `Fighter.mods` (keys and identity values:
  `CampaignCatalog.MOD_DEFAULTS`, e.g. `damage`, `defense`, `speed`, `stamina_regen`,
  `parry_window_add`, `wakeup_invuln_add`, `dodge_iframes_add`, `grab_hold_add`,
  `grab_escape_add`, `status_duration_taken`, campaign-only `prevent_knockdowns`, `revive_speed`,
  `assist_rate`).
* `hooks` — Hooks DSL entries appended to the creature's passives (`{on, if, do}`; see
  `src/sim/hooks.gd`).
* `statuses` — statuses applied at the bell of every fight.
* `run` — economy/run rules `[{key, mul|add|set}]` (`CampaignCatalog.RUN_DEFAULTS`: `scrip_mult`,
  `shop_price_mult`, `rest_heal_add`, `post_fight_heal`, `free_rerolls`, `reveal_rows_add`,
  `boss_tell_lead`, `supplement_side_effects`, …).

Meta upgrades use `per_level` instead of `apply` (numbers scale linearly with the owned level).

### Patches

`ContentPatch` ops on the creature dictionary: `set | add | mul | min | max | append | remove |
merge | time_scale`.

```json
{"op": "mul", "path": "moves.heavy.damage", "value": 1.12}
{"op": "time_scale", "path": "moves.*", "value": 1.05, "phase": "startup"}
{"op": "set", "path": "abilities.ability2.effects[type=prop].max_active", "value": 2}
```

Paths are dot separated; `*` matches every key; selectors `[3]`, `[*]`, `[field=value]` address
array elements. `time_scale` scales every authored time of a move/ability (`phase: "startup"`
only stretches the wind-up and shifts later times). Missing paths are skipped at apply time (kits
differ) and reported by `apply_all` so tests can flag patches that never hit their fighter.

**Kit contract for techniques.** Techniques target the kit slot names of `ROSTER.md`:
moves `l1 l2 l3 heavy heavy_charged finisher dash_attack grab pummel taunt`, abilities
`ability1 ability2 juice`, and effect types of the effects vocabulary (`[type=zone]`,
`[type=projectile]`, …). A kit that renames slots must keep these ids or ship its own technique
overrides.

### Supplements

`supplements/*.json`, `"type": "supplement"` or `"side_effect"`.

```json
{"id": "sup_tusk_dust", "type": "supplement", "name": "Tusk Dust", "rarity": "prescription",
 "stack": 2, "tags": ["heavy", "glass"], "effect": "Heavy damage +12%",
 "side_effect": "Stamina regen -10%", "label": "flavor text",
 "apply": {"patches": [...], "mods": [...]}}
```

Rarities `otc | prescription | black_market | banned` (offer weights in
`campaign_rules.rarity_weights`, act shifts in `act_rarity_shift`). `stack` caps copies;
`consumable: true` items run their `on_pick` effect ops when used. Tags drive synergy (2+ items
sharing a tag: +20% per tag, max +40%) and the autopilot. Side effects (`se_*`) are applied by
events and Dose 7 and removed by a Rub-down or the Antidote Lozenge; `fight_rolls` re-roll a
modifier per fight from the node seed.

### Techniques

`techniques/<fighter>.json`: `"type": "technique"` (36, six per fighter) and `"type": "build"`
(18 build directions, three per fighter).

```json
{"id": "tech_stoke_pressure_cooker", "type": "technique", "fighter": "f_stoke",
 "name": "Pressure Cooker", "build": "build_stoke_furnace", "tags": ["status", "burn"],
 "effect": "Sizzle on an enemy also drains stamina", "apply": {"hooks": [...]}}
```

Offered at elite/boss rewards, Train at rests, shops and some events; never twice.

### Events

`events/*.json`, `"type": "event"`.

```json
{"id": "evt_needles_sample", "type": "event", "title": "Free Sample", "speaker": "Needles",
 "text": "…{fighter}… {element}…", "roll": {"element": true}, "group": false,
 "requires": {"act": [1, 2]},
 "choices": [{"id": "take", "label": "Take it", "desc": "…", "risk": "risky",
              "cost": {"scrip": 40}, "requires": {"scrip": 40}, "locked_text": "…",
              "outcomes": [{"weight": 1, "text": "…", "effects": [{"op": "grant_supplement", "rarity": "prescription"}]}]}]}
```

Requirement keys: `act, fighters, element, party_element, weight_class, scrip, has_banned,
no_banned, has_supplements, roll_matches, variant, coop`. Unavailable choices stay visible with
their `locked_text`. Effect ops (`CampaignCatalog.EVENT_OPS`): `hp, hp_pct, max_hp, scrip, clout,
hype_carry, hype_carry_set, grant_supplement, side_effect, remove_supplement,
remove_side_effects, technique_pick, reward_pick, run_mods, run_patches, run_hooks, next_fight,
bet, boss_mod, fight, cosmetic, coupon, flag, nothing, consumable, quip, stat`. Group events are
decided once for a party (vote), costs split evenly. Outcome rolls use the node's stream.

### Encounters

`encounters/act{1,2,3}.json` (`"type": "encounter"`, tiers `normal | elite | boss | event`),
`acts.json` (`"type": "act"`), `minion_loadouts.json` (`"type": "minion_loadout"`).

```json
{"id": "enc_a1_blister_pack", "type": "encounter", "tier": "normal", "act": 1,
 "name": "Blister Pack", "arena": "drydock", "blurb": "Pop them at range.",
 "enemies": [{"minion": "blister_sludge", "count": 3}, {"minion": "scrapling_basic", "count": 2}],
 "special": {"hazards": [{"kind": "crane_hook", "every": 30}]}}
```

Enemy entries: `{"minion": loadout, count}`, `{"fighter": id|"random"|"mirror", pool, techniques,
build, techniques_list, hp_mult, count}`, `{"boss_fight": id}`. A spar (event fight with
`"spar": true`, e.g. Kid Lamprey's) is a copy of your fighter at the template's own `hp_mult`
(x0.6) and is never scaled by difficulty, Dose (no extra technique / start Hype) or party size.
Special rules (`special`):
`handicap`, `waves` (`{trigger_alive}`), `sequential`, `tag_bout` (`{regen, …}`; solo players get
one Granny Haymaker cameo), `sudden_death` (timed: round time then 1-HP sudden death), `gravity`,
`hype_mult`, `zone_duration_mult` (puddles last longer), `ffa`, `hazards` (`[{kind, every?, …}]`),
`blister_fast`, `enemy_start_hype`. Arena keys resolve through `campaign_rules.arenas` (arena ids,
day/night variant, default minion, default hazards). Scaling: difficulty × Dose × party size
(`campaign_rules.coop`: enemy count ×1.5/2/2.5, +35% HP and +10% damage per extra player; bosses
+60% HP per extra player only).

Minion loadouts patch a base minion (`npc_scrapling`, `npc_blister`) when no creature with the
loadout id exists: `scrapling_basic, scrapling_pelter, scrapling_hot_pipe, scrapling_gravel_lid,
scrapling_leaky_pipe, blister_sludge, blister_ember, blister_fuse`.

### Boss fights

`boss_fights/*.json`, `"type": "boss_fight"`; ids `fight_bilge`, `fight_conduit`,
`fight_snappington` reference the creatures `boss_bilge`, `boss_conduit`, `boss_snappington`.

```json
{"id": "fight_snappington", "type": "boss_fight", "creature": "boss_snappington", "act": 3,
 "arena": "gullet_title", "phase2_at": 0.5, "target_rotate": 8.0,
 "dazed": {"duration": 3.0, "damage_taken": 1.2, "throw_mult": 2.0},
 "standin_stats": {"health": 650, "poise": 240},
 "phases": [{"id": "by_the_book", "hazards": [...], "attack_gap": [2.2, 3.6], "attacks": [
   {"id": "gavel_claw", "weight": 3, "range": [0, 3.5], "cooldown": 5.0, "telegraph": 0.8,
    "recovery": 1.0, "aim": "target", "decal": {"shape": "line", "length": 3.0, "width": 1.2},
    "actions": [{"t": 0.0, "type": "area", "at": "forward:1.4", "radius": 1.0, "damage": 16}]}]},
  {"id": "off_the_books", "speed_mult": 1.25, "transition": {"invuln": 2.0, "line": "…"},
   "element_cycle": {"every": 8.0, "order": ["scorch", "static"]}, "attacks": [...]}]}
```

`BossMode` (extends `CampaignMatchMode`): two phases (phase 2 at the boss's own `phase2_at`; a run
modifier such as Dose 8 "No Mercy" only brings it sooner — `EncounterBuilder.boss_phase2_at`;
phase 2 cannot be skipped; 2 s invulnerable transition), telegraphed attacks (every telegraph
≥ 0.5 s, emitted as `boss_telegraph` with decal data), actions from the effects vocabulary plus
`grab_throw`, `withdraw`, `aim`,
`telegraph_only`, `rush`; any action may carry `yaw_offset`. **Dazed**: a poise break gives a 3 s
stagger (damage taken ×1.2, throws ×2) and is the only time a boss can be grabbed; other
knockdowns never floor a boss. Arena interplay: leash (Bilge), damage-triggered repositioning
(Conduit), element cycle and Juice Vat (Snappington), co-op target rotation.

### Ladder

`ladder/`: `doses.json` (`"type": "dose"`, level 1–10, `run` entries), `difficulty.json`
(`"type": "difficulty"` and `"type": "bot_tier"`), `campaign_rules.json` (the single
`"type": "campaign_rules"` entry: roster, start Scrip, arenas, map rules, rewards, rarity weights,
synergy, reroll, hype carry, boss heals, shop, rest, fight, pacing, co-op, hazards).
`campaign_defaults.gd` holds the built-in defaults the file is merged over.

### Meta upgrades

`meta_upgrades/cannery.json`, `"type": "meta_upgrade"`, 24 entries at six stations:

```json
{"id": "meta_heavy_bag", "type": "meta_upgrade", "meta_bonus": true, "name": "Heavy Bag",
 "station": "gym_floor", "costs": [80, 160, 320], "effect": "Damage +2% per level",
 "per_level": {"mods": [{"key": "damage", "mul": 1.02}]},
 "gate": {"flag": "beat_act1", "text": "Beat Act 1 in Fight Camp"}, "flags": ["hub_unlock"]}
```

## Validation

`Content.POST_LOAD_VALIDATORS` runs `CampaignValidator.validate_content(Content)` after every
(re)load:

1. JSON Schema per entry (`content/schemas/*.schema.json`); failing entries are removed from
   `Content.tables` so a broken mod entry can never reach a run; errors name the file.
2. Semantic checks (`CampaignCatalog.validate`): patch shapes, mod/run keys, hooks DSL, event ops
   and requirements, references between campaign entries, encounter enemies, boss telegraphs
   ≥ 0.5 s, difficulty bot tiers, act bosses.

Creatures owned by other packages (roster fighters, minions, bosses) and arenas are warnings,
not errors. A creature that is installed but does not parse yet (a kit still being authored) is
treated like a missing one: such encounters are excluded from generation, the campaign menu
explains why, and development stand-ins (`--campaign-stand-ins`, or the menu toggle; runs are
marked custom) fill in `dev_biped` bodies with the documented stats.

## Fights

`EncounterBuilder.plan()` turns an encounter into a JSON-safe plan stored in the node session
(enemy creatures and builds, minion loadouts, boss data, waves, tag bouts, special rules,
hazards, scaling, bot tier); a resumed run re-uses the plan, so a fight interrupted by a crash is
re-run from its start with the same enemies. `build_match()` produces the `App.start_match` /
`MatchSim.setup` config with patched `CreatureDef`s, mods and input sources.

`CampaignMatchMode` (extends `MatchMode`): one round; the party wins when every enemy-side fighter
is out and no wave/tag partner waits; carried HP, start statuses, next-fight rules;
waves/sequential entries/tag partners are parked off-world (INACTIVE, frozen); enemy tag bouts and
the party tag-team format (Switch Target = tag, benched Taunt = cheer, benched Ability 1 =
assist); simultaneous co-op downed/revive on MatchMode's machinery (hold Grab next to a downed
ally for 2 s, revive at 30%; the 15 s timer shrinks 5 s per prior down; bots get the revive
objective from `MatchMode.bot_objective`); campaign sudden death (everyone to 1 HP, decision after
45 s); hazards (`CampaignHazards`, built only from the effects vocabulary, every telegraphed hazard
emits `hazard_telegraph`). The result carries `result.campaign` (won, time, per-player HP/Hype/
stats, enemies, boss phase).

`HeadlessFightRunner` runs the same fight without presentation in its own physics world; with
`SimSpeed` (k× physics ticks per second at the fixed 1/120 s step) fights run 10–14× faster than
real time. Pausing freezes the fight's physics space.

## Persistence

`RunStore` (kind `campaign_run`, version `RunState.VERSION`) under `<user>/runs/<profile>/`:
slots `off_the_street`, `fight_camp`, `bookie`, `party_<run id>`. Writes go through `Saves`
(temp → verify → `.bak` rotate → rename, checksummed). Loading never deletes anything: damaged,
newer-format or content-incompatible saves return a clear error (missing content is listed per id
so the player can re-enable the mod); abandoning a damaged save moves every copy of the slot
(`.json`, `.tmp`, `.bak`) aside (quarantine). `RunStore.list` shows a slot as soon as any copy
exists — also when a crash left only the verified `.tmp` and/or the `.bak`, which `load_slot`
recovers from. `RunStore.migrate` chains format migrations (v0 → v1 included).

**One suspended run per variant.** A new run never silently replaces the one in its slot: the
campaign menu's START RUN and the hub's sign-up sheet ask first (abandon it and start / resume
it / cancel), and abandoning credits the old run as an abandoned defeat
(`CampaignFlow.abandon_suspended`: history, attempts; a run that cannot be loaded is
quarantined). `CampaignFlow.start` itself does the same for anything still in the slot, so no
caller can destroy a suspended run without a trace. A run saved by a newer game version is never
replaced, moved or deleted: the menus explain and deal no card over it. Party slots (`party_<run id>`) are listed
by the campaign menu but never resumed as a solo run (the co-op lobby resumes them through
`CoopSession.host_resume`); host and members clear them when the run ends.

Godot's JSON reader does not read every 17-digit double back exactly (about 1 in 7 random values
returns one ulp off), which would fail checksum verification for real fight results.
`RunStore.json_stable()` round-trips data to a JSON fixed point before saving and before party
tickets are checksummed; profile times written by the campaign use `RunStore.stable_float()`.
Other subsystems that save arbitrary floats through `Saves` should do the same (or `Saves`
should adopt it).

`CampaignProgression.finish_run(catalog, state, player_id, profile)` credits one finished run to
one profile (idempotent per run id and player): statistics, records, history, saved builds,
ladder, Clout (camp wallet or cosmetic wallet), cosmetics, camp milestone flags, achievements
list.

## Co-op protocol

`CoopSession` (2–4 players, both variants) talks only to an abstract `PartyTransport`:
`local_id()`, `send(to, type, payload)` (`to == ""` broadcasts), signals `message_received`,
`peer_joined`, `peer_left`, emitted from `poll()`. Payloads are JSON-safe dictionaries.

Host → members: `run_state {state, host, reason, live, event?}` (`live`: the run is on - a run
dealt in a lobby is held until the host starts it; `event`: the latest event outcome at this node
{node, title, choice, by, texts}, presentation only), `ticket {run_id, host, log_size, checksum,
state}` (replica checkpoint after every node), `vote_open {options, captain, seconds, voters,
event?}`, `vote_update {votes}`, `vote_result {node, reason, tie, counts}`, `fight_start
{encounter, …}`, `notice {text}`, `paused {by, seconds, budget}`, `resumed {budget}`,
`host_changed {host}`, `run_end {state}`, `error {text, type}`.

Members → host: `hello {player}`, `vote {node}`, `event_choice {choice}`, `pick {rid, choice}`,
`reroll {rid}`, `shop_buy {slot}`, `shop_service {}`, `shop_sell {item}`, `shop_leave {}`,
`rest {option}`, `consume {item}`, `pause {}`, `resume {}`, `rejoin {player}`, `move_on {}`.

**Trust.** The sender of a message is the transport's peer id (`from` of `message_received`),
never a payload field (payload `host`/`player` fields are informational). The host acts on a
member's intents only for that member's own player. Members accept host-only messages
(`run_state`, `ticket`, `run_end`, `notice`, `error`, `paused`, `resumed`, votes) only from the
current host; `host_changed` only from the successor the election rule picks (next connected
member in Captain order after the departed host, from the member's checkpoint) and only once the
old host is gone from the member's view — a claim that overtakes the departure is held until it.
A `run_state`, `ticket` or `run_end` must belong to the party's run (run id + seed of the host's
first state). Tickets and the final result must also follow from their own decision log
(`RunController.verify_from` the last accepted ticket — a node's worth of replay; a full replay
when it is not a plain continuation): only then is a ticket saved as the member's replica, and a
result credited — from the rebuilt run, never from the numbers in the message (elapsed: the
larger of the logged fight time and the host's). The ticket checksum only detects damage.
Rebuilding needs the same campaign content as the host (the run's `content_hash`); a member
with different content sees the checkpoints rejected with a notice instead of trusting them.

**Group events.** Every member's `event_choice` on a group event is a vote (never the decision);
the ballot holds only the choices the Captain may take and every member can pay their share of.
A pick that still fails at resolution (Scrip spent meanwhile) is dropped from the next ballot and
the error is broadcast; when nothing is left the party passes (`EventRunner.PASS`), so a group
event always resolves — also with everyone idle or disconnected. `vote_result {event: true,
choice, reason, tie, counts}` announces the outcome. A co-op host deals only Doses its own
profile may play; each member's Dose credit follows that member's own ladder.

Rules: the host owns the authoritative `RunController`; route votes (10 s, majority, Captain
breaks ties, abstainers ignored); per-player picks, inventories and Scrip; simultaneous format by
default, tag-team as a setting; downed/revive; scaling per party size; a disconnected member's
fighter is piloted by a bot (capped at Contender) until they rejoin at the next node boundary;
idle members are auto-decided after 60 s (the Captain may "move on"); host departure → members
wait 60 s, then the next connected member in Captain order resumes as host from their replica
(a fight in progress re-runs); if everyone leaves the run stays suspended in every member's party
slot. Ref timeouts pause fights for up to 30 s per player per run; menus never pause. At the end
each member credits only their own profile.

**Views for every machine's screens** (built on a member from the host's messages only):
`is_live()`, `vote_view()` {open, event, options, votes, voters, captain, left}, `pause_view()`
{paused, by, left, budget}, `fight_view()`, `last_event`. `act(type, payload)` returns whether the
intent was accepted (host: applied with a member's rules, `last_error` says why not; member: sent).

`LoopbackTransport` (in-process, serializes every payload to JSON text like a wire) drives the co-op
tests. `NetPartyTransport` adapts the Net autoload's app-message channel and namespaces types as
`cmp/<type>`; payloads above 4 KB (whole run states) travel deflated and are unpacked with bounded
checks (docs/NETWORKING.md §14). It uses from Net: `send_app(target_peer, type, payload)`
(reliable, ordered; `""` = broadcast), `signal app_message(from_peer, type, payload)`, `signal
member_joined(peer)`, `signal member_left(peer, reason)`, `local_member_id()`, `member_ids()`.

### Online party runs

Played through the online lobby (docs/NETWORKING.md §14 "Party runs played online"):
`NetPartyRuns` (src/net) owns the run on each machine - deal / offer / start on the host, seat
claims on members, ticking, and the host's **fight driver**: at a fight node it builds the match
with `RunController.match_config` (members' kinds: host `player`, connected members `net`, absent
members `bot` at Contender) and plays it on the session (`NetServer.start_campaign_match`); the
authoritative result goes into `CoopSession.complete_fight` once; an aborted match is played again.
`CoopFlow` (src/campaign/ui/coop_flow.gd, a `CampaignFlow`) binds the same campaign screens to the
shared run: decisions go through `CoopSession.act` (the `CampaignFlow.do_*` methods the screens
call; a solo `CampaignFlow` applies them directly), the route map's buttons are votes, screens are
rebuilt when this player's part of the run changes and otherwise only refresh their party line,
an event outcome stays until CONTINUE (`holds_screen`), and while a fight is presented the screens
wait for the session to return to its lobby (OnlineFlow then calls `show_current`). The host
alone can suspend the run for everyone or forfeit a fight; members leave (a bot takes over until
they rejoin). Each machine remembers its seat next to its party save (`RunStore.save_party_seat`),
so a resumed run finds the right player even when profile ids repeat between machines. Fight Camp
party runs use each member's own Cannery levels (sent to the host when they join, clamped to the
installed upgrades); Clout and records go to each member's own profile.

## The Bookie's Table

`BookieTable` (a Node under App so it survives screen changes) plays a card where bots fight every
bout and either the player or "Teddy" (`CampaignAutoPilot`) makes the decisions. Controls:
`pause()/resume()` (also freezes a fight in progress), `set_speed(1..4)` (tests use more),
`take_over()/hand_back()`, `stop()`, `deal()`. `fight_runner` is pluggable: the Bookie screen
plugs in a presented match (`BookieFlow.run_fight` via `App.start_match` with an overlay control
bar) or the headless fast-forward runner. Every presented fight re-applies the table's speed
(`SimSpeed.set_scale`: k × physics ticks at the fixed 1/120 s step) — a finished `MatchScene`
resets `Engine.time_scale` when it ends and leaves the tree. The same goes for the table's **camera
preset**, `set_camera()`, which the overlay bar's CAMERA button cycles:
- **Broadcast:** the standard fight framing.
- **Director:** the spectators' auto-director, which cuts between the fighters and the action.
- **Free:** a free camera, moved with the stick or WASD.
`BookieFlow.apply_camera` applies the preset to every presented fight and live when it changes. The
overlay bar lifts the fight HUD (`FightHud.set_bottom_inset`), so the fighter plates are never under it.
Attended decisions reuse the normal
campaign screens through `BookieFlow` (same routing as `CampaignFlow`, pending picks first).
Results go to the `bookie` record board with Clout at 50%; the table never unlocks Doses or
achievements.

## Autopilot

`CampaignAutoPilot` makes between-fight decisions for Teddy, disconnected/idle co-op members and
tests (deterministic for a given state):

* **Route** — value each visible node type by HP fraction, Scrip and build, and pick the best
  discounted route value to the boss (unknown nodes count as average). Low HP steers to
  Rest/Shop and away from Elites; healthy runs take Elites and Treasure.
* **Rewards** — rarity + tag synergy (with owned supplements and technique build tags) − risk
  when HP is low; techniques complete a build direction; Treasure takes the Scrip when the best
  supplement is weak.
* **Events** — expected value of each available choice's weighted outcomes (a group choice is
  available only if every member can pay their share); nothing available → pass.
* **Shop** — best affordable item above a threshold keeping 30 Scrip; Rub-down with 2+ side
  effects; leave.
* **Rest** — Patch up below 60% HP, Rub-down with 2+ side effects, Train if a technique is left,
  Patch up below 90%, else Film study.

## UI

`src/campaign/ui/` (self-contained widgets in `CampaignUI`, own modal): `campaign_menu`
(variant, fighter, difficulty, Dose, co-op format, seed, suspended runs, Bookie, Cannery Ledger),
`run_map` (branching map with icon + text node types, reachable nodes focusable, side panel with
HP/Scrip/Hype/build/consumables, suspend/abandon, act intro card), `reward`, `event`, `shop`,
`rest`, `run_summary` (victory/defeat, numbers, build, Clout/ladder/records; Run it back, New card,
Raise the Dose), `bookie` (setup, live view, overlay over presented fights), `camp_ledger`.
Everything is operable with a controller (focus chains, `ui_accept`, `ui_cancel` = back/close
modal) and with mouse/keyboard. `CampaignFlow` routes phases to screens and launches presented
fights with `App.start_match(config, on_finished)`; screens make this player's decisions through
the flow (`do_claim`, `do_event`, `do_shop_buy`, `do_rest`, ...), so `CoopFlow` can play the same
screens in an online party run (party line under the title, votes on the map, waiting states).

## Engine hooks used by the campaign

Small additive hooks outside `src/campaign/`:

* `Content`: `"boss_fights"` kind; `POST_LOAD_VALIDATORS` (+ `_run_post_load_validators()` after
  load).
* `MatchMode.intercept_knockdown(f, reason, by)` (Fighter.knock_down asks the mode first: boss
  Dazed, one-shot knockdown protection).
* `Fighter.mods` keys `wakeup_invuln_add`, `dodge_iframes_add`, `grab_hold_add`,
  `grab_escape_add`; `StatusSet` scales element-status durations by `status_duration_taken`.
* Hooks DSL conditions `self_hype_above/below`, `other_flag`, `self_attacking`, `hit_blocked`,
  `target_poise_below`, `hit_part`; `damage_add` with `min`; action `status`.
* `EffectsSystem` zones: negative `push_out` pulls inward.
* `combat.detect_hits`: stop scanning when the attacker's move ended mid-scan.
* `App` screen entries for the campaign screens.

## How to …

* **Add a supplement**: add an entry to a file in `supplements/` (or your mod's), pick a rarity,
  write the apply block, run `-- --test campaign` (schemas + semantic checks + a run test).
* **Add a technique for a new fighter**: add the fighter to `campaign_rules.roster` (override),
  add `build` entries and six `technique` entries targeting the kit slot names.
* **Add an event**: add it to `events/`; use `requires` for fighter/element events; outcomes are
  weighted lists of effect ops. `group: true` makes it a party vote.
* **Add an encounter**: add it to the act file with `tier`, `arena` (a key of
  `campaign_rules.arenas`) and `enemies`; it joins the generator's pool automatically if every
  creature it needs is installed.
* **Add a boss**: author the creature (creature owner), add a `boss_fight` entry referencing it,
  and an `encounter` with `"tier": "boss"` and `{"boss_fight": id}`; set it as an act boss in
  `acts.json` (override).
* **Tune the ladder**: edit `doses.json` / `difficulty.json`; run keys are listed above.

## Tests

`godot --headless --path game --fixed-fps 120 -- --test campaign` runs everything campaign;
filters such as `-- --test test_campaign_generation` run one file.

| File | Covers |
|---|---|
| `test_campaign_generation.gd` | 500-seed generation validity, determinism, pacing, guarantees, Dose 10 |
| `test_campaign_run.gd` | run state machine, rewards, shop, rest (Train pick), events (group costs, pass), claims, replay/verify (incl. incremental, tampering), ladder and Dose eligibility, custom runs and camp milestones, spar scaling, boss phase-2 threshold, variants |
| `test_campaign_fights.gd` | encounters → real MatchSim fights: plain, waves/timer, tag bout, boss phases/telegraphs/Daze, co-op downed/revive |
| `test_campaign_persistence.gd` | suspend/resume, crash recovery (also slots left with only `.tmp`/`.bak`), duplicate claims across resumes, damaged/missing/newer saves, removed content, migration, tickets, unstable floats |
| `test_campaign_coop.gd` | loopback co-op: votes, ties, picks, disconnect/rejoin, host departure, pause budget, tag format, per-player credit; forged member messages, tampered host results, host-change election rule, group-event ballots (affordable only, failed picks dropped, member choice = vote), party slots cleared at the end, host Dose clamp |
| `test_campaign_bookie.gd` | three unattended complete runs with real fights; pause/take over |
| `test_campaign_full_runs.gd` | complete runs with real fights: victory and defeat in both variants |
| `test_campaign_ui.gd` | every screen builds with a focused control; real `ui_accept`/`ui_down` input walks a run to the summary; modals, forfeit, ledger, Bookie controls; Rest → Train without a screen loop (also from a stuck save and at the table), replace-a-suspended-run confirmations (menu, hub sheet), Doses on the hub sheet, party rows, custom re-checks, play time, Bookie speed across presented fights |
| `test/net/test_net_party_play.gd` | online party runs in-process: CoopSession views on every machine, fights on the network session in both formats (tag-in / assist over the network, a downed ally revived with the member's own Grab), ref timeout freeze, result applied once, per-player picks, drop + reconnect mid-fight, replayed fight |
| `test/net/test_net_party_campaign.gd` | online party runs between independent processes through the real lobby and campaign screens: Off the Street simultaneous (ref timeout from the member's pause menu, picks, event, shop, drop + rejoin, forfeit, per-member credit) and Fight Camp tag (Cannery levels, tag-ins / assists from the bench, suspend and resume in a new session, event, rest, host leaving mid-fight) - LOOPBACK |

Match outcomes are asserted structurally or statistically (several fights), not bit-exactly;
generation and content logic are asserted seed-deterministic.

## Career (v0.9.16)

One persistent fighter, recreated from Cage Rules' career (DECISIONS D-048). It is not a run: it
does not use RunState, RunController or RunStore. Code: `game/src/campaign/career/`; screens:
`game/src/campaign/ui/career_*_screen.gd`; data: the `career` block of
`content/core/ladder/campaign_rules.json` deep-merged over `CareerDefaults.rules()` (nested objects
merge key by key, arrays such as `orgs`, `facilities` and name lists are replaced whole, so a missing
or partial block stays playable).

```
CareerController (one save = one JSON-safe Dictionary, CareerState VERSION 1)
   |  CareerOffers   seeded offers per (career seed, week, re-roll): RunRng "career/offers/w<week>/r<roll>"
   |  CareerBuild    six stats + carried injuries -> one apply block -> BuildApplier.compose
   |  CareerFight    Cage Rules bout config (presented or headless), seed RunRng.derive(seed, "fight/<offer>")
   |  CareerStore    Saves kind "career": careers/<profile slug>/slot_<1..3>.json (+ .tmp/.bak)
   v
CareerFlow (UI glue: FIGHT -> begin_fight -> App.start_match -> apply_result -> career_result)
```

* **Week loop.** `train(stat)` or `rest()` advances one week. Gain per week =
  `0.026 × (1 + 0.3 × room level) × (1 + 0.12 × coach level) × ((1 − s)^1.2 + 0.1) ×
  max(0.35, 1 − injury total / 260)`, stats capped at 0.99. Healing per region per week =
  `(10 + 4 × recovery level) × (2.5 when resting)`. An unbooked week costs 0.6 popularity and rolls
  new offers; a camp week counts down the booked fight.
* **Offers.** Two (40%) or three (60%) per week from the open promotions of your top tier and the
  one below (Cage Rules weights); slot 0 is the title fight at popularity 92 (or a defence for the
  champion). Nine promotions in four tiers (Regional, National, Major, The Big League) with Cage
  Rules' gates, purses and opponent levels; tier caps 42/66/88/100; the Grand Circuit holds the only
  belt. Purse = level-scaled range × short-notice premium (title × 2.5); win bonus 60% of the purse
  (100% in the top tier).
* **Opponents.** A playable creature with stats `level + (shape − 0.66) × 0.55 ± 0.04`, a generated
  record, an original ring name, nickname and home town, and a bot tier from its level (< 0.33
  Punching Bag, < 0.48 Journeyman, < 0.63 Contender, else Headliner; Easy −1 / Hard +1 tier, and only
  Hard reaches Hall-of-Famer). The danger tag compares ratings (≤ −8 FAVOURED, ≤ 6 EVEN, ≤ 16
  UNDERDOG, else LONG SHOT).
* **Stats → fighter.** `CareerBuild.MAP` (coefficients in `career.build`, scaled by s − 0.5, mul
  values clamped to 0.5–1.6): Stamina → `stamina_add`, `stamina_regen`; Chin → `poise_add`,
  `getup_speed`; Speed → `speed`, `move_speed`; Power → `damage` and patch `moves.*.poise`; Clinch →
  `grab_hold_add`, `grab_escape_add`, `throw_distance`, `splat_damage_add`, `held_time_mult`;
  Defence → `guard_absorb_mult`, `parry_window_add`, `dodge_iframes_add`, `dodge_cost`. Never
  `defense` or the `poise` multiplier. Half of each region's injury is a fight-start handicap: head
  → `poise_add` −0.3 per point (max −15), body → `stamina_regen` × (1 − carried/160), legs → `speed`
  × (1 − carried/200), floor × 0.7. The block is applied only in career bouts (state variant
  `career`), never to versus, online or Fight Camp builds.
* **Bouts.** Rules = the `cage_rules` preset (10-point judges + referee) with 3 rounds (5 for a
  title), the preset's 99 s rounds and sudden death off; arena from the career arena list; `no_record`
  and `context.career`. `begin_fight()` saves `booked.in_fight` before launch: a crash re-fights the
  identical bout; quitting from the pause menu is a withdrawal (popularity −4, week + 1, no purse).
* **Results** (`apply_result`, idempotent per fight id): reads `result.scoring` (method, cards,
  per-team tallies) or derives the outcome from `winner_team`. Popularity as Cage Rules (tier
  multipliers 1/1.4/1.8/2.4; finish bonus by rounds left; split × 0.75; title +6/−3; streak +1.5;
  fight-of-the-night +1.5 above 44 combined strikes landed per round; losses −(3 + 1.5 × tier mult),
  −2 more for a round-one stoppage loss; draw +0.5; gains capped by the tier cap). Pay = purse (+ bonus
  on a win). Record buckets W/L/D with T.K.O. and decision wins. Injuries out = damage taken by part
  (% of max HP) × 0.07 + 2 head per knockdown suffered + 10 head when stopped (D-045). Titles: a title
  win crowns you, a champion's title win is a defence, only a title loss takes the belt.
* **Persistence and reliability.** Autosave after every action and before a bout; three slots per
  profile; load never deletes (damaged, newer and missing-content saves are reported and kept);
  `CareerState.check` reports missing fighters/arenas; stale offers re-roll on load; a booked fight
  whose content disappeared can be cancelled without penalty; Retire moves `.json`, `.tmp` and `.bak`
  to `careers/<profile>/retired/` so a backup can never bring it back.
* **Standing.** Tier name, popularity label (Unknown … Superstar), a contender number #15 … #1 between
  popularity 74 and 92 in the top tier, and Champion.

## Known gaps

* Online party runs are tested with two humans between processes on one machine (LOOPBACK);
  three- and four-player parties only over the loopback transport. With Net the listen host's
  departure ends the session, so the run is recovered from the party saves (CoopSession's live
  host election only applies to transports that outlive the host). Members' run-end credit and
  checkpoints are verified against their own logs, the fights themselves are the host's. A member
  who is away when the run ends is credited if they reconnect while the host is still on the run
  summary (the hello reply carries the result); after that their party save keeps the run at the
  last stop they saw, uncredited.
* Until the creature owners' kits parse, roster fighters, minions and bosses run as documented
  stand-ins in tests and dev runs (custom).
* Some techniques approximate their design text with the current effects vocabulary (e.g.
  Counter Clock as a move-speed buff, Slippery Customer on any parry, Sidewinder as a general dash
  buff, grab reach via lunge); the arena hazard positions use defaults until arenas provide
  `hazard_<kind>` markers.
