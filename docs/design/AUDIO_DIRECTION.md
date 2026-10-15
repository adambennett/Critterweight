# CRITTERWEIGHT — Audio Direction

Everything here can be produced with synthesis (FM, subtractive, wavetable), synthesized drums, and designed noise, so the game owns its audio. Live-recorded foley is welcome where it is original and licensed; nothing depends on it.

## 1. Sonic identity

**"Dockside brass band meets a broken arcade."** Brass stabs and a foghorn-ish bass for the league's pomp; crunchy FM percussion and chip-adjacent leads for the arcade pace; crowd and harbor ambience glue it. Sounds are **chunky and short**: impacts under 300 ms, UI under 120 ms. Pitch and shape carry the element; color (timbre) carries the fighter.

## 2. Music plan

All tracks loop seamlessly; "loop points" are bar numbers. Tempo/key chosen so combat tracks can crossfade on bar lines (combat A and B share 128 BPM; the boss track is 132). Stems: drums / bass / harmony / lead / crowd so the mixer can drop layers (e.g., lead stem muted while the announcer babbles).

| # | Track | Where | Mood | Tempo / key | Instrumentation (synthesizable) | Structure (bars) | Loop |
|---|---|---|---|---|---|---|---|
| 1 | **Fight Night Poster** | Main menu | Big, brassy, slightly sleazy; a promo you don't trust | 104 BPM, F minor | FM brass stabs (3-op, brassy ratio 1:1 + feedback), sub bass (sine + saturation), synthesized kick/snare with gated reverb, a swung hi-hat, muted-trumpet FM lead with vibrato, crowd murmur pad | Intro 4 (foghorn + crowd) → A 16 (stabs, bass) → B 16 (lead) → A' 16 (stabs + lead) → tag 4 | Loop bars 5–56; intro plays once |
| 2 | **Cannery Radio** | Hub (The Cannery) | Lazy, warm, a radio in another room; diegetic | 92 BPM, B♭ major | Lo-fi: filtered electric-piano wavetable, subtractive bass with slow filter, brushed synth drums, a whistled lead (sine + breath noise), vinyl crackle layer | A 16 → B 16 → A 16 → C 8 (bridge) | Loop bars 1–56; filtered/EQ'd per room (Juice Bar radio brighter, Loading Dock sound system bass-heavier) |
| 3 | **Combat A — Undercard Scrap** | Standard fights, campaign Acts 1–2 | Driving, cheeky, forward | 128 BPM, D minor | FM kick (pitched 50→40 Hz), snare (noise + 200 Hz body), 16th hat, square-wave bass with octave jumps, brass-stab chords on the 2 and 4-and, a detuned saw lead for the B section, crowd stem | A 16 (groove) → B 16 (lead) → A 16 → C 8 (breakdown: drums + crowd only) | Loop 1–56; **intensity layers**: bars 1–16 at low intensity (no lead), the lead stem fades in when any fighter < 50% HP |
| 4 | **Combat B — Main Card Heat** | Acts 2–3, FFA, bonus modes | Heavier, more chaotic, a half-time section for big moments | 128 BPM, A minor | Same drum kit with an added FM tom roll, a reese-style bass (two detuned saws, slow phase), brass stabs an octave lower, a chip-arpeggio counter-lead (pulse wave), crowd | A 16 → B 16 (half-time) → A' 16 → D 8 (double-time build) | Loop 1–56; the half-time B section is forced for 8 bars after a JUICE activation (the mixer jumps to the nearest B bar) |
| 5 | **Boss — Her Honor** | Bosses (all three; the phase-2 layer differs by boss) | Ominous pomp, then unhinged | 132 BPM, C minor | Low brass cluster pads (FM, slow attack), a tolling bell (FM 1:3.5 ratio), marching snare roll, sub bass pulsing on quarter notes, a screaming lead (hard-sync saw) for phase 2, crowd chanting on a 2-bar loop | Intro 8 (bell + pad) → A 16 (march) → B 16 (brass theme) → **P2 layer**: adds lead + double-time hats; boss-specific stem: Bilge = wet toms, Conduit = electric buzz drone (60 Hz sync'd), Snappington = gavel clacks on beat 1 | Loop 9–40; P2 crossfades on the phase-change cinematic |
| 6 | **Victory sting — Belt Up** | Results (win) | Triumphant, ridiculous | 120 BPM, E♭ major | Full brass fanfare (4 FM voices), snare roll, crash, a crowd roar swell, then a 2-bar swung tag with the muted trumpet | 6 bars, non-looping (fanfare 4 + tag 2) | — |
| 7 | **Defeat sting — Cut Man** | Results (loss) | Deflated, affectionate | 70 BPM, F minor | Solo muted-trumpet lead (slightly flat), a single sub-bass note, a sad slide-whistle grain, distant crowd "aww" | 4 bars, non-looping | — |
| 8 | **Title Night** (bonus) | The Gullet (Title Night), final boss walk-in, menu after a full clear | Over-the-top broadcast | 112 BPM, G major | Fight Night Poster's brass at full size, pyro whooshes on bar 1, a choir-ish pad (detuned saws through a vowel formant filter), crowd at max | Intro 4 → A 16 → B 8 | Loop 5–28 |

Transitions: the music system works on bar boundaries; combat → victory/defeat stings cut on the next beat with a 100 ms fade; hub ↔ menu crossfade 1.5 s. Variation: each combat track has 2 alternate drum patterns and a transposed (+2 semitones) variant selected per match by seed, so ten fights in a row don't sound identical.

## 3. SFX list

### 3.1 Impacts

| Sound | Design | Variants |
|---|---|---|
| Light hit (flesh) | 60 ms noise burst (band-passed 300–1200 Hz) + 40 ms sine thump at 90 Hz; pitch scales with closing speed | 6 |
| Heavy hit | 120 ms thump at 55 Hz with a pitch drop, layered crack (noise 2–5 kHz, 20 ms), a short room slap | 6 |
| Hit on chitin/plates (Dredge, Dozer, Snappington, Scrapling lid) | Adds a "clock" (resonant 800 Hz ping, 30 ms) | 4 |
| Hit on jelly (Jitters, Blister) | Adds a wet "splort" (filtered noise with a pitch wobble) | 4 |
| Guarded hit | Dull "thup" (150 Hz, 80 ms), no crack, a short shield "shh" | 4 |
| Parry | Bright metallic "ting" (FM bell 1:2.01, 200 ms) + a 60 ms air whip; quarter-second ducking of music | 3 |
| Wall splat | Chain-link rattle (noise through a comb filter, 400 ms) + a low boom | 4 per arena material (fence, concrete, steel plate, railing) |
| Knockdown | Body thud (two 70 Hz thumps 80 ms apart) + a dust "pff" | 4 |
| Throw | A grunt (fighter voice), a whoosh, then the landing thud | per fighter |
| KO | Everything above at once plus a 300 ms sub drop and a crowd roar; the detachable piece gets a cartoon "ping" and a bounce rattle | 3 |

### 3.2 Whooshes and movement

| Sound | Design |
|---|---|
| Light whoosh | 80 ms filtered noise sweep 2 kHz → 500 Hz |
| Heavy whoosh | 160 ms sweep with a low 100 Hz "wump" tail |
| Spin/sweep | Looping whoosh with Doppler-style pitch wobble |
| Charge (Bulldoze, Quarry Ram) | Hoof-gallop loop + rising noise; "release" is a heavy whoosh |
| Leap/hover | Short "hup" + flap/boing; hover is a soft airy loop |
| Dodge | 100 ms "swish" + 1 footstep of the fighter's set |
| Blink (Drain Dive) | Drain gurgle down, 0.5 s silence, drain pop up |
| Grab | A clutch "clap" plus the grabber's voice grunt; pummel hits are light impacts pitched up |

### 3.3 Footsteps per body plan (surface variants: canvas, concrete, steel, wet plank, gravel/tar)

| Plan | Design |
|---|---|
| Biped (Stoke, Scraplings) | Bare slaps (short noise + 120 Hz), plus Stoke's belly-door clank every 4th step |
| Crab (Dredge, Snappington) | Six-point click-clack (two alternating 1 kHz ticks), wet on planks |
| Avian (Gusto) | Light taps with a tiny scrape; wing flaps on dashes |
| Quadruped (Dozer, Bilge) | Four heavy thuds at 2 Hz cadence; gravel scatter layer on gravel/tar |
| Serpent (Slurry, Conduit) | A continuous drag loop (filtered noise with slow amplitude modulation) + drips; Conduit adds an electric tick |
| Hopper (Jitters, Blisters) | "Boing" on takeoff (pitched spring), "splat/pat" on landing; Blisters wetter |

### 3.4 Element sounds (per hit layer, status trigger, zone loop, reaction)

| Element | Hit layer | Status trigger | Zone loop | Reaction signature |
|---|---|---|---|---|
| Scorch | Crackle (granular sparks) | A "whoomp" ignition | Low fire crackle loop | Flare-Up: boom + crackle; Backdraft: a gust-fed roar; Steam Burst: a kettle hiss |
| Brine | Splash (short) | A big splash + drip tail | Lapping water loop | Short-Out: a buzz-zap + splash; Mudbound: a thick glop; Dilute: a pour |
| Static | Snap (2 ms click + 4 kHz zap) | A rising buzz + pop | 60 Hz hum with random ticks | Stormfront: a thunder crack (noise burst + 40 Hz sub); Catalyze: a fizz |
| Sludge | Squelch | A gurgle + bubble pops | Slow bubbling loop | Spray: a wet spray; Crust: a crackling set |
| Grit | Gravel crunch | A rockfall tumble | Gravel trickle loop | Sandblast: a sand hiss + a guard "crack" |
| Gale | Air whip | A whistle gust | Swirling wind loop | — (Gale reactions use the partner's signature plus a gust) |

### 3.5 Fighter voices (synthesized or designed from original recordings)

| Fighter | Grain set | Notes |
|---|---|---|
| Stoke | Gravelly amphibian grunts with a metallic ring | Effort grunts on heavies, a kettle whistle at JUICE |
| Dredge | Low bubbling rumble, mouthpart clacks | Rarely vocal; a foghorn-ish "hmm" on taunt |
| Gusto | Nasal gull squawks shaped into laughs and catcalls | Vocal on every taunt and dodge |
| Dozer | Deep happy snorts, "hwuff" on charge, sneezes on idle | A mining siren at JUICE |
| Slurry | Wet hisses, gurgles, a bubbly chuckle | A drain backing up at JUICE |
| Jitters | Squeaky hum with crackles, "eep" on hit, kazoo giggle | A capacitor whine at JUICE |
| Minions | Scrapling: tin-can chatter; Blister: a rising whistle while inflating | The whistle is the Blister's whole telegraph in audio |
| Bosses | Bilge: big dog barks/pants through a tunnel reverb; Conduit: modulated arcs; Snappington: a dry, gavel-punctuated rasp | Phase-2 variants add distortion |

### 3.6 UI sounds

| Sound | Design |
|---|---|
| Move focus | 40 ms soft tick (filtered noise) |
| Confirm | 80 ms two-note FM blip (C→G) |
| Back | 80 ms single blip (G) |
| Error | 120 ms buzz (square, 110 Hz) |
| Card stamp (results, node cards) | A rubber-stamp thud + paper slap |
| Scrip gain | Coin-ish FM ping ×n (capped at 5) |
| Supplement pick | A can crack-open + fizz |
| Banned Substance pick | The can crack + a siren blip + a crowd "ooh" |
| Hype full | A rising shimmer + a can-shake rattle; loops softly while JUICE is available |
| Cooldown ready | A short click + chime pitched per ability slot |
| Round card / FIGHT! | A brass stab + a bell |

### 3.7 Crowd

Three loop layers (murmur, excited, roar) crossfaded by a "heat" value (recent damage + Hype totals), plus one-shots: "ooh" on big hits, "aww" on knockdowns against the player, chant (2-bar) during JUICE and Title Night, boo on taunts at low health, laughter on ring-outs, a "can shower" (rattling cans) on KO at Title Night. Per arena: The Gullet (indoor, reverberant), Drydock (open, distant, gulls), The Crusher (small rowdy crowd on a rim, echo), The Rooftop (crowd on the next roof, very distant, wind).

### 3.8 Announcer and coach babble

See ANNOUNCER_AND_TUTORIAL.md §1 and §2 for the grain and contour specs. Implementation: a grain player with 8 grains per character, pitch contour from punctuation, syllable rate per character; lines never exceed 4 s of babble. Both characters are on the **dialogue bus** with subtitles always on.

## 4. Mixing priorities

| Bus | Default | Ducking | Notes |
|---|---|---|---|
| Master | 0 dB | — | Limiter at −1 dBTP; no clipping at any combination of 8 fighters + JUICE + crowd (tested scene: 8-fighter FFA with 2 JUICE activations and 6 reactions in 2 s) |
| Impacts (SFX-critical) | 0 dB | **Never ducked**; highest priority voice stealing (max 24 voices; drops the quietest/oldest) | Includes parry, knockdown, KO |
| Whooshes/movement | −4 dB | Ducked −3 dB by impacts | Max 16 voices |
| Element/zone loops | −8 dB | Ducked −4 dB by impacts; zone loops limited to 6 audible (nearest) | |
| Voices (fighters) | −3 dB | Ducked −2 dB by impacts | |
| Dialogue (announcer/coach) | −2 dB | Ducks music −6 dB and crowd −3 dB while playing | User volume slider; "Reduced announcer" |
| Music | −8 dB combat, −12 dB hub, −6 dB menu | Ducked by dialogue; lead stem muted while dialogue plays | User slider |
| Crowd/ambience | −10 dB | Ducked −3 dB by dialogue | User slider (grouped under Effects or its own slider) |
| UI | −4 dB | — | User slider |

Priorities in one sentence: **you must always hear the hit, then the voice telling you what happened, then the music.** Readable-visual alternatives exist for every essential cue (hit flashes, status pips, telegraph decals, subtitles), so audio is never the only channel.

## 5. Variation and anti-repetition rules
- Every one-shot has ≥ 3 variants with ±4% random pitch and ±1 dB level; the same variant never plays twice in a row.
- Fighter voices have a per-line cooldown (taunt line 3 s, hit grunt 0.3 s).
- Footstep variants cycle; surface detection from the arena material tag.
- Music variants per match by seed (drum pattern, transposition); combat A/B chosen by act and mode.
- Crowd one-shots have an 8 s cooldown per type.
