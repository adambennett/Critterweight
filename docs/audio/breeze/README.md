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

## Commentary overhaul for v0.9.17

Authorized by the owner's v0.9.17/v0.9.18 specification (2026-10-20): one Breeze allowance of
10,000 credits for both releases, the approved voices only (Devon for Barnaby, Kendall, Coach Buck),
the existing key workflow, offline shipped speech. `tools/audio/breeze/prepare_commentary_v0917.py`
turns `commentary_script.txt` (the reviewed v0.9.17 lines: new calls for stoppages, decisions, round
results, every fighter's abilities and ability hits, observations, Career context, conversations,
corrected re-records, whole-sentence name variants and ceremonial winner names) into `v0.9.17/plan.json`.
`generate.py` journaled every request in `v0.9.17/generation-ledger.jsonl` before sending it; there
were no uncertain requests and no automatic retries.

After the technical speech audit (`tools/audio/breeze/audit_speech.py`: levels, clipping, silences,
endings, pace, pitch range, joins; heuristics, not a listening verdict) 20 retakes were generated
with direction notes for the problem (`tools/audio/breeze/prepare_retakes_v0917.py`,
`v0.9.17/plan-retakes.json`): four cut-off endings, four flat deliveries on big calls, three long
mid-line pauses and the eight fastest deliveries. One retake was rejected (its ending was unclear;
a second take replaced it) and one had a stray sound after 0.4 s of digital silence trimmed from its
end (`v0.9.17/retakes-installed.json`). Replaced takes stay journaled and their raw masters stay on B:.

Installed: 521 clips (426 Devon, 93 Kendall, 2 Coach Buck), 33.7 minutes, 97,067,644 bytes of mono
16-bit PCM at 24 kHz under `game/assets/audio/speech/v0917/` with `catalog.json` (498 lines); every
installed WAV matches its catalog SHA-256. Raw masters: `B:\Critterweight-work\v0.9.17\breeze-raw`.
Spend: 541 completed requests, 3,255.8 credits (3,132.2 for the main batch, 123.6 for retakes); the
provider reports 3,255.8 used, zero reserved and 6,744.2 remaining of the 10,000 allowance
(`v0.9.17/budget-final.json`). This was the provider balance at the end of the v0.9.17 batch.
At the 2026-10-21 takeover, Claude had also generated v0.9.18 commentary and tutorial recordings:
the combined saved ledger is 4,425.0 credits spent and 5,575.0 remaining across both releases.
No human listening review has been performed; publication is authorized by the owner.

## Movesets commentary and tutorials for v0.9.18

The same 10,000-credit allowance funded 132 new commentary clips (103 Devon, 29 Kendall) and
122 Coach Buck tutorial fragments composing 36 tutorial lines. Installed duration is 671.405
seconds. Plans, request journals and catalogs are in `v0.9.18/`; the runtime catalogs and WAVs
are in `game/assets/audio/speech/v0918/`. Raw masters remain under
`B:\Critterweight-work\v0.9.18\breeze-raw`.

The technical audit led to 26 retake requests: ten commentary and thirteen tutorial replacements
were selected, with three rejected takes retained in the journal. See `retakes-installed.json`
and `retakes-tutorial-installed.json`. The 2026-10-21 takeover integrity check verified all 254
installed clips against both their catalog and completed request journal: SHA-256, duration,
mono 24 kHz PCM16, non-silence and peaks at or below -3 dBFS. This is technical evidence, not a
human listening verdict. All shipped speech plays offline.

v0.9.18 spent 818.4 credits on commentary and 350.8 on tutorials. Combined with v0.9.17's
3,255.8, the saved provider report records **4,425.0 used, zero reserved, 5,575.0 remaining**.
No paid generation was added during takeover. `docs/evidence/verification/v0.9.18/audio/`
retains the installed-file integrity report.
