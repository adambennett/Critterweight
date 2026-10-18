# Generated audio and replacement candidates

The v0.9.12 audit found **638 generated WAV files, 128.8 MiB**, made by this repository's JavaScript DSP/score pipeline. v0.9.13 now layers selected free replacements over those sources in a separate bank override, preserving the generated files and making each choice reproducible.

The complete, hash-checked file list is [generated-audio-inventory.txt](generated-audio-inventory.txt). The [JSON version](generated-audio-inventory.json) includes each file's SHA-256, duration, sample rate, channels and every direct bank reference. Regenerate both with `node tools/audio/inventory.js`.

## What is generated

- Music: 18 files (eight base cues and ten adaptive layers).
- Voices: 156 creature sounds; announcer: 52 speech/grain files.
- Combat: 73 impacts, 35 movement sounds, 24 reactions, 20 projectiles, 12 abilities and 10 JUICE effects.
- World: 100 footsteps, 30 elemental effects, 25 hazards, 23 crowd sounds, 12 ambience loops and eight zones.
- Interface: 40 sounds.

All paths below are under `game/assets/audio/music/`:

- `title_night.wav`: title/menu.
- `fight_night_poster.wav`: pre-fight/build-up.
- `cannery_radio.wav`: hub.
- `combat_a.wav`, `combat_a_lead.wav`, `combat_a_perc2.wav`, `combat_a_perc3.wav`: combat A and its layers.
- `combat_b.wav`, `combat_b_arp.wav`, `combat_b_perc2.wav`, `combat_b_perc3.wav`: combat B and its layers.
- `boss.wav`, `boss_bilge.wav`, `boss_conduit.wav`, `boss_snappington.wav`, `boss_p2.wav`: boss base and layers.
- `victory.wav`, `defeat.wav`: results.

The most valuable first replacements are the three menu/hub cues, the combat bases and ambience/crowds. They repeat for long stretches and dominate the game's sound. Creature calls and the announcer need a separate casting/recording decision; generic human voice packs will not preserve the current creature identities or the announcer's custom lines.

## Music shortlist

These tracks were selected from the creators' descriptions and metadata, not from an in-game listening review. The four free MP3s are installed in v0.9.13 under **CC BY 4.0** with the required attribution. The Incompetech page also offers paid versions; none were used.

- **Title / fight-night poster: [Funkorama](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100474), Kevin MacLeod.** A 101 BPM funk groove with guitar, bass, organ and drums, 3:21. A plausible fit for the crooked sports-promotion tone and the gold/black menus. Try a restrained excerpt for the title and a busier section for pre-fight build-up.
- **Cannery: [Backbay Lounge](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1700068), Kevin MacLeod.** Relaxed piano/guitar/bass/drums lounge music, 120 BPM, 4:27. A candidate for a radio in the hub, mixed quietly beneath NPC dialogue.
- **Combat: [Furious Freak](https://incompetech.com/music/royalty-free/index.html?Search=Search&isrc=USUAN1600021), Kevin MacLeod.** Driving electronic music, 160 BPM, 3:07. The listed version has a long build; the creator mentions an alternate immediate start in the uncompressed download. Audition that version for instant fight energy.
- **Boss alternative: [Volatile Reaction](https://incompetech.com/music/royalty-free/index.html?Search=Search&isrc=USUAN1400039), Kevin MacLeod.** Intense orchestral percussion/brass, 155 BPM, 2:45 in 7/4. It would make bosses more cinematic; it may be too serious for the game's comic tone. Its meter also means the current four-beat layer assumptions need changing.
- **Results: [Music Jingles](https://kenney.nl/assets/music-jingles), Kenney.** 85 short CC0 cues. Audition contrasting success/failure stings for `victory.wav` and `defeat.wav`; short, clear endings should work better than another full track.

These finished recordings are not synchronized replacement stems. Do not play the generated percussion/lead layers underneath a new recording. Either obtain matching stems with the same license, or initially use one finished loop per cue and disable that cue's adaptive layers in the bank. Author a clean loop and measure its actual beat grid before enabling beat-aligned transitions.

## Sound shortlist

- **Punches, footsteps, crates and collisions: [Impact Sounds](https://kenney.nl/assets/impact-sounds), Kenney.** 130 CC0 sounds. Selected body hits, wood/metal collisions, landing transients and material footsteps are installed; softer variants cover blocked hits so heavy contact retains contrast.
- **Menus and editor: [Interface Sounds](https://kenney.nl/assets/interface-sounds), Kenney.** 100 CC0 sounds for focus, accept, back, invalid, toggles, saves and editor placement. Keep focus movement very quiet because a held stick repeats it.
- **Book and coin handling: [RPG Audio](https://kenney.nl/assets/rpg-audio), Kenney.** 50 CC0 sounds. Book flips and coin handling are installed for the corresponding interface cues.
- **Harbour water: [Waterflow Sound](https://opengameart.org/content/waterflow-sound), TyberiusGames.** The CC0 MP3 is installed as the quiet dock bed. The four CC0 [Water waves](https://opengameart.org/content/water-waves) FLAC recordings from transitking / qubodup were considered but not installed because the stock Godot importer does not support FLAC.
- **Crowd bed: [Crowd Shouting/Speaking Ambience](https://opengameart.org/content/crowd-shoutingspeaking-ambience), StarNinjas.** CC0 OGG, used at low gain for the arena bed. Freesound crowd-idle required a login, so this freely downloadable alternative was selected.
- **Crowd reaction: [Applause in a Large Hall or Church](https://opengameart.org/content/applause-in-a-large-hall-or-church), eXpl0it3r.** CC0 WAV, wired to the crowd-cheer event as a one-shot.
- **Optional human combat calls: [Voiceover Pack: Fighter](https://kenney.nl/assets/voiceover-pack-fighter), Kenney.** 45 CC0 voice clips. Suitable only if deliberately choosing a human voice direction; it does not replace the six creature casts or written NPC dialogue.

For industrial machinery, electric arcs, steam and monster source material, the [Sonniss GDC collection](https://gdc.sonniss.com/) is a larger optional search pool. Its [GDC bundle license](https://sonniss.com/gdc-bundle-license/) permits commercial use incorporated into games without mandatory attribution, but does not permit distributing the sounds as a raw sound library. Keep any selected source recordings outside a public source/mod SDK and record their provenance. The much smaller CC0 packs above are easier starting points for this repository.

## Owner listening review

The v0.9.13 bank and recordings are installed. The placements below were chosen from the recordings' descriptions and metadata; automated checks cover import, hashes, bank references and loop settings, but cannot judge sound quality. In-game, listen to the title/menu, Cannery radio under dialogue, a full ordinary fight, boss JUICE transitions, result stings, crowd reactions, the dock ambience and menu sounds. Check volume against dialogue and impacts, abrupt restarts after returning to a screen, and whether the repeated material fits the tone. The owner can then keep or revise individual paths and gains in `game/assets/audio/replacement-overrides.json`.

The exact downloaded recordings, authors, source links, licenses, hashes and bank references are in `game/assets/audio/replacements/replacement-audio-inventory.json` and `docs/THIRD_PARTY.md`. Required CC BY attribution is in the in-game Credits and `docs/CREDITS.md`; all other installed recordings are CC0. Music is played as a finished recording without mismatched generated layers. The audio bank tests and packaged smoke checks verify technical integration, not an aesthetic approval.

## Installed in v0.9.13

The game contains **126 imported audio files (~34.8 MiB)**, and all 126 unique replacement paths are referenced from the bank. The separate replacement-audio-inventory.txt lists every file, source, licence, SHA-256 and bank reference; tools/audio/inventory.js rebuilds it.

- **Music:** Funkorama handles both title/menu and fight-night poster; Backbay Lounge is the Cannery radio; Furious Freak fills both combat slots; Volatile Reaction is the boss cue and keeps a 7/4 section B jump for JUICE. Kenney Pizzicato/Hit jingles handle victory and defeat. The original adaptive stems are disabled for these finished tracks.
- **Combat and movement:** Kenney punch/plate/metal impacts replace light/heavy hits, material impacts, guard/parry and wall contacts. Five-variant Kenney footsteps replace all four creature plans across canvas, concrete, steel, plank and gravel surfaces, with per-plan pitch ranges; hard floor stands in for steel and snow crunch for gravel. Landing sounds use matching impact clips.
- **Menus:** Kenney scroll, confirmation, back, error, toggle, tick, select, open, close, coin and book sounds replace the common UI actions.
- **World:** the low-gain StarNinjas crowd OGG loops as crowd ambience; the eXpl0it3r applause WAV is the crowd-cheer reaction; TyberiusGames waterflow MP3 is the quiet Drydock/dock bed. The water-wave FLAC candidates were not used because Godot's stock importer does not support FLAC.

Every installed file is CC BY 4.0 or CC0 1.0 and free to use without a composer payment. The CC BY tracks require the Kevin MacLeod attribution shown in docs/CREDITS.md and in-game Credits; CC0 clips are credited there as provenance. Original named-creature and announcer voices remain generated because the optional human voice pack is not an appropriate drop-in replacement.

The recordings are installed and automated import/bank/hash checks pass. The owner can audition them in this release and decide what should change. See game/assets/audio/replacements/provenance.json for the terms and exact sources.

## Buzz fix shipped in v0.9.12

The generated beds contained sustained machinery hums, a pad and electrical buzz. Their continuous tonal layers were removed from `amb_gullet`, `amb_crusher`, `amb_rooftop`, `amb_hub_main`, `amb_hub_booth`, `amb_hub_boiler`, `amb_hub_office` and `amb_hub_juice_bar`. Environmental water, wind and sparse details remain. The ambience player's crossfades also cancel old tweens before reusing either player, so rapid room changes cannot leave an old loop fading back in after a newer request.

This is the targeted fix requested for 0.9.12. The separate Ableton experiment remains untouched; the v0.9.13 stock replacements use a distinct bank override and await the owner's listening review.
