#!/usr/bin/env node
'use strict';
// Prints the geometry facts docs/CREATURES.md records for every creature file:
// segment count / total mass / height, chains with bone lengths and their IK reach from the
// root (shoulder offset + len1 + len2), and every weapon's rest distance from the root pivot
// plus its maximum reachable distance (ROSTER.md reach cap: 1.6 m).
//   node tools/forge/measure.js [--md]            (all core creatures, minions and bosses)
const fs = require('fs');
const path = require('path');

const repo = path.resolve(__dirname, '..', '..');
const dirs = ['game/content/core/creatures', 'game/content/core/minions', 'game/content/core/bosses'];
const md = process.argv.includes('--md');
const v = (a) => [a[0] || 0, a[1] || 0, a[2] || 0];
const dist = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);
const distXZ = (a, b) => Math.hypot(a[0] - b[0], a[2] - b[2]);

function measure(file) {
  const c = JSON.parse(fs.readFileSync(file, 'utf8'));
  const b = c.body;
  if (!b || b.id === 'dev_biped_body') return null;
  const s = b.scale || 1;
  const segs = b.segments.map((x) => Object.assign({}, x, { pivot: v(x.pivot).map((k) => k * s) }));
  const byId = Object.fromEntries(segs.map((x) => [x.id, x]));
  const root = segs[0];
  const mass = segs.reduce((a, x) => a + x.mass, 0);
  let top = 0;
  for (const x of segs) for (const sh of x.shapes || []) {
    const ys = sh.type === 'capsule' ? [sh.a[1], sh.b[1]] : sh.type === 'sphere' ? [sh.center[1]] : [sh.center[1] + sh.size[1] / 2];
    for (const y of ys) top = Math.max(top, y * s + (sh.radius || 0) * s);
  }
  const chains = Object.entries(b.chains || {}).map(([name, ch]) => {
    const s0 = byId[ch.segments[0]], s1 = byId[ch.segments[1]];
    const eff = v(ch.effector).map((k) => k * s);
    const l1 = dist(s0.pivot, s1.pivot), l2 = dist(s1.pivot, eff);
    const shoulderXZ = distXZ(s0.pivot, root.pivot);
    return { name, segs: ch.segments.join('+'), l1, l2, leg: !!ch.leg, restReach: distXZ(eff, root.pivot), maxReach: shoulderXZ + l1 + l2 };
  });
  const chainOf = (segId) => chains.find((ch) => ch.segs.split('+').includes(segId));
  const weapons = Object.entries(b.weapons || {}).map(([name, w]) => {
    const seg = byId[w.segment];
    const p = v(w.point).map((k) => k * s);
    const r = (w.radius || 0.1) * s;
    const rest = distXZ(p, root.pivot);
    const ch = chainOf(w.segment);
    let max;
    if (ch) {
      // weapon offset beyond the chain effector adds to the reach
      const s1 = byId[ch.segs.split('+')[1]];
      const l2w = dist(s1.pivot, p);
      const s0 = byId[ch.segs.split('+')[0]];
      max = distXZ(s0.pivot, root.pivot) + ch.l1 + Math.max(ch.l2, l2w) + r;
    } else {
      // joint-driven part: pivot chain from the root sums its link lengths (upper bound)
      let total = 0, cur = seg;
      while (cur && cur.parent) { const par = byId[cur.parent]; total += dist(cur.pivot, par.pivot); cur = par; }
      max = total + dist(seg.pivot, p) + r;
    }
    return { name, seg: w.segment, rest, radius: r, max };
  });
  return { id: c.id, name: c.name, gait: b.gait, hover: (b.hover_height || 1) * s, segs: segs.length, mass, height: top, chains, weapons, stats: c.stats || {},
    segments: segs.map((x) => ({ id: x.id, parent: x.parent || '-', part: x.part || 'core', mass: x.mass, hurt: x.hurt == null ? 1 : x.hurt, w0: x.w0 == null ? 30 : x.w0, guard: !!x.guard })) };
}

const out = [];
for (const d of dirs) {
  const full = path.join(repo, d);
  if (!fs.existsSync(full)) continue;
  for (const f of fs.readdirSync(full).filter((x) => x.endsWith('.json')).sort()) {
    const m = measure(path.join(full, f));
    if (m) out.push(m);
  }
}
const f2 = (x) => x.toFixed(2);
for (const m of out) {
  if (md) {
    console.log(`### ${m.name} (\`${m.id}\`) — ${m.gait}, ${m.segs} segments, ${m.mass} kg, top ${f2(m.height)} m, hover ${f2(m.hover)} m\n`);
    console.log('| Segment | Parent | Part | Mass | Hurt | w0 | Guard |\n|---|---|---|---|---|---|---|');
    for (const s of m.segments) console.log(`| \`${s.id}\` | ${s.parent} | ${s.part} | ${s.mass} | ${s.hurt} | ${s.w0} | ${s.guard ? 'yes' : ''} |`);
    if (m.chains.length) {
      console.log('\n| Chain | Segments | Bone 1 | Bone 2 | Leg | Effector from root (rest) | Max IK reach |\n|---|---|---|---|---|---|---|');
      for (const ch of m.chains) console.log(`| \`${ch.name}\` | ${ch.segs} | ${f2(ch.l1)} m | ${f2(ch.l2)} m | ${ch.leg ? 'yes' : ''} | ${f2(ch.restReach)} m | ${f2(ch.maxReach)} m |`);
    }
    console.log('\n| Weapon | Segment | Radius | Rest distance from root | Max distance from root |\n|---|---|---|---|---|');
    for (const w of m.weapons) console.log(`| \`${w.name}\` | ${w.seg} | ${f2(w.radius)} m | ${f2(w.rest)} m | ${f2(w.max)} m${w.max > 1.6 && !m.id.startsWith('boss_') ? ' (!)' : ''} |`);
    console.log('');
  } else {
    console.log(`${m.id}: ${m.gait} segs=${m.segs} mass=${m.mass} top=${f2(m.height)} hover=${f2(m.hover)}`);
    for (const ch of m.chains) console.log(`  chain ${ch.name} ${ch.segs} l1=${f2(ch.l1)} l2=${f2(ch.l2)} rest=${f2(ch.restReach)} max=${f2(ch.maxReach)}${ch.leg ? ' leg' : ''}`);
    for (const w of m.weapons) console.log(`  weapon ${w.name} (${w.seg}) r=${f2(w.radius)} rest=${f2(w.rest)} max=${f2(w.max)}${w.max > 1.6 && !m.id.startsWith('boss_') ? ' OVER-CAP' : ''}`);
  }
}
