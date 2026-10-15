'use strict';
// COMMISSIONER SNAPPINGTON at her desk (HUB.md): the Office NPC. Reuses the boss art (at 0.75
// scale, so she fits the mezzanine) parked behind a desk with the ledger, a nameplate and the
// gavel. Static model: all parts bind to one root bone.
const boss = require('../creatures/boss_snappington.js');

const S = 0.75;
const scaleParts = (parts) => parts.map((p) => {
  if (Array.isArray(p)) return scaleParts(p);
  const q = Object.assign({}, p);
  delete q.seg;
  for (const k of ['c', 'a', 'b', 'p']) if (q[k]) q[k] = q[k].map((x) => x * S);
  for (const k of ['r', 'ra', 'rb', 'R', 'round', 'w', 'h', 'blend']) if (typeof q[k] === 'number') q[k] *= S;
  if (Array.isArray(q.r)) q.r = q.r.map((x) => x * S);
  if (q.size) q.size = q.size.map((x) => x * S);
  if (q.clip) q.clip = q.clip.map((h) => ({ p: h.p.map((x) => x * S), n: h.n }));
  if (q.extent) q.extent *= S;
  return q;
});

const P = Object.assign({}, boss.palette, { desk: '#5A3B22', desk_top: '#7A5230', paper: '#EDE6D6', brass: '#C9A227' });

module.exports = {
  id: 'hub_snappington_desk',
  out: 'hub/snappington_desk.glb',
  resolution: 0.012,
  target_tris: 12000,
  blend: 0.03,
  palette: P,
  materials: Object.assign({ cloth: { roughness: 0.92, metallic: 0 } }, boss.materials),
  parts: [
    // the Commissioner, shifted back so the desk sits in front of her
    scaleParts(boss.parts).map((p) => shift(p, [0, 0, -0.9])),
    // the desk: top, two pedestals, a ledger, a nameplate, a lamp
    { type: 'box', c: [0, 0.74, 0.55], size: [1.6, 0.06, 0.7], round: 0.015, color: '$desk_top', material: 'wood', name: 'desk', op: 'sharp', blend: 0 },
    { type: 'box', c: [0.6, 0.36, 0.55], size: [0.36, 0.72, 0.66], round: 0.015, color: '$desk', material: 'wood', name: 'desk', op: 'sharp', blend: 0, mirror: true },
    { type: 'box', c: [0.1, 0.785, 0.5], size: [0.34, 0.03, 0.44], round: 0.006, rot: [0, 12, 0], color: '$paper', material: 'cloth', name: 'ledger', op: 'sharp', blend: 0 },
    { type: 'box', c: [-0.45, 0.8, 0.82], size: [0.3, 0.07, 0.03], round: 0.008, rot: [-15, 0, 0], color: '$brass', material: 'gold', name: 'nameplate', op: 'sharp', blend: 0 },
    { type: 'cylinder', a: [0.6, 0.77, 0.35], b: [0.6, 1.1, 0.3], r: 0.015, round: 0.004, color: '$brass', material: 'gold', name: 'lamp', op: 'sharp', blend: 0 },
    { type: 'cone', a: [0.6, 1.14, 0.3], b: [0.6, 1.02, 0.3], ra: 0.03, rb: 0.11, color: '#2E6B3F', material: 'metal', name: 'lamp_shade', blend: 0.006 },
  ],
  paints: boss.paints,
};

function shift(p, d) {
  if (Array.isArray(p)) return p.map((q) => shift(q, d));
  const q = Object.assign({}, p);
  for (const k of ['c', 'a', 'b', 'p']) if (q[k]) q[k] = [q[k][0] + d[0], q[k][1] + d[1], q[k][2] + d[2]];
  if (q.clip) q.clip = q.clip.map((h) => ({ p: [h.p[0] + d[0], h.p[1] + d[1], h.p[2] + d[2]], n: h.n }));
  return q;
}
