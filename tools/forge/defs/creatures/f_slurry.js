'use strict';
// SLURRY — the Drain Wyrm (ROSTER.md §5). "Question mark": oily moray serpent reared on its rear
// three segments, frilled crest, brass pipe-fitting collars, sludge seeping from the seams.
// Coordinates line up with game/content/core/creatures/f_slurry.json.
const H = require('../../lib/helpers');

const P = {
  primary: '#2A2F2E', sheen: '#3E5A44', secondary: '#C7E66B', belly_dk: '#9FBF52', brass: '#B08A3E', verdigris: '#5E9C7A',
  crest: '#8BD426', crest_dk: '#5FA012', accent: '#E04FB0', pupil: '#1A0A14', fang: '#EDE6D6', sludge: '#8BD426', band: '#E6E2DA',
};

// collar: brass pipe fitting around a body segment with bolt heads
function collar(seg, c, axis, R) {
  const V = require('../../lib/vec');
  const out = [{ type: 'torus', seg, c, axis, R, r: 0.035, color: '$brass', material: 'brass', name: 'collar', blend: 0.01 }];
  const a = V.norm(axis);
  const side = V.norm(V.cross(a, Math.abs(a[1]) < 0.9 ? [0, 1, 0] : [1, 0, 0]));
  const up = V.cross(side, a);
  for (let i = 0; i < 6; i++) {
    const ang = (i / 6) * Math.PI * 2;
    const p = V.add(c, V.add(V.mul(side, Math.cos(ang) * (R + 0.02)), V.mul(up, Math.sin(ang) * (R + 0.02))));
    out.push({ type: 'sphere', seg, c: p, r: 0.016, color: '$verdigris', material: 'brass', name: 'bolt', blend: 0.004, op: 'sharp' });
  }
  return out;
}

module.exports = {
  id: 'f_slurry',
  creature: 'game/content/core/creatures/f_slurry.json',
  out: 'creatures/f_slurry.glb',
  resolution: 0.012,
  target_tris: 13000,
  blend: 0.05,
  palette: P,
  materials: {
    skin: { roughness: 0.3, metallic: 0.05 },      // wet oily skin
    brass: { roughness: 0.4, metallic: 0.75 },
    fin: { roughness: 0.6, metallic: 0 },
    eye: { roughness: 0.2, metallic: 0 },
    glow: { roughness: 0.4, metallic: 0, emissive: '#8BD426' },
    team: { roughness: 0.8, metallic: 0 },
  },
  parts: [
    // ---- body: one tapered tube per segment, overlapping for a continuous hose ----
    { type: 'cone', seg: 'body3', a: [0, 0.24, -0.4], b: [0, 0.3, -0.02], ra: 0.17, rb: 0.18, color: '$primary', name: 'body', blend: 0.06 },
    { type: 'cone', seg: 'body3', a: [0, 0.3, 0.0], b: [0, 0.68, 0.13], ra: 0.18, rb: 0.165, color: '$primary', name: 'body', blend: 0.06 },
    { type: 'cone', seg: 'body2', a: [0, 0.7, 0.14], b: [0, 1.08, 0.16], ra: 0.165, rb: 0.15, color: '$primary', name: 'body', blend: 0.06 },
    { type: 'cone', seg: 'body1', a: [0, 1.06, 0.16], b: [0, 1.4, 0.11], ra: 0.15, rb: 0.13, color: '$primary', name: 'body', blend: 0.06 },
    { type: 'cone', seg: 'body4', a: [0, 0.2, -0.4], b: [0, 0.17, -0.78], ra: 0.17, rb: 0.15, color: '$primary', name: 'body', blend: 0.06 },
    { type: 'cone', seg: 'body5', a: [0, 0.17, -0.78], b: [0, 0.16, -1.16], ra: 0.15, rb: 0.125, color: '$primary', name: 'body', blend: 0.06 },
    { type: 'cone', seg: 'body6', a: [0, 0.16, -1.16], b: [0, 0.14, -1.44], ra: 0.125, rb: 0.07, color: '$primary', name: 'body', blend: 0.06 },
    // spade tail tip
    { type: 'ellipsoid', seg: 'body6', c: [0, 0.14, -1.5], r: [0.12, 0.04, 0.12], color: '$primary', name: 'tail_spade', blend: 0.03 },
    // ---- head: moray head, wide jaw, fangs, magenta eyes ----
    { type: 'sphere', seg: 'head', c: [0, 1.56, 0.2], r: 0.16, color: '$primary', name: 'head', blend: 0.05 },
    { type: 'cone', seg: 'head', a: [0, 1.54, 0.26], b: [0, 1.5, 0.52], ra: 0.13, rb: 0.075, color: '$primary', name: 'head', blend: 0.05 },
    { type: 'cone', seg: 'head', a: [0, 1.44, 0.24], b: [0, 1.41, 0.46], ra: 0.09, rb: 0.055, color: '$primary', name: 'jaw', blend: 0.04 },
    { type: 'box', seg: 'head', c: [0, 1.455, 0.4], size: [0.22, 0.014, 0.24], color: '#120A10', paint: true, name: 'mouth' },
    { type: 'cone', seg: 'head', a: [0.055, 1.48, 0.44], b: [0.05, 1.41, 0.46], ra: 0.016, rb: 0.004, color: '$fang', material: 'eye', name: 'fang', mirror: true, blend: 0.004, op: 'sharp' },
    { type: 'cone', seg: 'head', a: [0.03, 1.47, 0.5], b: [0.028, 1.42, 0.51], ra: 0.011, rb: 0.003, color: '$fang', material: 'eye', name: 'fang', mirror: true, blend: 0.004, op: 'sharp' },
    H.eye({ seg: 'head', c: [0.1, 1.61, 0.29], r: 0.045, dir: [0.5, 0.15, 1], white: '$accent', pupil: '$pupil', pupil_r: 0.016, material: 'eye',
      brow: { a: [0.05, 1.67, 0.3], b: [0.15, 1.63, 0.28], w: 0.03, h: 0.02, color: '$sheen' } }),
    H.eye({ seg: 'head', c: [-0.1, 1.61, 0.29], r: 0.045, dir: [-0.5, 0.15, 1], white: '$accent', pupil: '$pupil', pupil_r: 0.016, material: 'eye',
      brow: { a: [-0.05, 1.67, 0.3], b: [-0.15, 1.63, 0.28], w: 0.03, h: 0.02, color: '$sheen' } }),
    { type: 'sphere', seg: 'head', c: [0.04, 1.54, 0.5], r: 0.012, color: '#141A16', paint: true, name: 'nostril', mirror: true },
    // ---- dorsal crest: membrane fin along the back from the head down to the rise ----
    H.crest({ seg: 'head', a: [0, 1.7, 0.1], b: [0, 1.64, -0.02], count: 3, h0: 0.14, h1: 0.1, up: [0, 1, -0.4], ra: 0.03, rb: 0.008, color: '$crest', material: 'fin', name: 'crest' }),
    H.crest({ seg: 'body1', a: [0, 1.38, -0.04], b: [0, 1.1, 0.0], count: 4, h0: 0.13, h1: 0.11, up: [0, 0.6, -1], ra: 0.03, rb: 0.008, color: '$crest', material: 'fin', name: 'crest' }),
    H.crest({ seg: 'body2', a: [0, 1.06, 0.0], b: [0, 0.74, -0.02], count: 4, h0: 0.1, h1: 0.08, up: [0, 0.5, -1], ra: 0.03, rb: 0.008, color: '$crest', material: 'fin', name: 'crest' }),
    { type: 'box', seg: 'body1', c: [0, 1.25, -0.08], size: [0.012, 0.28, 0.16], round: 0.004, color: '$crest', material: 'fin', name: 'membrane', blend: 0.02 },
    { type: 'box', seg: 'body2', c: [0, 0.9, -0.06], size: [0.012, 0.3, 0.12], round: 0.004, color: '$crest', material: 'fin', name: 'membrane', blend: 0.02 },
    // ---- brass pipe collars on three segments ----
    collar('body2', [0, 0.9, 0.15], [0, 1, 0.05], 0.165),
    collar('body3', [0, 0.46, 0.06], [0, 1, 0.3], 0.185),
    collar('body5', [0, 0.165, -0.98], [0, 0, 1], 0.145),
    // ---- sludge drips at the seams ----
    { type: 'sphere', seg: 'body2', c: [0.1, 0.8, 0.26], r: 0.03, color: '$sludge', material: 'glow', glow: 0.6, name: 'drip', blend: 0.01 },
    { type: 'cone', seg: 'body2', a: [0.1, 0.82, 0.26], b: [0.11, 0.7, 0.27], ra: 0.025, rb: 0.008, color: '$sludge', material: 'glow', glow: 0.6, name: 'drip', blend: 0.01 },
    { type: 'sphere', seg: 'body3', c: [-0.14, 0.4, 0.14], r: 0.035, color: '$sludge', material: 'glow', glow: 0.6, name: 'drip', blend: 0.01 },
    { type: 'cone', seg: 'body3', a: [-0.14, 0.42, 0.14], b: [-0.15, 0.26, 0.16], ra: 0.028, rb: 0.008, color: '$sludge', material: 'glow', glow: 0.6, name: 'drip', blend: 0.01 },
    { type: 'sphere', seg: 'body5', c: [0.12, 0.1, -1.02], r: 0.03, color: '$sludge', material: 'glow', glow: 0.6, name: 'drip', blend: 0.01 },
    { type: 'sphere', seg: 'head', c: [0.12, 1.44, 0.36], r: 0.022, color: '$sludge', material: 'glow', glow: 0.6, name: 'drip', blend: 0.008 },
  ],
  paints: [
    // yellow-green belly: forward on the reared part, downward on the floor part
    { type: 'facing', target: { zones: ['body', 'head', 'jaw'] }, dir: [0, -0.35, 1], start: 0.5, end: 0.92, color: '$secondary', strength: 0.9 },
    { type: 'spots', target: { zones: ['body'] }, cell: 0.14, radius: 0.03, density: 0.35, seed: 21, color: '$belly_dk' },
    { type: 'facing', target: { zones: ['body', 'tail_spade'] }, dir: [0, -1, 0], start: 0.4, end: 0.95, color: '$secondary', strength: 0.9 },
    // oily green sheen along the top
    { type: 'facing', target: { zones: ['body', 'head'] }, dir: [0, 1, 0], start: 0.5, end: 1.0, color: '$sheen', strength: 0.4 },
    // team band: painted ring on the tail base
    { type: 'band', target: { zones: ['body'] }, axis: [0, 0, 1], center: -0.58, width: 0.08, color: '$band', material: 'team' },
  ],
  gore: {
    resolution: 0.003, target_tris: 300,
    parts: [{ type: 'cone', a: [0, 0.03, 0], b: [0, -0.03, 0], ra: 0.014, rb: 0.003, color: '$fang', material: 'eye' }],
  },
};
