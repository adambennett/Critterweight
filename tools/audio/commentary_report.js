'use strict';
// Commentary audit report (docs/audio/COMMENTARY.md §7): reads the session logs written by
// tools/audio/commentary_audit.ps1 (game/src/test/audio/commentary_audit.gd) for one or more runs and
// measures what was actually played:
//   pacing      lines per live minute, share of time talking, silences, cut-offs
//   repetition  exact repeats within a bout, in the next two bouts (rematches, the next campaign
//               bout), across the restart between session A and B; joke-family repeats in a row
//   accuracy    situational lines checked against the events that preceded them; result calls
//               (KO / stoppage / decision) checked against what really happened; stale calls
//   spread      distinct lines, the most-played lines, never-played share of the eligible bank
// Usage: node tools/audio/commentary_report.js <run dir> [<run dir> ...] [--md out.md] [--json out.json]
const fs = require('fs');
const path = require('path');
const ROOT = path.resolve(__dirname, '../..');

const args = process.argv.slice(2);
const runs = args.filter((a, i) => !a.startsWith('--') && !(i > 0 && args[i - 1].startsWith('--')));
const mdOut = args.includes('--md') ? args[args.indexOf('--md') + 1] : '';
const jsonOut = args.includes('--json') ? args[args.indexOf('--json') + 1] : '';

// line id -> {situation, families, trigger} from the reviewed classification and current content
const meta = {};
const cls = JSON.parse(fs.readFileSync(path.join(ROOT, 'docs/audio/commentary/classification.json'), 'utf8'));
for (const c of cls) meta[c.id] = { situation: c.situation, families: (c.families || []).map((f) => f.replace(/^other:/, '')) };
for (const f of fs.readdirSync(path.join(ROOT, 'game/content/core/announcer'))) {
  const doc = JSON.parse(fs.readFileSync(path.join(ROOT, 'game/content/core/announcer', f), 'utf8'));
  for (const e of doc.items || []) {
    const m = meta[e.id] || {};
    meta[e.id] = { situation: m.situation || e.situation || e.trigger, families: m.families || e.families || [], trigger: e.trigger };
  }
}

const SITUATIONAL = {
  parry: { types: ['parry'], window: 3 },
  block: { pred: (e) => e.type === 'hit' && e.blocked, window: 2.5 },
  evade: { types: ['dodge'], window: 2.5 },
  knockdown: { types: ['knockdown'], window: 5 },
  getup: { types: ['getup', 'ref_wave_up'], window: 4 },
  counter: { pred: (e) => e.type === 'hit' && e.counter, window: 3 },
  big_hit: { pred: (e) => (e.type === 'hit' && !e.blocked && e.damage >= 10) || e.type === 'slam', window: 3 },
  clean_hit: { pred: (e) => e.type === 'hit' && !e.blocked && e.damage >= 4, window: 2.5 },
  grab_throw: { types: ['throw', 'grab'], window: 3 },
  wall: { types: ['slam'], window: 3 },
  ability: { types: ['ability'], window: 3 },
  juice: { types: ['juice'], window: 4 },
  combo: { combo: true, window: 2.5 },
  exchange: { exchange: true, window: 2.5 },
  pressure: { pressure: true, window: 4 },
  hurt: { hurt: true },
  close: { close: true },
  opening: { opening: true },
  round_break: { types: ['round_end', 'timeout', 'round_scored'], window: 8 },
  result: { types: ['match_end', 'ko', 'ref_stoppage', 'judges_decision'], window: 10 },
};

function load(dir) {
  const sessions = [];
  for (const n of ['A', 'B']) {
    const p = path.join(dir, `session_${n}.json`);
    if (fs.existsSync(p)) sessions.push(Object.assign(JSON.parse(fs.readFileSync(p, 'utf8')), { name: n }));
  }
  return sessions;
}

function evidence(sit, line, events) {
  const rule = SITUATIONAL[sit];
  if (!rule) return null;
  const t = line.t;
  const recent = events.filter((e) => e.t <= t + 0.05 && e.t >= t - (rule.window || 8));
  if (rule.types) return recent.some((e) => rule.types.includes(e.type));
  if (rule.pred) return recent.some(rule.pred);
  const hits = recent.filter((e) => e.type === 'hit' && !e.blocked && e.damage > 0.5);
  if (rule.combo) return Object.values(hits.reduce((a, e) => ((a[e.fighter] = (a[e.fighter] || 0) + 1), a), {})).some((n) => n >= 3);
  if (rule.exchange) return new Set(hits.map((e) => e.fighter)).size >= 2;
  if (rule.pressure) return Object.values(hits.reduce((a, e) => ((a[e.fighter] = (a[e.fighter] || 0) + 1), a), {})).some((n) => n >= 3);
  const last = events.filter((e) => e.t <= t + 0.05 && e.health).slice(-1)[0];
  if (rule.hurt) return !!last && last.health.some((h) => h > 0 && h < 0.35);
  if (rule.close) return !!last && Math.max(...last.health) - Math.min(...last.health) < 0.2;
  if (rule.opening) {
    const rs = events.filter((e) => e.type === 'round_start' && e.t <= t).slice(-1)[0];
    return !!rs && t - rs.t < 30;
  }
  return null;
}

function analyse(label, dir) {
  const sessions = load(dir);
  const out = { label, dir, segments: [], totals: {} };
  const playsById = {};
  const segOrder = [];
  let allLines = [];
  for (const s of sessions) {
    for (const seg of s.segments) {
      const lines = s.lines.filter((l) => l.segment === seg.segment);
      const events = s.events.filter((e) => e.segment === seg.segment);
      const dur = seg.duration || (events.length ? events[events.length - 1].t + 5 : 0) || (lines.length ? lines[lines.length - 1].t + 5 : 0);
      segOrder.push({ key: s.name + ':' + seg.segment, session: s.name, seg, lines, events, dur });
      allLines = allLines.concat(lines.map((l) => Object.assign({ session: s.name, segkey: s.name + ':' + seg.segment }, l)));
    }
  }
  // per segment pacing and accuracy
  let talk = 0, live = 0, cuts = 0, sitTotal = 0, sitOk = 0, stale = 0, lullSit = 0, lullSitOk = 0, lullLines = 0;
  const gaps = [];
  const resultChecks = { ko_said_over_but_round_only: 0, stoppage_called_as_ko: 0, stoppage_called: 0, decision_called: 0, decisions: 0, stoppages: 0, kos: 0 };
  for (const g of segOrder) {
    const { lines, events } = g;
    let segTalk = 0;
    lines.forEach((l) => { segTalk += Math.max(0, (l.end || l.t) - l.t); if (l.cut_by) cuts += 1; });
    talk += segTalk;
    live += g.dur;
    for (let i = 1; i < lines.length; i++) gaps.push(lines[i].t - (lines[i - 1].end || lines[i - 1].t));
    for (const l of lines) {
      const m = meta[l.id] || {};
      const sit = (l.trigger === 'color' || l.trigger === 'conversation_turn' || l.trigger === 'color_conversation_start') ? (m.situation || 'generic') : (SITUATIONAL[l.trigger] ? l.trigger : (SITUATIONAL[m.situation] && l.trigger === m.situation ? m.situation : null));
      const ev = sit ? evidence(sit, l, events) : null;
      if (ev !== null) { sitTotal += 1; if (ev) sitOk += 1; }
      // lines played as lull chatter (colour) that actually claim a situation
      const lull = ['color', 'conversation_turn', 'color_conversation_start', 'fighter_color', 'element_color', 'matchup_color'].includes(l.trigger);
      if (lull) {
        lullLines += 1;
        if (m.situation && !['generic', 'fighter', 'matchup', 'element'].includes(m.situation) && SITUATIONAL[m.situation]) {
          lullSit += 1;
          if (ev) lullSitOk += 1;
        }
      }
      // a knockdown call after the bout was decided is stale
      if ((l.trigger === 'knockdown' || m.situation === 'knockdown') && events.some((e) => (e.type === 'ref_stoppage' || (e.type === 'ko')) && e.t < l.t - 0.3)) {
        const lastEnd = events.filter((e) => ['ref_stoppage', 'match_end'].includes(e.type) && e.t < l.t).length;
        if (lastEnd > 0) stale += 1;
      }
    }
    // result calls
    for (const e of events) {
      const after = lines.filter((l) => l.t >= e.t - 0.05 && l.t <= e.t + 6);
      if (e.type === 'ref_stoppage') {
        resultChecks.stoppages += 1;
        if (after.some((l) => l.trigger === 'stoppage')) resultChecks.stoppage_called += 1;
        if (after.some((l) => l.trigger === 'ko')) resultChecks.stoppage_called_as_ko += 1;
      }
      if (e.type === 'judges_decision' && e.method && e.method !== 'TKO') {
        resultChecks.decisions += 1;
        if (after.some((l) => l.trigger === 'decision' || (l.trigger === 'time' && /cards/i.test(l.text)))) resultChecks.decision_called += 1;
      }
      if (e.type === 'ko') {
        resultChecks.kos += 1;
        const end = events.find((x) => x.type === 'round_end' && Math.abs(x.t - e.t) < 0.2);
        const decided = events.some((x) => x.type === 'match_end' && x.t >= e.t && x.t - e.t < 8);
        if (end && !decided && after.some((l) => l.trigger === 'ko' && /over|goodnight|refunds|the night|the fight/i.test(l.said || l.text))) resultChecks.ko_said_over_but_round_only += 1;
      }
    }
    out.segments.push({ segment: g.key, kind: g.seg.kind, a: g.seg.a, b: g.seg.b, seconds: +g.dur.toFixed(1), lines: lines.length,
      per_min: +(lines.length / Math.max(g.dur / 60, 0.01)).toFixed(2), talk_share: +(segTalk / Math.max(g.dur, 1)).toFixed(3),
      cut_offs: lines.filter((l) => l.cut_by).length });
  }
  // repetition
  const bySeg = {};
  segOrder.forEach((g, i) => { bySeg[g.key] = i; });
  let repWithin = 0, repNext2 = 0, repAcrossRestart = 0, famRun = 0, famPairs = 0;
  const seen = {};
  for (let i = 0; i < allLines.length; i++) {
    const l = allLines[i];
    const si = bySeg[l.segkey];
    const prev = seen[l.id] || [];
    if (prev.some((p) => p.si === si)) repWithin += 1;
    else if (prev.some((p) => si - p.si <= 2 && si - p.si >= 1)) repNext2 += 1;
    if (l.session === 'B' && prev.some((p) => p.session === 'A' && si - p.si <= 3)) repAcrossRestart += 1;
    prev.push({ si, session: l.session });
    seen[l.id] = prev;
    playsById[l.id] = (playsById[l.id] || 0) + 1;
    if (i > 0 && allLines[i - 1].segkey === l.segkey) {
      famPairs += 1;
      const fa = (meta[allLines[i - 1].id] || {}).families || [];
      const fb = (meta[l.id] || {}).families || [];
      if (fa.some((f) => fb.includes(f))) famRun += 1;
    }
  }
  const sortedPlays = Object.entries(playsById).sort((a, b) => b[1] - a[1]);
  gaps.sort((a, b) => a - b);
  const q = (p) => (gaps.length ? +gaps[Math.floor(p * (gaps.length - 1))].toFixed(2) : 0);
  out.totals = {
    bouts: segOrder.filter((g) => g.seg.kind !== 'sequence').length, lines: allLines.length, live_minutes: +(live / 60).toFixed(1),
    lines_per_min: +(allLines.length / Math.max(live / 60, 0.01)).toFixed(2), talk_share: +(talk / Math.max(live, 1)).toFixed(3),
    gap_s: { p10: q(0.1), median: q(0.5), p90: q(0.9), max: q(1) }, cut_offs: cuts,
    distinct_lines: Object.keys(playsById).length,
    repeats_within_bout: repWithin, repeats_in_next_two_bouts: repNext2, repeats_across_restart: repAcrossRestart,
    family_repeat_in_a_row: famRun, consecutive_pairs: famPairs,
    lull_lines: lullLines, lull_lines_claiming_a_situation: lullSit, lull_claims_backed: lullSitOk,
    situational_checked: sitTotal, situational_supported: sitOk, situational_accuracy: sitTotal ? +(sitOk / sitTotal).toFixed(3) : null,
    stale_knockdown_calls: stale, result_calls: resultChecks,
    most_played: sortedPlays.slice(0, 8).map(([id, n]) => ({ id, n, text: ((allLines.find((l) => l.id === id) || {}).said || '').slice(0, 70) })),
  };
  return out;
}

const results = runs.map((r) => analyse(path.basename(r), r));
if (jsonOut) fs.writeFileSync(jsonOut, JSON.stringify(results, null, 1));
let md = '| Metric | ' + results.map((r) => r.label).join(' | ') + ' |\n|---|' + results.map(() => '---:').join('|') + '|\n';
const row = (name, f) => { md += `| ${name} | ${results.map((r) => f(r.totals)).join(' | ')} |\n`; };
row('Bouts (+ scripted sequences)', (t) => t.bouts);
row('Lines played', (t) => t.lines);
row('Lines per live minute', (t) => t.lines_per_min);
row('Share of time talking', (t) => (100 * t.talk_share).toFixed(1) + '%');
row('Silence between lines, median / p90 (s)', (t) => `${t.gap_s.median} / ${t.gap_s.p90}`);
row('Lines cut off by another line', (t) => t.cut_offs);
row('Distinct lines', (t) => t.distinct_lines);
row('Exact repeats within a bout', (t) => t.repeats_within_bout);
row('Exact repeats in the next two bouts', (t) => t.repeats_in_next_two_bouts);
row('Exact repeats across the restart', (t) => t.repeats_across_restart);
row('Same joke family twice in a row', (t) => `${t.family_repeat_in_a_row} / ${t.consecutive_pairs}`);
row('Lull lines that claim a situation (backed by an event)', (t) => `${t.lull_lines_claiming_a_situation} of ${t.lull_lines} (${t.lull_claims_backed} backed)`);
row('Situational lines backed by an event', (t) => `${t.situational_supported} / ${t.situational_checked} (${t.situational_accuracy === null ? '-' : (100 * t.situational_accuracy).toFixed(0) + '%'})`);
row('Stale knockdown calls after the result', (t) => t.stale_knockdown_calls);
row('Stoppages called as stoppages', (t) => `${t.result_calls.stoppage_called} / ${t.result_calls.stoppages}`);
row('Stoppages called as knockouts', (t) => t.result_calls.stoppage_called_as_ko);
row('Decisions announced', (t) => `${t.result_calls.decision_called} / ${t.result_calls.decisions}`);
row('Round-only KOs called as the end of the fight', (t) => t.result_calls.ko_said_over_but_round_only);
for (const r of results) {
  md += `\n**${r.label}: most played** — ` + r.totals.most_played.map((m) => `${m.id} ×${m.n} ("${m.text}")`).join('; ') + '\n';
}
if (mdOut) fs.writeFileSync(mdOut, md);
console.log(md);
