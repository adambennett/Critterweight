# Recorded dialogue for the v0.9.15 preview

The owner authorized the full spoken-content batch on 2026-10-18, with a 3,500-credit cap,
using Devon and Kendall, then specifically chose Coach Buck for the coach. `plan.json`
contains the reviewed source extraction and exact estimate. `generation-ledger.jsonl`
journals each request before sending and records every completed take; a missing completion
requires inspecting the provider history before retrying. No key appears in these files.

The three actors cover eight in-world roles. Devon leads Barnaby's standard and Vintage
Bellows commentary, plus Snappington, Doc and Ludlow; Kendall handles selected comic calls,
Teddy, Needles and Kid Lamprey; Coach Buck handles all Granny/tutorial material. Role-specific
instructions vary delivery. This is a preview cast for the owner's listening review, not eight
independently selected voices. No extra voices were designed or purchased.

`tools/audio/breeze/plan.py` extracts announcer, hub, tutorial, secret, tape and recap text.
`generate.py` defaults to a dry run; `--generate --max-credits 3500` performs paid generation.
It verifies completed takes and their hashes, checks the provider's remaining key allowance,
uses two short requests at a time, and makes no automatic retries. Existing key access uses
the ThirdAgeModern Credential Manager target or BREEZE_API_KEY in process memory. Helpers
were adapted from that repository's production workflow; the repository itself is unchanged.
Raw WAV masters are preserved at B:/Critterweight/release-work/v0.9.15-preview2/breeze-raw.
Runtime assets are game/assets/audio/speech and require no account or network connection.

Names/numbers use reusable recorded fragments to stay within budget. Known roster names,
Rookie, Player 1-8 and numeric values are supported; custom names remain exact in subtitles.
Tutorial recordings speak action names while the visible instructions show live bindings.
Unbounded/mod-added dialogue retains the existing fallback. The owner-selected 17 player names are covered in every voice, with worm/werm spelling
aliases sharing recordings. Some joins may benefit from whole-sentence retakes after listening.

Terms: https://breezeblue.ai/legal/terms, section 5d, checked 2026-10-18. The owner's active
paid subscription allows commercial use of outputs, including library voices, and that
permission survives cancellation. No continuing composer royalty is specified for these
eligible outputs. Pricing: https://breezeblue.ai/pricing, one credit per ten weighted characters.
Generation completed 2026-10-18: 764 WAV clips (393 Devon, 150 Kendall, 221 Coach Buck),
497 authored/composed subtitle entries, 31.99 minutes, 92,153,056 bytes. Every installed WAV
matches its journal/catalog SHA-256, decodes as mono 16-bit PCM, and has a peak at or below
-3 dBFS. The provider reports 3,230.2 credits used, zero reserved and 269.8 remaining from
the authorized 3,500. See budget-final.json. No further generation is pending.

Recorded playback uses actual clip duration, sequential completion signals, and the existing
priority/interrupt queue. NPC bubbles follow recorded duration. Explicit conversation choices
and lesson transitions replace stale speech. Physical listening approval remains with the owner.

## Announcer expansion for the v0.9.15 preview

Generated 2026-10-18 for the v0.9.15 playtest preview. The approved batch contains 854 offline recordings: 515 Devon takes for Barnaby and 339 Kendall takes, totaling 49 minutes 21 seconds. The nine rare booth conversations are ten turns each. The added 108 takes call out Varga, Knell, Scrap, Spectral, ability use and eight roster matchups.

The provider charged 5,656.5 credits from the owner's 6,000-credit allowance, leaving 343.5. All 854 processed WAVs and their raw masters match the generation journal SHA-256 values. Installed clips are mono 24 kHz PCM16 with peaks between -7.3 and -3.0 dBFS. Runtime files are under `game/assets/audio/speech/announcer_expansion/`; raw masters are in `B:/Critterweight/release-work/v0.9.15-preview4/breeze-raw`. See `announcer-expansion-audit.json`, `announcer-expansion-ledger.jsonl`, and `announcer-expansion-budget-final.json` for verification.
