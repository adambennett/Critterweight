# Audio

Audio uses the repository synthesis pipeline for its editable score, SFX, creature and announcer sources, with selected free third-party recordings overlaid for v0.9.13. The audio bank remains reproducible: tools/audio/build.js writes the generated source bank, then merges game/assets/audio/replacement-overrides.json. Imported files stay in game/assets/audio/replacements/ and are protected from the generated-audio cleaner.

The v0.9.12 playtest removed eight sustained tonal ambience beds and fixed rapid-room crossfades. v0.9.13 adds selected CC BY 4.0 and CC0 music, combat, UI, movement, crowd and dock-water clips. The four Kevin MacLeod songs require in-game attribution. Replacement filenames, source pages, licences, hashes and bank references are in docs/audio/replacement-audio-inventory.txt; the original generated inventory remains separate. Named creature calls and custom announcer/coach lines remain generated.

Spec: `docs/design/AUDIO_DIRECTION.md` (tracks, SFX list, mixing), `docs/design/ANNOUNCER_AND_TUTORIAL.md`
(voices, lines), `docs/design/ROSTER.md` (per-fighter sound palettes).

## 1. Pipeline

```
tools/audio/scores/*.js      song scores (pattern sequencer)         ─┐
tools/audio/sfx/*.js         SFX definitions (parametric generators)  ├─ node tools/audio/build.js ─► game/assets/audio/**/*.wav (+ .import, QOA)
tools/audio/lib/babble.js    announcer/coach grain banks             ─┘                               game/assets/audio/bank.json    (runtime bank)
                                                                                                        game/assets/audio/manifest.json (sha256/peak/LUFS per file)
                                                                                                        tools/audio/report.md           (showcase report)
game/content/core/announcer/*.json   announcer + coach lines (ids, triggers, subtitles, priority)
game/src/audio/audio.gd              Audio autoload (buses, pools, music, announcer, crowd, ambience, event mapping)
game/src/audio/babble.gd             runtime babble synthesizer (AudioStreamGenerator)
game/src/audio/match_bridge.gd       one-call MatchSim integration (events, footsteps, zone loops, watchers)
```

**Rebuild everything** (Node.js 18+, zero dependencies; ~80 s on the dev machine):

```powershell
node tools/audio/build.js                      # all: sfx + music + voice banks + bank.json + manifest + report
node tools/audio/build.js --sfx --only hit_    # re-render only ids containing "hit_" (bank stays complete)
node tools/audio/build.js --music --only boss  # one track
node tools/audio/build.js --check              # re-render in memory and verify every committed file is byte-identical
node tools/audio/build.js --clean              # remove stale generated WAVs; preserve replacements/
node tools/audio/build.js --say "Pick the crab." --speaker barnaby --out captures/say.wav   # audition a babble line
node tools/audio/spectro.js game/assets/audio/music/boss.wav --out captures/boss.png --seconds 40  # spectrogram + waveform PNG
& $g --headless --path game --import           # then import (Godot fills uid/path in the generated .import files)
& $g --headless --path game -- --test audio    # headless verification (see §7)
& $g --path game -s res://src/test/audio/audio_showcase.gd -- --quick   # windowed showcase with real playback
```

Renders are deterministic: all randomness goes through a seeded xoshiro RNG keyed by asset id and
variant, dither uses a fixed LCG, so a rebuild reproduces identical bytes (`--check` proves it).

Generated output formats: 16-bit PCM WAV. Imported replacement music and selected SFX use MP3, OGG and WAV. Music 44.1 kHz stereo (the diegetic hub radio is 22.05 kHz mono by
design, the game filters it per room), music layers 22.05 kHz mono (stems that only add a lead or
percussion line), SFX 44.1 kHz mono, creature voices / crowd / ambience 22.05 kHz mono, announcer grains
22.05 kHz mono imported as PCM (the runtime reads their samples). Everything else imports as QOA
(`compress/mode=2`, Godot 4.5's default). Loops get `edit/loop_mode=2` with explicit `loop_begin/end`.
Total rendered size: 128.9 MB (638 files); the lion's share is the eight tracks (~106 MB), see §8.

## 2. Synth engine (`tools/audio/lib`)

| File | Contents |
|---|---|
| `rng.js` | xoshiro128** seeded from strings (FNV-1a); `fork(tag)` for nested determinism |
| `dsp.js` | polyBLEP oscillators (sine/saw/square/pulse/tri), FM operator, hard-sync saw, supersaw, white/pink/brown noise, LFO; ADSR / point envelopes / exponential decays; TPT state-variable filter (LP/HP/BP/notch), one-pole, RBJ biquads (EQ, shelves), comb/allpass/delay lines; saturation (tanh/soft/hard/fold/tube), bit-crusher, chorus, feedback/ping-pong delay, Freeverb reverb (with gate), feed-forward compressor, lookahead limiter, mid/side widener, Haas spread; measurement: sample peak, RMS, BS.1770 K-weighted integrated loudness with gating |
| `instruments.js` | melodic voices: `fmBrass` (3-op FM with feedback), `mutedTrumpet` (FM + formant band, `flat` cents), `subBass`, `squareBass` (pulse + filter env + sub), `reeseBass`, `sawLead` (supersaw), `syncLead` (hard sync), `pulseArp`, `epiano` (FM tine + tremolo), `whistle`, `choirPad` (saws through vowel formants), `bell` (1:3.5 FM), `foghorn`, `organ`, `pluck` (Karplus-Strong), `whoosh`, `murmurPad`; drums: `kick` (pitched 160→44 Hz), `snare`, `clap`, `hat`/`hatOpen` (6 inharmonic squares), `tom` (optional FM, wet), `crash`, `ride`, `rim`, `shaker`, `gavel`, `clank`, `crackle` |
| `sequencer.js` | tracker: song/sections/bars/loop, per-track patterns (16-step strings, chords, ties, velocities, glides, rolls, generative functions), swing, humanize, note cache, per-track FX chains (hp/lp/eq/shelf/sat/crush/chorus/delay/reverb/comp/trem/autopan/filterLfo/sidechain/fade), send reverb, master EQ/comp, loudness normalization to a LUFS target, lookahead limiter at −1 dBFS, loop-tail folding (the ring-out past the loop end is added back onto the loop start so loops are seamless), layer stems and short phase-locked loop layers |
| `sfxkit.js` | designed-sound building blocks: filtered noise bursts, pitched thumps, tones, FM pings, noise sweeps (whooshes), chirps, granular crackle, bubbles, drips, splashes, chain rattles (comb), zaps, buzzes, wind, seamless loop stitching, mono room slap, formant creature vocals (pulse source + 3 formants + growl AM + jitter + metallic ring) |
| `babble.js` | announcer/coach grain banks and the reference line planner (mirrors `babble.gd`) |
| `wav.js` | 16-bit WAV writer (deterministic TPDF dither) and reader |

## 3. Source formats

### 3.1 Scores (`tools/audio/scores/<track>.js`)

```js
module.exports = {
  id: 'combat_a', title: 'Undercard Scrap', bpm: 128, sr: 44100, stereo: true, swing: 0, gain: -8, tags: ['combat'],
  sections: ['A', 'B', 'A2', 'C'], bars: { A: 16, B: 16, A2: 16, C: 8 },   // arrangement + bar counts
  loop: { startBar: 1, endBar: 56 },                                        // 1-based inclusive; null = one-shot (stinger)
  layers: [{ id: 'lead', tracks: ['lead'], mono: true, sr: 22050, defaultDb: -80, kind: 'intensity' },
           { id: 'perc2', tracks: ['perc2'], loopBars: 4, kind: 'variant' }], // short loops stay phase-locked (loopBars divides every section)
  master: { lufs: -14.5, ceiling: -1, hp: 32, comp: {...}, reverb: {...}, eq: [...] },
  tracks: [
    { name: 'kick', inst: 'kick', params: { start: 170, end: 44 }, gain: -2.5, pan: 0, send: 0.0, fx: [],
      patterns: { A: ['x . . . x . . . x . . . x . . .', 'x . . . x . . . x . . x . . x .'], C: [...] } },
    { name: 'bass', inst: 'squareBass', patterns: { A: H.fromProg(PROG_A, (c, root) => H.bass(root, 'R . R . O . R . R . O . R R . O')) } },
  ],
};
```

Pattern tokens: `.` rest, `-` tie, `x X o r` drum hit/accent/soft/roll, `c3 eb4 f#2` notes, `c3+e3+g3` chords,
`:7` velocity (1–9 or 0.0–1.0), `*4` gate length in steps, `~` glide from the previous note, `x?` 50 % chance.
A pattern value is a bar string, an array of bars (cycled over the section) or a function
`(barIndex, section, ctx) => string`. `scores/_h.js` has helpers (`chord`, `stab`, `bass`, `fromProg`, `tr`).
`layers.kind`: `intensity` (fades in with `Audio.music_intensity`), `lead` (on by default, ducked during
dialogue), `variant` (one picked per match by seed), `phase` (boss phase 2), `boss` (per-boss flavour).

### 3.2 SFX definitions (`tools/audio/sfx/<group>.js`)

```js
const { def, alias } = require('./_def');
module.exports = [
  def('hit_light', { group: 'impacts', bus: 'Impacts', variants: 6, gain: 0, pitch: [0.96, 1.04], cooldown: 0.02, priority: 90, max_voices: 8 },
      (rng, sr, k) => K.tidy(K.mix(sr, [{ buf: K.burst(sr, rng, {...}), gain: 0 }, { buf: K.thump(sr, {...}), gain: -3 }]), sr)),
  alias('hit_otg', 'hit_light', { gain: -4, pitch: [0.85, 0.92] }),   // same files, different play parameters
];
```

Every rendered file is peak-normalized to −1 dBFS; `gain` is the bank's play-time level (mix balance),
`pitch` the random pitch range, `cooldown` the re-trigger guard, `priority` the voice-stealing rank,
`max_voices` the per-id cap, `loop: true` renders a seamless loop and imports it looping, `spatial: false`
keeps a sound 2D (UI, crowd, ambience). Variants render with `rng = Rng("<id>:<k>")`.

### 3.3 Announcer / coach lines (`game/content/core/announcer/*.json`)

```json
{"items": [
  {"id": "ann_big_09", "speaker": "barnaby", "trigger": "big_hit", "when": {"kind": "counter"}, "priority": 60,
   "text": "Caught him WINDING UP! That's a counter, folks, that's reading the mail!"}
]}
```

`trigger` is the key passed to `Audio.announce_trigger`; `when` conditions must all match the trigger
context (string equality, numbers, or membership when the context value is an array). The most specific
matching lines win, rotate by match seed and are not repeated within a match. `{p}` `{o}` `{a}` `{n}` are
substituted from the match context / `vars`. `mood: "pleased"` adds Granny's warble. Barnaby subtitles
are ≤ 90 characters (tested); the babble itself is capped at 4 s.

Triggers and context keys used by `Audio.on_sim_event`: `intro {creature}`, `boss_intro/boss_phase2 {boss}`,
`round_start {round: 2plus|final, context: campaign}`, `first_hit {who, kind: heavy}`, `big_hit {kind: [counter,
big_damage, charged, launcher, wall], who, target}`, `combo {kind: three|four_plus|six_plus|finisher|ended, who}`,
`parry {who, kind: [heavy, third]}`, `knockdown {kind: [poise, throw, trip, third], who, target}`, `comeback`,
`juice {creature}`, `low_health {who: player|opponent|both, kind: ten, context: coop}`, `time {kind: ten_seconds|
decision|sudden_death|sudden_death_won|ref_timeout}`, `ko {kind: [heavy, throw, juice, zone, piece, fast, ringout],
target}`, `win {creature}`, `draw`, `ringout {who, kind: wind|double}`, `reaction {reaction}`, `taunt {creature, kind:
punished|low}`, `event {node}`, `idle`, `tutorial {kind}` (Barnaby) / `tutorial {exercise, phase}` (Granny), `mode
{mode}`, `minion {kind}`, `hub {kind}`.

### 3.4 Babble voice

Each character has a grain bank (`assets/audio/announcer/<speaker>/`): two takes of five vowel honks
(`v_a_0` … `v_u_1`), six consonant classes (plosive click, sibilant hiss, "sh", fricative, nasal hum, liquid
glide), Barnaby's two-honk name `fanfare`, Granny's rising `eh`. `Babble.plan()` turns a subtitle into grain
events: letter classes → syllables (vowel groups, silent final e), onset consonant + vowel per syllable at the
character's rate (Barnaby 11/s, Granny 7/s), pitch contour from the sentence's terminal punctuation (`!` rises,
`.` falls, `?` rises then falls, `…` flat; Granny is flat with a 3 % drift), ALL-CAPS words +40 % level and a
pitch jump (Granny never shouts: only a small pitch rise), fighter names → the fanfare grain, commas / dashes /
mid-line periods → pauses, the last word of an auctioneer sentence lands longer and louder, deterministic
per-syllable jitter seeded by line id. Lines over 4 s speed up; "Reduced announcer" halves length and level.
The runtime streams the plan through an `AudioStreamGenerator` at 22.05 kHz (linear-interpolated grain
resampling, 10 ms release windows). Because assembly happens at runtime, mod lines babble without rebuilding.

## 4. Runtime bank and buses

`bank.json` → `{buses, sfx: {id: {files, bus, gain, pitch, cooldown, priority, max_voices, loop, spatial} | {alias, …}},
music: {id: {file, bpm, beats_per_bar, bars, seconds, bar_seconds, sections, loop, layers, gain, tags, stinger}},
voices: {speaker: {grains, f0, rate, …}}, creatures: {creature_id: {voice, material, plan, juice, …}}}`.

Bus layout (Settings owns the parent sliders; `Audio` owns the sub-buses and ducking):

| Bus | Parent | Default | Content | Ducking |
|---|---|---|---|---|
| Master | — | limiter −1 dB | | |
| Music | Master | per track: menu −6, hub −12, combat −8, boss −8, stings −6 | music players, `Radio` sub-bus (hub diegetic filter) | −6 dB while dialogue plays; lead layers −9 dB |
| SFX → Impacts | SFX | 0 | hits, parry, knockdowns, KO, reactions, abilities, JUICE | never ducked; priority ≥ 80 impacts duck the buses below for 150 ms |
| SFX → Movement | SFX | −4 | whooshes, footsteps, projectiles | −3 dB by impacts |
| SFX → Zones | SFX | −8 | zone / hazard loops (6 nearest audible) | −4 dB by impacts |
| Voice → Creatures | Voice | −3 | fighter grunts/hurt/KO/taunt/JUICE/idle | −2 dB by impacts |
| Voice → Dialogue | Voice | −2 | announcer / coach babble, bell, sting | — |
| UI | Master | −4 (slider) | interface | — |
| Ambience → Crowd | Ambience | 0 | crowd layers and one-shots (arena reverb on this bus) | −3 dB by dialogue |
| Ambience | Master | −10 | arena / hub beds | — |

Variation rules (AUDIO_DIRECTION §5): every one-shot has 3–6 variants, the same variant never plays twice in
a row, ±4 % pitch and ±1 dB level per play, per-id cooldowns (taunt lines 3 s, hurt grunts 0.3 s, crowd one-shots
6–10 s), footstep variants cycle with surface detection from the arena, music variation per match by seed
(percussion overlay layer + a micro pitch nudge), combat A/B chosen by the lead per act/mode.

## 5. `Audio` API

| Call | Purpose |
|---|---|
| `sfx(id, pos = null, vol_db = 0, pitch = 1) -> int` | one-shot (3D when `pos` is a Vector3 and the entry is spatial); returns a handle or −1 |
| `sfx_loop(id, pos, vol_db) -> int`, `stop_loop(h, fade)`, `set_loop_pos(h, pos)`, `set_loop_volume(h, db, fade)`, `is_playing(h)` | loops (zones, drags, charge, hover) |
| `ui(id)`, `scrip(n)` | interface sounds; coin ping × n (capped at 5) |
| `music(track, fade = 1, opts = {layers:{id:bool}, seed, intensity, section, pitch, diegetic})` | crossfade to a track; stems start sample-aligned |
| `music_intensity(v)`, `music_layer(id, on)`, `music_jump(section)`, `music_bar()`, `music_bar_seconds()`, `music_position()`, `sting(track)`, `stop_music(fade)` | layers, bar-synced section jumps, stingers |
| `announce(line_id, vars = {}) -> bool`, `announce_trigger(trigger, ctx, vars) -> id`, `pick_line(trigger, ctx)`, `say(speaker, text, priority, vars, mood)`, `stop_announcer()`, `announcer_busy()` | announcer/coach queue (priority ≥ 90 interrupts, ≥ 70 queues one line, lower is dropped while speaking; no repeats per match; `gameplay.announcer` full/reduced/off; `access.subtitles`) |
| `subtitle(speaker, text, seconds)` signal | emitted for every spoken line (connect `FightHud.subtitle`) |
| `crowd_start()`, `crowd_stop(fade)`, `crowd(id)`, `add_heat(v)`, `crowd_heat` | three heat layers crossfaded by `crowd_heat` (decays 0.05/s), one-shots with cooldowns |
| `ambience(id, fade)`, `set_arena(arena_id)`, `set_room(room)` | beds, arena crowd reverb preset, hub room radio EQ (juice_bar bright, dock bass-heavy, elsewhere "another room") |
| `begin_match(ctx)`, `end_match()`, `attach_match(sim, player_index, ctx)`, `detach_match()` | match context (names for `{p}`/`{o}`, seed, arena); the bridge does the rest |
| `on_sim_event(ev, listener_pos, info) -> Array` | maps one simulation event to sounds + lines (returns the ids used) |
| `on_match_tick(health_fracs, time_left, dt)` | low-health and ten-seconds lines (the bridge calls it at 4 Hz) |
| `creature_audio(creature_id)` | palette (voice, material, body plan, JUICE id); creature JSON may override with an `"audio": {...}` object |
| `validate() -> PackedStringArray` | every bank id resolves to an imported stream (used by the tests) |

Headless (`--headless`, dedicated server, `--lab-worker`): `enabled` is false, no players or streams are
created, every call is a no-op except the announcer queue, which still emits subtitles. Missing ids log once
(`Log.w("audio", …)`) and never crash. Settings respected: `audio.*` sliders and mute-in-background (applied by
Settings), `audio.device`, `gameplay.announcer`, `access.subtitles`, `access.gore` (KO piece ping only on
"full").

## 6. Integration table (lead)

One call per match covers everything in the table's "bridge" rows:

```gdscript
# MatchScene.start(), after sim.setup():
Audio.attach_match(sim, player_index, {"context": "campaign"})   # or "versus" / "coop"
Audio.music("combat_a", 1.5, {"seed": int(cfg.get("seed", 1))})  # combat_b for Acts 2–3 / FFA / bonus modes, "boss" for bosses
Audio.subtitle.connect(hud.subtitle)                              # FightHud.subtitle(speaker, text, seconds)
# MatchScene end / free:
Audio.end_match()                                                 # stops crowd + announcer, detaches the bridge
```

| Event / place | Call | Result |
|---|---|---|
| every sim event (hit, glance, parry, knockdown, getup, ko, downed, guard_break, burst, juice, juice_end, grab, grab_tech, grab_escape, throw, dodge, taunt, move_start, ability, effect, status, reaction, slam, ringout, reflect, round_intro, round_start, round_end, timeout, match_end, respawn, revived) | bridge → `on_sim_event` | impacts with material + element layers, whooshes, creature voices, crowd heat/one-shots, announcer lines (first blood, big hits, combos, parries, knockdowns, JUICE, reactions, wall splats, ring-outs, KO/win/draw), bell/round card, stingers |
| footsteps, serpent drags, hover/charge loops, hops | bridge (body plan from the palette, surface from the arena id/theme) | `step_<plan>_<surface>`, `drag_serpent_*`, `hop_takeoff` / `hop_land_*`, Stoke's belly clank every 4th step, Gusto's flaps |
| zones / projectiles (`sim.effects.entities`) | bridge | `zone_<vfx|element>` loops (6 nearest), `proj_loop_<element>` |
| HP thresholds, last 10 s, lead-layer intensity | bridge → `on_match_tick`, `music_intensity` | low-health lines, timer tick, lead stem fades in under 50 % HP |
| NetMatchScene (snapshots, no MatchSim) | `begin_match(ctx)` + `on_sim_event(ev, listener, {"pos": …, "health": […]})` per replicated event; call `on_match_tick` yourself | same mapping without the bridge |
| boss phase 2 | `Audio.music_layer("p2", true)`; `Audio.music_layer("bilge"|"conduit"|"snappington", true)` at match start; `announce_trigger("boss_phase2", {"boss": id})` | phase layer + boss flavour loop + line |
| JUICE in combat B | automatic (`music_jump("B")` on the next bar) | half-time section |
| results screen | `Audio.sting("victory"|"defeat")` is fired by `match_end`; call `announce_trigger("win", {"creature": id})` only if you bypass `on_sim_event` | |
| main menu | `Audio.music("fight_night_poster")`, `Audio.ambience("amb_menu")`, `announce_trigger("idle")` after 30 s idle | |
| hub | `Audio.music("cannery_radio")`, `Audio.set_room("main"|"juice_bar"|"dock"|"office"|"boiler"|"locker"|"booth"|"med_bay"|"roof")` | diegetic radio EQ per room + bed |
| Title Night / final boss walk-in / menu after a clear | `Audio.music("title_night")` | |
| campaign nodes | `announce_trigger("event", {"node": "shop"|"rest"|"event"|"mystery"|"elite"|"treasure"|"banned"|"boss"})`, `ui("ui_stamp")`, `ui("ui_card_flip")`, `scrip(n)`, `ui("ui_supplement")`, `ui("ui_banned")` + `crowd("crowd_ooh")` | |
| tutorial | `announce_trigger("tutorial", {"exercise": n, "phase": "intro"|"success"|"hint"|"juice"}, {"juice": name})` (Granny) and `announce_trigger("tutorial", {"kind": "start"|"string"|"heavy"|"guard"|"dodge"|"ability"|"parry"|"complete"})` (Barnaby on success); fighter jab `{"phase": "jab", "creature": id}` | |
| menus / settings | `ui("ui_move"|"ui_accept"|"ui_back"|"ui_error"|"ui_toggle"|"ui_slider"|"ui_tab"|"ui_open"|"ui_close"|"ui_pause"|"ui_unpause"|"ui_notify"|"ui_purchase")`; `ui("ui_hype_full")` when Hype hits 100, `sfx_loop("ui_hype_loop")` while JUICE is available, `ui("ui_cooldown_ready", 0, pitch_per_slot)` | |
| bonus modes / minions | `announce_trigger("mode", {"mode": "spotlight"|"chumball_goal"|"new_unit"|"rush_headliner"|"rush_wave"|"rush_down"})`, `announce_trigger("minion", {"kind": "scrapling_hit"|"blister_pop"|"ten_down"})`, `announce_trigger("time", {"kind": "sudden_death"|"sudden_death_won"|"ref_timeout"})`, `announce_trigger("comeback", {...})` | the sim does not emit these yet |
| arena hazards | `sfx("hazard_gutter_telegraph")`, `sfx_loop("hazard_gutter_flood")`, `hazard_crane_telegraph/drop`, `hazard_plate_telegraph`, `sfx_loop("hazard_plate_live")`, `hazard_magnet_telegraph`, `sfx_loop("hazard_magnet_pull")`, `hazard_wind_telegraph`, `hazard_wind_gust`, `prop_break_wood/metal`, `prop_burst_<element>`, `bumper_ding`, `spring_pad`, `pickup_health`, `pickup_hype`, `drain_teleport` | when hazards/props land in the sim, map them in `on_sim_event` or call these directly |

Visual alternatives: every cue above already has a visual (hit flash/sparks, VFX words, status pips,
telegraph decals, HUD callouts) and every spoken line is a subtitle, so audio is never the only channel.

## 7. Verification

`& $g --headless --path game -- --test audio` (14 tests, `game/src/test/audio/`):

- `test_audio_bank.gd`: bank loads; `validate()` finds every id's imported stream (QOA, loops imported looping);
  frequent sounds have ≥ 3 variants and pitch ranges; the required id list from AUDIO_DIRECTION §3 is present
  (impacts, whooshes, footsteps per plan × surface, elements × 6, statuses, 11 reactions, projectiles, UI,
  crowd, ambience, 12 voices × 6 types, JUICE); no file peaks above −1 dBFS (manifest); every manifest sha256
  matches the committed file (so the measurements describe what is shipped); music: 8 tracks, combat A/B at
  128 BPM, boss 132, loop points imported exactly and sitting on bar lines, layers divide the track, intensity/
  variant/phase/boss layers present; size budget.
- `test_audio_announcer.gd`: 163 Barnaby lines ≤ 90 chars with ids/triggers/priorities, ≥ 36 Granny lines;
  `announce` emits the subtitle with `{p}` substituted; most-specific line selection, deterministic rotation,
  no repeats per match; interrupt/queue/drop rules; reduced and off modes; the sim-event mapping (light/heavy/
  blocked hits, chitin and element layers, counter, parry, knockdown, JUICE signature per fighter, reactions,
  abilities by move id with generic fallback, projectile launch by element, KO + KO line); unknown events and
  ids are safe; headless `sfx()` returns −1.
- `test_audio_babble.gd`: the grain banks decode from PCM imports, a line plans, streams through the
  generator under the dummy driver and finishes with the signal.

Windowed runtime: `& $g --path game -s res://src/test/audio/audio_showcase.gd -- --quick` plays the whole
chain (menu → combat A with the seed layer and intensity → combat B JUICE jump → boss phase 2 → KO + victory
sting → coach line → hub radio per room) with real output and exits 0 when the music advanced, ≥ 8 subtitles
were shown, ≥ 20 voices played and no id was missing.

Report: `tools/audio/report.md` (regenerated by the build) lists every track's BPM, bars, length, loop,
layers, integrated loudness and peak, the SFX groups, grain banks and the global peak check.

Requirement ledger rows this covers (for `docs/REQUIREMENTS.md`): AUD-01 (menu/combat music, impact/ability/
creature sounds, UI feedback, ambience, mixing) and AUD-02 (variations, transitions, buses, visual
alternatives, no missing assets, no clipping) — implemented, built, auto-tested, Windows-runtime verified by
the showcase; UI-05's bus/device/mute settings were already wired by Settings and are honoured here.

## 8. Known gaps and decisions

- Size: 128.9 MB rendered against the ~120 MB target. The eight tracks follow the spec's bar structures at
  44.1 kHz stereo (hub radio 22.05 kHz mono, layers 22.05 kHz mono). The "+2 semitone transposed variant" of
  the combat tracks is not pre-rendered (it would add ~37 MB); per-match variation uses the percussion overlay
  layers plus a seed-based start offset instead. A transposed render is one `transpose: 2` away in the score.
- Sudden death, ref timeouts, comeback detection, bonus-mode and minion events are not emitted by the sim
  yet; the lines and triggers exist (see §6) for the lead/mode owners to call.
- Boss phase-2 vocal distortion is a runtime effect to add on the Creatures bus when bosses land (the
  palettes exist: bilge, conduit, snappington).
- Hub NPC lines other than Granny's documented ones are subtitles-only until the hub owner adds their JSON
  (any speaker without a grain bank gets subtitles with an estimated duration).

## 9. Provenance

All music, sound effects, creature voices, crowd, ambience and the announcer/coach babble voices are original
works synthesized by the tools in `tools/audio/` (written for this project, Node.js standard library only,
no npm packages) from the scores, definitions and line files in this repository, rendered on 2026-10-15. No
samples, loops, soundfonts, recordings, TTS voices or third-party audio libraries were used; nothing was
copied from Cage Rules or any other project. Fonts and other non-audio assets are inventoried elsewhere.
