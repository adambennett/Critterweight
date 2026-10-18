# Generated audio and replacement candidates

Audited for v0.9.12 on 2026-10-17. The shipped bank contains **638 generated WAV files, 128.8 MiB**. They were synthesized by this repository's JavaScript DSP/score pipeline, rather than recorded in Ableton or downloaded from a stock library. Replacing them is an aesthetic choice; they are not assets that must be replaced before shipping.

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

These are candidates selected from the creators' descriptions and metadata, **not an auditioned soundtrack selection**. Nothing here was downloaded or installed. Each listed Kevin MacLeod track offers a free **CC BY 4.0** download with attribution; his [licensing page](https://incompetech.com/music/royalty-free/licenses/) also offers paid alternatives without attribution. Keep the exact credit supplied with each download.

- **Title / fight-night poster: [Funkorama](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100474), Kevin MacLeod.** A 101 BPM funk groove with guitar, bass, organ and drums, 3:21. A plausible fit for the crooked sports-promotion tone and the gold/black menus. Try a restrained excerpt for the title and a busier section for pre-fight build-up.
- **Cannery: [Backbay Lounge](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1700068), Kevin MacLeod.** Relaxed piano/guitar/bass/drums lounge music, 120 BPM, 4:27. A candidate for a radio in the hub, mixed quietly beneath NPC dialogue.
- **Combat: [Furious Freak](https://incompetech.com/music/royalty-free/index.html?Search=Search&isrc=USUAN1600021), Kevin MacLeod.** Driving electronic music, 160 BPM, 3:07. The listed version has a long build; the creator mentions an alternate immediate start in the uncompressed download. Audition that version for instant fight energy.
- **Boss alternative: [Volatile Reaction](https://incompetech.com/music/royalty-free/index.html?Search=Search&isrc=USUAN1400039), Kevin MacLeod.** Intense orchestral percussion/brass, 155 BPM, 2:45 in 7/4. It would make bosses more cinematic; it may be too serious for the game's comic tone. Its meter also means the current four-beat layer assumptions need changing.
- **Results: [Music Jingles](https://kenney.nl/assets/music-jingles), Kenney.** 85 short CC0 cues. Audition contrasting success/failure stings for `victory.wav` and `defeat.wav`; short, clear endings should work better than another full track.

These finished recordings are not synchronized replacement stems. Do not play the generated percussion/lead layers underneath a new recording. Either obtain matching stems with the same license, or initially use one finished loop per cue and disable that cue's adaptive layers in the bank. Author a clean loop and measure its actual beat grid before enabling beat-aligned transitions.

## Sound shortlist

- **Punches, crates and collisions: [Impact Sounds](https://kenney.nl/assets/impact-sounds), Kenney.** 130 CC0 sounds. Start with body hits, wood/metal collisions and landing transients; choose softer variants for blocked hits so heavy contact retains contrast.
- **Menus and editor: [Interface Sounds](https://kenney.nl/assets/interface-sounds), Kenney.** 100 CC0 sounds for focus, accept, back, invalid, toggles, saves and editor placement. Keep focus movement very quiet because a held stick repeats it.
- **Footsteps / prop handling: [RPG Audio](https://kenney.nl/assets/rpg-audio), Kenney.** 50 CC0 sounds. Useful source material for footsteps and handling; audition material matches before replacing the game's five surface families and creature-size variants.
- **Harbour water: [Water waves](https://opengameart.org/content/water-waves), transitking / qubodup.** Four CC0 wave recordings. Candidates for Drydock or Slurry-related water, after trimming and seamless-loop editing.
- **Crowd bed: [crowd idle.wav](https://freesound.org/people/moxobna/sounds/102099/), moxobna.** CC0 crowd ambience, about 93.5 seconds. A candidate for quiet arena background, with distance filtering and modest gain.
- **Crowd reaction: [crowd cheer distant.wav](https://freesound.org/people/moxobna/sounds/102108/), moxobna.** CC0, about 18.9 seconds. A candidate for wins and dramatic hits. Inspect for prominent speech and trim distinct reactions; do not run this continuously. Freesound requires a login to download these files.
- **Optional human combat calls: [Voiceover Pack: Fighter](https://kenney.nl/assets/voiceover-pack-fighter), Kenney.** 45 CC0 voice clips. Suitable only if deliberately choosing a human voice direction; it does not replace the six creature casts or written NPC dialogue.

For industrial machinery, electric arcs, steam and monster source material, the [Sonniss GDC collection](https://gdc.sonniss.com/) is a larger optional search pool. Its [GDC bundle license](https://sonniss.com/gdc-bundle-license/) permits commercial use incorporated into games without mandatory attribution, but does not permit distributing the sounds as a raw sound library. Keep any selected source recordings outside a public source/mod SDK and record their provenance. The much smaller CC0 packs above are easier starting points for this repository.

## Integration approach

1. Audition music in an actual fight and hub session, with dialogue, impacts and crowd enabled. Choose the direction before replacing hundreds of small files.
2. Save the downloaded license, author, exact source page, download date and chosen filenames in `docs/THIRD_PARTY.md`; include required CC BY credits in `docs/CREDITS.md` and the in-game credits. CC0 credit is optional but useful for provenance.
3. Preserve bank event IDs and gameplay timing. Replace variations together so one generated outlier does not stand out. Use mono for spatial point effects, stereo where useful for music/ambience, and match perceived loudness with headroom.
4. Store imported replacements in a distinct directory and point `game/assets/audio/bank.json` at them. The DSP builder overwrites its generated filenames; keep stock assets out of that overwrite path. Update the inventory tool to classify imported provenance when this work happens.
5. For music, author loop points and adapt/disable layers as described above. For ambience, use sparse environmental detail and avoid persistent narrow tones. Do not normalize every quiet loop to the same loud peak as combat.
6. Run the audio bank/content tests, import and packaged Windows checks. Then listen to a full fight, transitions between every hub room, pause/unpause, focus changes, results and the AI Lab dropdowns. Metering and automated playback tests cannot establish that a track is pleasant.

## Buzz fix shipped in v0.9.12

The generated beds contained sustained machinery hums, a pad and electrical buzz. Their continuous tonal layers were removed from `amb_gullet`, `amb_crusher`, `amb_rooftop`, `amb_hub_main`, `amb_hub_booth`, `amb_hub_boiler`, `amb_hub_office` and `amb_hub_juice_bar`. Environmental water, wind and sparse details remain. The ambience player's crossfades also cancel old tweens before reusing either player, so rapid room changes cannot leave an old loop fading back in after a newer request.

This is the targeted fix requested for 0.9.12. It does not merge the separate Ableton experiment or claim that the proposed stock replacements have been approved by listening.
