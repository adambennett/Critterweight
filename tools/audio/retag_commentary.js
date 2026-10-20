'use strict';
// v0.9.17 commentary re-tagging (docs/audio/COMMENTARY.md §5). Reproducible: reads the reviewed
// per-line classification (docs/audio/commentary/classification.json: situation, alt situations,
// recent_action, register, families, energy, issues) and rewrites the announcer content files in
// place with accurate triggers and gates:
//   trigger   colour lines that describe a situation move to that situation's trigger
//             (a "That parry sent the plan aside" line is a parry call, not lull chatter)
//   also      further triggers the line is accurate for
//   when      gates for facts the line asserts (referee, 10-point scoring, venue, hazards, ...)
//   families  joke/topic families (selector spacing); energy (delivery, selection hint)
//   retired   lines that assert something the game does not have or gets wrong; never played
//   follow_id a line that answers this one (Barnaby asks, Kendall answers)
// Run: node tools/audio/retag_commentary.js [--check]   (--check: report only, write nothing)
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '../..');
const CLASSES = path.join(ROOT, 'docs/audio/commentary/classification.json');
const FILES = ['barnaby', 'barnaby_vintage', 'announcer_expansion'].map((f) => path.join(ROOT, 'game/content/core/announcer', f + '.json'));
const check = process.argv.includes('--check');

const SITUATION_TRIGGER = {
  generic: 'color', opening: 'opening', round_break: 'round_break', clean_hit: 'hit_clean', exchange: 'exchange',
  pressure: 'pressure', counter: 'counter', combo: 'combo', big_hit: 'big_hit', whiff: 'whiff', block: 'block',
  parry: 'parry', evade: 'evade', grab_throw: 'grab_throw', escape_grab: 'escape', reversal: 'comeback',
  knockdown: 'knockdown', getup: 'getup', wall: 'big_hit', edge: 'edge', ability: 'ability', element: 'element',
  hurt: 'hurt', late: 'late', close: 'close', result: 'result', fighter: 'fighter_color', matchup: 'matchup_color',
  juice: 'juice',
};
const WALL = { kind: 'wall' };

// Lines that assert what the game does not have, or get a fact wrong. Kept on disk (and their
// recordings) for provenance; never selected. Reasons are written into the line.
const RETIRE = {
  ann_exp_0340: 'feints are not a game mechanic', ann_exp_0367: 'feints are not a game mechanic',
  ann_exp_0376: 'feints are not a game mechanic', ann_exp_0397: 'feints are not a game mechanic',
  ann_exp_0116: 'no clinch in the game', ann_exp_0174: 'no ropes (cage/railings)', ann_exp_0719: 'no ropes; between bouts only',
  ann_v73_ringout_01: 'no ropes', ann_v73_first_01: "'first blood' (no blood in the game)",
  ann_exp_0086: "calls the partner 'Devon' (the voice's name, not Barnaby); re-recorded as cmt17",
  ann_exp_0206: "calls the partner 'Devon'; re-recorded as cmt17", ann_exp_0225: "calls the partner 'Devon'; re-recorded as cmt17",
  ann_exp_0829: 'wrong: Haunted slows cooldowns; corrected take recorded', ann_exp_0830: 'wrong: Haunted slows cooldowns; corrected take recorded',
  ann_exp_0837: 'wrong: Haunted slows cooldowns; corrected take recorded', ann_exp_0799: 'wrong: Port Hook is a light hook, not a pull',
  ann_exp_0054: 'high/low targeting is not modelled', ann_exp_0358: 'high/low targeting is not modelled',
  ann_exp_0377: 'high/low targeting is not modelled', ann_exp_0382: 'level changes are not modelled',
  ann_exp_0407: 'circling direction cannot be known', ann_exp_0302: "needs 'Glandco' said just before",
  ann_exp_0304: "needs 'clout' said just before", ann_exp_0602: 'too vague to place', ann_exp_0228: 'mixes a fence and an open edge',
  ann_exp_0230: 'outdoor wind across a cage (no such arena)', ann_exp_0725: 'pre-fight only', ann_exp_0740: 'between bouts only',
  ann_exp_0769: 'needs a missed rear uppercut (not tracked)', ann_exp_0405: 'repeats the sandwich-diagram joke of 0355',
  ann_exp_0024: 'assumes a corner stool (between-rounds furniture not shown)', ann_exp_0023: 'its answer (0024) is retired; a question left hanging',
  // corner crews are not in the game: lines claiming what a corner said or did describe nothing on screen
  ann_exp_0003: 'corner crew not in the game', ann_exp_0041: 'corner crew not in the game', ann_exp_0043: 'corner crew not in the game',
  ann_exp_0059: 'corner crew not in the game', ann_exp_0068: 'corner crew not in the game', ann_exp_0083: 'corner crew not in the game',
  ann_exp_0134: 'corner crew not in the game', ann_exp_0138: 'corner crew not in the game', ann_exp_0140: 'corner crew not in the game',
  ann_exp_0146: 'corner crew not in the game', ann_exp_0153: 'corner crew not in the game', ann_exp_0166: 'corner crew not in the game',
  ann_exp_0176: 'corner crew not in the game', ann_exp_0189: 'corner crew not in the game', ann_exp_0241: 'corner crew not in the game',
  ann_exp_0266: 'corner crew not in the game', ann_exp_0339: 'corner crew not in the game', ann_exp_0355: 'corner crew not in the game',
  ann_exp_0383: 'corner crew not in the game', ann_exp_0387: 'corner crew not in the game', ann_exp_0398: 'corner crew not in the game',
  ann_exp_0415: 'corner crew not in the game', ann_exp_0434: 'corner crew not in the game', ann_exp_0452: 'corner crew not in the game',
  ann_exp_0458: 'corner crew not in the game', ann_exp_0467: 'corner crew not in the game', ann_round_03: "assumes a cornerman; replaced by cmt17 round calls",
};

// Explicit placements: [trigger, when, also?]. Applied after the defaults.
const PLACE = {
  // referee / officials
  ann_exp_0137: ['getup', { referee: true }], ann_exp_0145: ['getup', { referee: true }], ann_exp_0152: ['getup', { referee: true }],
  ann_exp_0158: ['getup', { referee: true }], ann_exp_0165: ['knockdown', { referee: true }], ann_exp_0168: ['getup', { referee: true }],
  ann_exp_0173: ['getup', { referee: true }], ann_exp_0683: ['counter', { referee: true }], ann_exp_0778: ['fighter_color', { creature: 'f_varga', referee: true }],
  ann_exp_0410: ['color', { referee: true }], ann_exp_0421: ['color', { referee: true }], ann_exp_0020: ['color', { referee: true }],
  // 10-point scoring (judges, cards)
  ann_first_01: ['first_hit', { scoring: 'ten_point' }], ann_combo_05: ['combo', { kind: 'six_plus', scoring: 'ten_point' }],
  ann_time_01: ['time', { kind: 'ten_seconds', scoring: 'ten_point' }], ann_exp_0139: ['knockdown', { scoring: 'ten_point' }],
  ann_exp_0160: ['knockdown', { scoring: 'ten_point' }], ann_exp_0350: ['color', { scoring: 'ten_point' }],
  ann_exp_0448: ['late', { scoring: 'ten_point' }], ann_exp_0680: ['result', { finish: 'decision' }],
  ann_exp_0685: ['hit_clean', { scoring: 'ten_point' }], ann_exp_0695: ['result', { finish: 'decision' }],
  ann_exp_0700: ['result', { finish: 'decision' }], ann_v73_time_02: ['time', { kind: 'decision', scoring: 'ten_point' }],
  ann_exp_0504: ['color_conversation_start', { scoring: 'ten_point' }],
  // venues
  ann_round_02: ['round_start', { fence: true }], ann_juice_stoke_02: ['juice', { creature: 'f_stoke', fence: true }],
  ann_big_03: ['big_hit', { night: false }], ann_big_04: ['big_hit', { kind: 'charged', fence: true }], ann_big_06: ['big_hit', { kind: 'wall', fence: true }],
  ann_exp_0231: ['color', { venue: 'gullet' }], ann_exp_0261: ['color', { venue: 'gullet' }],
  ann_exp_0242: ['color', { outdoor: true }], ann_exp_0248: ['color', { outdoor: true }], ann_exp_0254: ['color', { outdoor: true }],
  ann_exp_0255: ['color', { outdoor: true }], ann_exp_0260: ['color', { outdoor: true }],
  ann_exp_0259: ['color', { outdoor: false }], ann_exp_0711: ['color', { outdoor: false }], ann_exp_0714: ['color', { outdoor: false }],
  ann_exp_0734: ['color', { outdoor: false }], ann_exp_0040: ['conversation_turn', { outdoor: false }],
  ann_exp_0226: ['element', { venue: 'rooftop' }], ann_exp_0229: ['color', { venue: 'rooftop' }], ann_exp_0233: ['opening', { venue: 'rooftop' }],
  ann_exp_0238: ['color', { venue: 'rooftop' }], ann_exp_0244: ['evade', { venue: 'rooftop' }], ann_exp_0246: ['color', { venue: 'rooftop' }],
  ann_exp_0251: ['color', { venue: 'rooftop' }], ann_exp_0197: ['edge', { open_edges: true }],
  ann_ringout_01: ['ringout', { open_edges: true }], ann_ringout_02: ['ringout', { who: 'player', open_edges: true }],
  ann_ringout_03: ['ringout', { kind: 'wind' }], ann_ko_10: ['ko', { kind: 'ringout', open_edges: true }], ann_v73_ko_02: ['ko', { kind: 'ringout' }],
  ann_exp_0227: ['color', { venue: 'drydock' }], ann_exp_0235: ['exchange', { venue: 'drydock' }], ann_exp_0252: ['color', { venue: 'drydock' }],
  ann_exp_0256: ['color', { venue: 'drydock' }], ann_exp_0265: ['color', { venue: 'drydock' }], ann_exp_0286: ['color', { venue: 'drydock' }],
  ann_exp_0743: ['color', { venue: 'drydock' }],
  ann_exp_0232: ['big_hit', { kind: 'wall', fence: true }], ann_exp_0239: ['big_hit', { kind: 'wall', fence: true }],
  ann_exp_0245: ['edge', { kind: 'cage' }], ann_exp_0249: ['color', { fence: true }], ann_exp_0258: ['color', { fence: true }],
  ann_exp_0401: ['edge', { kind: 'cage', hands: true }], ann_exp_0418: ['exchange', { fence: true }], ann_exp_0453: ['evade', { fence: true }],
  ann_exp_0603: ['edge', { kind: 'cage' }], ann_exp_0613: ['edge', { kind: 'cage' }], ann_exp_0621: ['edge', { kind: 'cage' }],
  ann_exp_0388: ['pressure', { fence: true }],
  // arena hazards and props (hazard / pickup / spring events)
  ann_exp_0181: ['ability', { id: 'steam_vent' }], ann_exp_0211: ['ability', { id: 'steam_vent' }], ann_exp_0196: ['reaction', {}],
  ann_exp_0183: ['spring', {}], ann_exp_0215: ['spring', {}], ann_exp_0191: ['ability', { id: 'spring_pad' }], ann_exp_0207: ['ability', { id: 'spring_pad' }],
  ann_exp_0592: ['pickup', {}], ann_exp_0598: ['pickup_available', {}], ann_exp_0606: ['pickup_available', {}],
  ann_exp_0612: ['pickup_available', {}], ann_exp_0618: ['pickup_available', {}],
  ann_exp_0595: ['evade', { props: true }], ann_exp_0596: ['evade', { props: true }], ann_exp_0600: ['evade', { props: true }],
  ann_exp_0604: ['evade', { props: true }], ann_exp_0619: ['color', { props: true }], ann_exp_0614: ['hazard', {}],
  // modes and formats
  ann_exp_0626: ['color', { format: 'tag' }], ann_exp_0641: ['color', { format: 'tag' }],
  ann_exp_0627: ['tag', {}], ann_exp_0633: ['tag', {}], ann_exp_0646: ['tag', {}],
  ann_exp_0625: ['color', { objective: true }], ann_exp_0630: ['color', { objective: true }], ann_exp_0631: ['goal', {}],
  ann_exp_0638: ['close', { objective: true }], ann_exp_0648: ['color', { objective: true }],
  ann_exp_0623: ['color', { special_rules: true }], ann_exp_0628: ['color', { special_rules: true }], ann_exp_0632: ['color', { special_rules: true }],
  ann_exp_0637: ['color', { special_rules: true }], ann_exp_0639: ['color', { special_rules: true }], ann_exp_0642: ['color', { special_rules: true }],
  ann_exp_0647: ['color', { special_rules: true }],
  ann_exp_0016: ['color', { sudden_death: true }], ann_exp_0636: ['late', { sudden_death: true }], ann_exp_0645: ['late', { sudden_death: true }],
  ann_exp_0281: ['close', { context: 'campaign' }],
  // abilities: readiness, misses, follow-ups
  ann_exp_0650: ['ability_ready', {}], ann_exp_0656: ['ability_ready', {}], ann_exp_0661: ['ability_ready', {}],
  ann_exp_0672: ['ability_ready', {}], ann_exp_0674: ['ability_ready', {}], ann_exp_0654: ['ability_ready', {}], ann_exp_0669: ['ability_ready', {}],
  ann_exp_0657: ['ability_miss', {}], ann_exp_0665: ['ability', { creature: 'f_slurry', id: 'sludge_lob' }],
  ann_exp_0658: ['stamina', {}], ann_exp_0664: ['stamina', {}], ann_exp_0670: ['stamina', {}],
  // results and round breaks with conditions
  ann_exp_0678: ['result', { finish: 'stopped' }], ann_exp_0686: ['result', { finish: 'stopped' }], ann_exp_0694: ['result', { finish: 'stopped' }],
  ann_exp_0698: ['result', { finish: 'stopped' }], ann_exp_0689: ['result', { finish: 'time' }], ann_exp_0693: ['result', { finish: 'time' }],
  ann_exp_0699: ['result', { finish: 'time' }], ann_exp_0705: ['result', { finish: 'time' }], ann_exp_0690: ['result', { finish: 'time', comeback: true }],
  ann_exp_0703: ['result', { finish: 'time', comeback: true }], ann_exp_0684: ['result', { close: true }],
  ann_exp_0681: ['round_break', { surge: true }], ann_exp_0697: ['round_break', { round_end: 'time' }], ann_exp_0702: ['round_break', {}],
  ann_exp_0736: ['round_break', {}], ann_exp_0426: ['knockdown', { final_round: false }], ann_exp_0413: ['evade', { round: '2plus' }],
  ann_exp_0624: ['late', { leader: true }], ann_exp_0635: ['late', { leader: true }], ann_exp_0634: ['round_start', { match_point: true }],
  // body plans and sizes
  ann_kd_03: ['knockdown', { kind: 'poise', legs: true }], ann_exp_0103: ['evade', { hands: true }], ann_exp_0109: ['evade', { hands: true }],
  ann_exp_0112: ['counter', { hands: true }], ann_exp_0126: ['evade', { hands: true }], ann_exp_0133: ['parry', { hands: true }],
  ann_exp_0342: ['opening', { hands: true }], ann_exp_0370: ['hit_clean', { hands: true }], ann_exp_0384: ['counter', { hands: true }],
  ann_exp_0389: ['pressure', { hands: true }], ann_exp_0319: ['close', { size_gap: true }], ann_exp_0347: ['opening', { size_gap: true }],
  ann_exp_0351: ['round_break', { size_gap: true }], ann_exp_0352: ['opening', { quick: true }],
  // taunts
  ann_exp_0333: ['taunt_punished', {}], ann_exp_0361: ['taunt_punished', {}],
  // Varga: move-specific calls, stance switches
  ann_exp_0764: ['hit_clean', { creature: 'f_varga', slot: ['rl_lkick', 'll_lkick', 'rl_lkick@southpaw', 'll_lkick@southpaw'] }],
  ann_exp_0768: ['hit_clean', { creature: 'f_varga', slot: ['rl_bkick', 'll_bkick', 'rl_bkick@southpaw', 'll_bkick@southpaw'] }],
  ann_exp_0775: ['hit_clean', { creature: 'f_varga', slot: ['rh_overhand', 'lh_overhand', 'rh_overhand@southpaw', 'lh_overhand@southpaw'] }],
  ann_exp_0774: ['hit_clean', { creature: 'f_varga', slot: ['rl_knee', 'll_knee', 'rl_knee@southpaw', 'll_knee@southpaw'] }],
  ann_exp_0760: ['stance', { creature: 'f_varga' }], ann_exp_0767: ['stance', { creature: 'f_varga' }],
  ann_exp_0773: ['stance', { creature: 'f_varga' }], ann_exp_0781: ['stance', { creature: 'f_varga' }],
  ann_exp_0777: ['evade', { creature: 'f_varga' }],
  // Knell: move-specific calls and follow-ups
  ann_exp_0798: ['hit_clean', { creature: 'f_knell', slot: 'l1' }], ann_exp_0800: ['hit_clean', { creature: 'f_knell', slot: 'l3' }],
  ann_exp_0801: ['windup', { creature: 'f_knell', slot: 'heavy' }], ann_exp_0802: ['windup', { creature: 'f_knell', slot: 'heavy_charged' }],
  ann_exp_0803: ['hit_clean', { creature: 'f_knell', slot: 'dash_attack' }], ann_exp_0804: ['combo', { creature: 'f_knell', kind: 'finisher' }],
  ann_exp_0809: ['grab_throw', { creature: 'f_knell' }], ann_exp_0810: ['taunt', { creature: 'f_knell' }],
  ann_exp_0811: ['big_hit', { creature: 'f_knell' }],
  ann_exp_0797: ['ability_follow', { creature: 'f_knell', id: 'ghost_light' }], ann_exp_0806: ['ability_follow', { creature: 'f_knell', id: 'ghost_light' }],
  ann_exp_0812: ['ability_follow', { creature: 'f_knell', id: 'ghost_light' }], ann_exp_0813: ['ability_follow', { creature: 'f_knell', id: 'ghost_light' }],
  ann_exp_0818: ['ability_follow', { creature: 'f_knell', id: 'through_the_veil' }], ann_exp_0808: ['juice_follow', { creature: 'f_knell' }],
  ann_exp_0817: ['juice_follow', { creature: 'f_knell' }], ann_exp_0816: ['intro_follow', { creature: 'f_knell' }],
  ann_exp_0850: ['matchup_color', { matchup: 'f_jitters|f_knell' }],
  // element facts that are really matchup facts, or need the status in play
  ann_exp_0824: ['matchup_color', { matchup: 'f_dozer|f_varga' }], ann_exp_0833: ['matchup_color', { matchup: 'f_knell|f_varga' }],
  ann_exp_0834: ['matchup_color', { matchup: 'f_jitters|f_knell' }], ann_exp_0821: ['element', { element: 'scrap', status: 'rattled' }],
  ann_exp_0825: ['element', { element: 'scrap', status: 'rattled' }], ann_exp_0832: ['element', { element: 'spectral', status: 'haunted' }],
};
// Q&A pairs and callbacks: [question, answer]
const PAIRS = [['ann_exp_0021', 'ann_exp_0022'], ['ann_exp_0025', 'ann_exp_0026'], ['ann_exp_0027', 'ann_exp_0028'],
  ['ann_exp_0029', 'ann_exp_0030'], ['ann_exp_0031', 'ann_exp_0032'], ['ann_exp_0033', 'ann_exp_0034'], ['ann_exp_0035', 'ann_exp_0036'],
  ['ann_exp_0037', 'ann_exp_0038'], ['ann_exp_0039', 'ann_exp_0040'], ['ann_exp_0710', 'ann_exp_0732'], ['ann_exp_0715', 'ann_exp_0730']];

// element hints the classifiers wrote as "element=x"
function elementGate(issues) {
  const m = /element=(scorch|brine|gale|grit|sludge|static|scrap|spectral)/.exec(issues || '');
  return m ? m[1] : '';
}

function main() {
  const classes = Object.fromEntries(JSON.parse(fs.readFileSync(CLASSES, 'utf8')).map((c) => [c.id, c]));
  const report = { moved: {}, retired: [], gated: 0, pools: {} };
  for (const file of FILES) {
    const doc = JSON.parse(fs.readFileSync(file, 'utf8'));
    const items = doc.items || doc;
    for (const e of items) {
      const c = classes[e.id];
      if (!c) continue;
      const fams = (c.families || []).map((f) => String(f).replace(/^other:/, ''));
      e.families = Array.from(new Set(fams));
      e.energy = c.energy || 'medium';
      e.situation = c.situation;
      if (e.conversation_id) {
        // conversations keep their turn triggers; only explicit gates apply
      } else if (e.trigger === 'color' || (e.trigger === 'fighter_color' && c.situation !== 'fighter') || (e.trigger === 'element_color' && c.situation !== 'element')) {
        let trig = SITUATION_TRIGGER[c.situation] || 'color';
        if (trig !== e.trigger) {
          report.moved[`${e.trigger}->${trig}`] = (report.moved[`${e.trigger}->${trig}`] || 0) + 1;
          if (c.situation === 'wall') e.when = Object.assign({}, e.when || {}, WALL);
          if (trig === 'element' && !(e.when || {}).element) {
            const el = elementGate(c.issues);
            if (el) e.when = Object.assign({}, e.when || {}, { element: el });
          }
          e.trigger = trig;
        }
        const also = (c.alt || []).map((s) => SITUATION_TRIGGER[s]).filter((t) => t && t !== e.trigger && !['color', 'result', 'fighter_color', 'matchup_color'].includes(t));
        if (also.length) e.also = Array.from(new Set(also));
        else delete e.also;
      }
      if (PLACE[e.id]) {
        const [trig, when] = PLACE[e.id];
        e.trigger = trig;
        e.when = Object.assign({}, e.when || {}, when);
        if (when.slot) delete e.when.move;      // a slot gate replaces an older move-id gate
        report.gated += 1;
      }
      if (RETIRE[e.id]) {
        e.retired = RETIRE[e.id];
        report.retired.push(e.id);
      } else {
        delete e.retired;
      }
    }
    for (const [q, a] of PAIRS) {
      const qe = items.find((x) => x.id === q);
      if (!qe) continue;
      if (a) {
        qe.follow_id = a;
        const ae = items.find((x) => x.id === a);
        if (ae) { ae.trigger = 'follow'; ae.when = {}; delete ae.also; }
      }
    }
    for (const e of items) {
      if (e.retired) continue;
      for (const t of [e.trigger].concat(e.also || [])) report.pools[t] = (report.pools[t] || 0) + 1;
    }
    if (!check) fs.writeFileSync(file, JSON.stringify(doc, null, 2) + '\n');
  }
  report.retired_count = report.retired.length;
  report.pools = Object.fromEntries(Object.entries(report.pools).sort((x, y) => y[1] - x[1]));
  console.log(JSON.stringify(report, null, 1));
}

main();
