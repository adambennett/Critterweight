'use strict';
// Authoring helpers for .js definitions: each returns an array of parts (nestable). JSON
// definitions can express the same things by writing the parts out by hand.

const V = require('./vec');

// Cartoon eye: a white ball pushed into the head, a flat dark pupil disc protruding slightly,
// optional iris ring and brow. `dir` = gaze direction (default forward +Z). All parts are
// sharp unions so the colour edges stay crisp.
function eye(o) {
  const dir = V.norm(o.dir || [0, 0, 1]);
  const r = o.r || 0.05;
  const c = o.c;
  const parts = [];
  const seg = o.seg;
  const lid = o.lid || 0; // 0..1 fraction of the eye covered by an upper lid (sleepy / angry)
  parts.push({ type: 'sphere', seg, c, r, color: o.white || '#F6F3EA', op: 'sharp', name: o.name ? o.name + '_white' : 'eye_white', material: o.material || 'eye', skin_soft: 0.01 });
  const pr = o.pupil_r || r * 0.45;
  const pc = V.add(c, V.mul(dir, r - pr * 0.55));
  if (o.iris) {
    const ir = o.iris_r || r * 0.65;
    parts.push({ type: 'sphere', seg, c: V.add(c, V.mul(dir, r - ir * 0.72)), r: ir, color: o.iris, op: 'sharp', name: 'eye_iris', material: o.material || 'eye', skin_soft: 0.01 });
  }
  parts.push({ type: 'sphere', seg, c: pc, r: pr, color: o.pupil || '#1A1A1F', op: 'sharp', name: 'eye_pupil', material: o.material || 'eye', skin_soft: 0.01 });
  if (o.shine !== false) {
    const up = Math.abs(dir[1]) < 0.9 ? [0, 1, 0] : [1, 0, 0];
    const side = V.norm(V.cross(up, dir));
    const sc = V.add(V.add(pc, V.mul(dir, pr * 0.75)), V.add(V.mul(side, pr * 0.4), V.mul(up, pr * 0.4)));
    parts.push({ type: 'sphere', seg, c: sc, r: pr * 0.28, color: '#FFFFFF', op: 'sharp', name: 'eye_shine', material: o.material || 'eye', skin_soft: 0.01 });
  }
  if (lid > 0) {
    // upper lid: a skin-coloured slab clipping the top of the eye
    const up = o.lid_up || [0, 1, 0];
    const cutc = V.add(c, V.mul(V.norm(up), r * (1 - lid * 1.2)));
    parts.push({ type: 'box', seg, c: V.add(cutc, V.mul(V.norm(up), r)), size: [r * 3, r * 2, r * 3], rot: o.lid_rot || [0, 0, 0], color: o.lid_color, op: 'sharp', name: 'eye_lid', material: o.lid_material || 'skin', blend: 0.004 });
  }
  if (o.brow) {
    const b = o.brow;
    parts.push({ type: 'box', seg, a: b.a, b: b.b, w: b.w || r * 1.2, h: b.h || r * 0.6, round: (b.h || r * 0.6) * 0.45, color: b.color || o.pupil || '#1A1A1F', name: 'brow', material: o.lid_material || 'skin', blend: b.blend == null ? 0.01 : b.blend });
  }
  return parts;
}

// A stack of tori / a textured capsule for bandage wraps or tape along a limb from a to b.
function wrap(o) {
  const parts = [];
  const a = o.a, b = o.b;
  const n = o.turns || 4;
  const dir = V.norm(V.sub(b, a));
  for (let i = 0; i < n; i++) {
    const t = (i + 0.5) / n;
    const c = V.lerp(a, b, t);
    const tilt = o.tilt == null ? 12 : o.tilt;
    parts.push({ type: 'torus', seg: o.seg, c, axis: V.norm(V.add(dir, V.mul(V.cross(dir, [0, 1, 0]), Math.tan((tilt * Math.PI) / 180) * (i % 2 ? 1 : -1)))), R: o.r, r: o.band || o.r * 0.22, color: o.color, material: o.material || 'cloth', blend: 0.006, name: o.name || 'wrap' });
  }
  return parts;
}

// A chain of alternating tori between two points (mooring chain, collar chain).
function chain(o) {
  const parts = [];
  const a = o.a, b = o.b;
  const n = o.links || 6;
  const d = V.sub(b, a);
  const dir = V.norm(d);
  const len = V.len(d);
  const R = o.R || 0.045, r = o.r || 0.012;
  const side = V.norm(V.cross(dir, Math.abs(dir[1]) < 0.9 ? [0, 1, 0] : [1, 0, 0]));
  const up = V.cross(side, dir);
  for (let i = 0; i < n; i++) {
    const c = V.add(a, V.mul(dir, (i + 0.5) * (len / n)));
    parts.push({ type: 'torus', seg: o.seg, c, axis: i % 2 ? side : up, R, r, color: o.color || '#7A7F85', material: o.material || 'metal', op: 'sharp', name: o.name || 'chain', skin_soft: 0.02 });
  }
  return parts;
}

// Sequence of spheres along a path (spikes/bumps/barnacles) with deterministic jitter.
function bumps(o) {
  const parts = [];
  const n = o.count || 5;
  let s = o.seed || 1;
  const rnd = () => { s = (s * 1103515245 + 12345) % 2147483648; return s / 2147483648; };
  for (let i = 0; i < n; i++) {
    const t = n === 1 ? 0.5 : i / (n - 1);
    const c = V.lerp(o.a, o.b, t);
    const j = o.jitter || 0;
    const cj = [c[0] + (rnd() - 0.5) * j, c[1] + (rnd() - 0.5) * j, c[2] + (rnd() - 0.5) * j];
    const r = (o.r || 0.03) * (0.75 + rnd() * 0.5);
    parts.push({ type: 'sphere', seg: o.seg, c: cj, r, color: o.color, material: o.material, blend: o.blend == null ? 0.01 : o.blend, name: o.name || 'bump', op: o.op || 'union' });
  }
  return parts;
}

// Fin/crest: a row of thin rounded boxes fanning along a→b with heights from h0 to h1.
function crest(o) {
  const parts = [];
  const n = o.count || 5;
  for (let i = 0; i < n; i++) {
    const t = n === 1 ? 0.5 : i / (n - 1);
    const base = V.lerp(o.a, o.b, t);
    const h = o.h0 + (o.h1 - o.h0) * t;
    const tip = V.add(base, V.mul(V.norm(o.up || [0, 1, 0]), h));
    parts.push({ type: 'cone', seg: o.seg, a: base, b: tip, ra: o.ra || 0.04, rb: o.rb || 0.012, color: o.color, material: o.material, blend: o.blend == null ? 0.015 : o.blend, name: o.name || 'crest' });
  }
  return parts;
}

// Four-fingered cartoon fist: a big sphere plus knuckle bumps and a thumb.
function fist(o) {
  const c = o.c, r = o.r, fwd = V.norm(o.fwd || [0, 0, 1]), side = V.norm(o.side || [1, 0, 0]);
  const parts = [{ type: 'ellipsoid', seg: o.seg, c, r: [r * 1.05, r * 0.9, r], color: o.color, name: o.name || 'fist', material: o.material, blend: o.blend == null ? 0.02 : o.blend }];
  for (let i = 0; i < 3; i++) {
    const k = V.add(V.add(c, V.mul(fwd, r * 0.78)), V.mul(side, (i - 1) * r * 0.55));
    parts.push({ type: 'sphere', seg: o.seg, c: V.add(k, [0, r * 0.2, 0]), r: r * 0.36, color: o.color, name: o.name || 'fist', material: o.material, blend: 0.025 });
  }
  parts.push({ type: 'capsule', seg: o.seg, a: V.add(c, V.mul(side, -r * 0.6)), b: V.add(V.add(c, V.mul(side, -r * 1.1)), V.mul(fwd, r * 0.3)), r: r * 0.32, color: o.color, name: o.name || 'fist', material: o.material, blend: 0.025 });
  return parts;
}

module.exports = { eye, wrap, chain, bumps, crest, fist };
