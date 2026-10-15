# CRITTERWEIGHT — Game Pitch

> Design-authority doc. Everything player-facing uses the names in this file. The repository name "PokeMMA" is a placeholder and never appears in-game.

## Title and logline

**CRITTERWEIGHT**

*Six over-juiced critters. One cage. Zero regulations.*

A 3D creature cage-fighting game where every fighter is a physical, flailing, stumbling active ragdoll. Mash your way to glory, or learn the spacing and timing that makes a 160 kg crab throw a bird into the sponsor boards. Between fights, run a seeded roguelike fight card: branching routes, shady supplements, side effects, bosses with two phases, and a league commissioner who has never once been drug-tested.

## Design pillars

| # | Pillar | What it means in practice |
|---|---|---|
| 1 | **Contact is the truth** | Damage only happens when a weapon point physically reaches a body with closing speed. Reach, body shape, spacing and footwork matter. Hits shove, stagger, and knock bodies down; the comedy and the depth both come from physics, never from canned hit-confirms. |
| 2 | **Mashable, then masterable** | Left stick + Light + Heavy gets a brand-new player through an easy fight with a grin. Guard, Dodge, Parry, Grab, two Abilities and JUICE layer on top. No motion inputs, no frame-perfect links, no button chords for basic competency. |
| 3 | **Six reasons to exist** | Each of the six fighters is a different body plan, a different element, and a different *problem to solve*. No recolors. If two fighters could swap kits and nobody would notice, one of them is cut. |
| 4 | **Builds you can feel** | Roguelike upgrades change how a fighter moves and hits, not just a number in a tooltip. Every supplement has a flavor, many have a side effect, and build synergies read on screen (bigger puddles, longer charges, more pads). |
| 5 | **Satire with a straight face** | The Circuit is a shameless, corrupt, lovable combat-sport promotion. The jokes come from the world taking itself seriously: sponsor reads, weight classes nobody enforces, "supplements" that are obviously not supplements. Cartoony-mature, PG-13, never cruel. |

## Setting and lore

### Gullet Bay
A rust-streaked harbor city built around a defunct fish cannery. Fog, neon, gulls, pallets. The kind of place where the health inspector is also the bookie.

### The Critterweight Circuit ("the Circuit")
The world's only sanctioned creature cage-fighting league. "Sanctioned" by the **Gullet Bay Athletic Commission (GBAC)**, a body consisting of one ancient snapping turtle, **Commissioner Snappington**, who writes the rulebook, enforces it selectively, and holds the undefeated title belt she awarded herself in 1973.

The Circuit runs **fight cards** out of the old cannery. A card has three parts, which are also the three acts of a campaign run:

| Act | Card segment | Vibe |
|---|---|---|
| 1 | **The Undercard** | Daytime harbor shows, dock crowds, cheap seats. |
| 2 | **The Main Card** | Scrapyards and rooftops, night crowds, real money. |
| 3 | **The Title Card** | Prime time inside The Gullet. Confetti cannons. The Commissioner is watching. |

### Glandco and the JUICE
The Circuit's title sponsor is **Glandco**, a "nutritional" conglomerate whose flagship product is **Glandco JUICE**. Nobody knows what is in it. Everybody drinks it. In-fight, a full Hype meter lets a fighter *hit the JUICE*: a short, spectacular, slightly irresponsible ultimate.

Glandco also sells the in-run upgrades the game calls **supplements**: Tusk Dust, Marrow Shake, Gland Tonic, Pre-Workout Bile. Rarities are literally **Over-the-Counter → Prescription → Black Market → Banned Substance**. Side effects are printed on the label in a font nobody reads.

### Weight classes (decorative, like the drug testing)

| Class | Mass | Roster |
|---|---|---|
| Pipsqueak | ≤ 65 kg | Jitters, Gusto |
| Scrapper | 66–110 kg | Stoke, Slurry |
| Lunker | 111–145 kg | Dozer |
| Absolute Unit | 146–170 kg | Dredge |

Everyone fights everyone. The classes exist so the announcer has something to say.

### The people (see HUB.md and ANNOUNCER_AND_TUTORIAL.md)
- **Barnaby Bellows** — pelican, ring announcer, sequined jacket, former fish-market auctioneer. The voice of the game.
- **Granny Haymaker** — possum, head coach, bare-knuckle champion of the cannery era, 4 feet tall, terrifying.
- **Commissioner Snappington** — snapping turtle, runs the league, final boss.
- **Needles** — porcupine, runs the Juice Bar, sells supplements, denies everything.
- **Doc Sutura** — octopus veterinarian and cut-woman. Eight hands, no bedside manner.
- **Kid Lamprey** — hoodie-wearing up-and-comer, sparring partner, trash talker.
- **Ludlow** — walrus janitor, former ring crew, knows every secret in the building.
- **Teddy Two-Tooth** — rat bookie, runs the autobattler table.

## Tone and satire guidelines

**Do**
- Treat the Circuit as a real sport that everyone involved takes very seriously. The humor is in the gap between the pomp and the rust.
- Let the fighters be athletes with personalities: Stoke is impatient, Dredge is weary, Gusto is a showboat, Dozer is a cheerful dope, Slurry is smug, Jitters is anxious.
- Use the supplement theme for *mechanics with tradeoffs*: power with a side effect, a stat that goes up while another goes down, a label that lies.
- Keep vulgarity rare and earned. One good "hell" lands harder than ten.
- Keep gore cosmetic and cartoon-silly: a tooth pings off the cage, a horn tip embeds in the sponsor board.

**Avoid**
- Real drug names, real supplement brands, real dosing advice, needles-in-arms imagery. "JUICE" is a glowing green can; Needles the porcupine is a visual pun, not a drug reference.
- Real fighters, promotions, catchphrases, walkout songs, logos, ring-card formats, or "parody" names that are one letter off from a real person or brand.
- Anything sexual, any slur, any joke whose target is a real group. Body humor is fine (Dredge molts; Slurry hiccups), humiliation of a group is not.
- Mean-spirited losing. Defeat lines rib the player; they never call the player bad.
- Edgelord tone. The game is confident and warm. The world is corrupt; the characters are not cynical.
- Any Pokémon / Digimon / Palworld / real combat-sport terminology: no "types", no "trainers", no "evolution", no "octagon" by name (the cage is **The Gullet**, an eight-sided cage), no "ultimate fighting", no "title belt" lookalikes of real designs.

**Rating target:** PG-13 / PEGI 12 equivalent. Cartoon violence, mild language, fictional substance humor framed as satire.

## Naming conventions

| Thing | Convention | Examples |
|---|---|---|
| Fighters | One word, 1–2 syllables, a plain-English word used as a ring name; ALL CAPS in UI, Title Case in prose. Epithet: "the <Species Nickname>". | STOKE the Boiler Newt, DREDGE the Dock Crab |
| Elements | One-syllable-ish nouns for a force or substance; statuses are adjectives/verbs. | Scorch → Sizzle, Brine → Soaked |
| Moves | Title Case, 1–3 words, concrete and physical. Lights are plain (Jab, Cross), Heavies are brand-flavored (Overhand Boiler), JUICE ultimates are grandiose (Meltdown). | — |
| Supplements | Product names: <Body Part/Fluid> + <Form>. | Tusk Dust, Marrow Shake, Gland Tonic |
| Techniques | Gym-talk phrases. | Lead Hand Learner, Quarry Legs |
| Modes | Two punchy words. | Spotlight Hog, Chum Rush |
| Difficulty | Fight-card slang. | Sparring, Undercard, Main Card, Title Shot |
| Challenge ladder | **The Dosage**, levels "Dose 1" … "Dose 10". | — |
| Bot skill tiers | Career-stage nouns. | Punching Bag, Journeyman, Contender, Headliner, Hall-of-Famer |
| Currencies | **Scrip** (in-run, Glandco company scrip) and **Clout** (persistent, fame). | — |
| Data ids | `snake_case`, stable, prefixed by domain: `f_stoke`, `enc_a1_dock_rats`, `evt_boiler_inspector`, `sup_tusk_dust`, `tech_stoke_pressure_cooker`, `arena_gullet`, `mode_chumball`. | — |
| Campaign variants | **Off the Street** (fresh-run, no persistent power) and **Fight Camp** (persistent progression from the hub, **The Cannery**). | — |
| Autobattler | **The Bookie's Table**. | — |

### Trademark note for the engineering lead
All names are original coinages or common English words. Before any commercial release, run a quick clearance pass on the game title and on the common-word fighter names (Dredge, Gusto, Stoke, Dozer) against game titles in the same category. Alternates are pre-approved if a clash turns up: DREDGE → **BOLLARD**, GUSTO → **KITER**, STOKE → **FIREBOX**, DOZER → **TAMPER**.

## Core experience loop (one paragraph for the README)

Pick a critter. Fight in a cage where every punch is a physical object. Win, pick a supplement from a shady porcupine, choose a route on the fight card, win again, meet a boss with two phases, hit the JUICE, lose a tooth, get the belt. Then do it again on a higher Dose with a friend, in tag-team, in a cage you built yourself.
