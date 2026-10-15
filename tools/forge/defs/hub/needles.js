'use strict';
// NEEDLES — porcupine Juice Bar vendor (HUB.md): lab coat two sizes too big, quills everywhere,
// sweating, sincere. Pose: shoulders up, hands lost in the sleeves, a Glandco can on the belt.
const H = require('../../lib/helpers');
const C = require('./_hub_common');

const P = { fur: '#6B4A2E', quill: '#3A2A1C', quill_tip: '#EDE6D6', coat: '#F2F2EC', coat_sh: '#D8D8D0', nose: '#2A1E16', eye: '#F6F4EE', pupil: '#1C1A1A', glass: '#C9A227', can: '#8BD426', sweat: '#BDEFFF' };

function quills() {
  const out = [];
  const spots = [[0, 1.26, -0.08], [0.08, 1.24, -0.1], [-0.08, 1.24, -0.1], [0.04, 1.2, -0.16], [-0.04, 1.2, -0.16], [0.12, 1.16, -0.12], [-0.12, 1.16, -0.12],
    [0, 1.3, 0.0], [0.07, 1.29, 0.02], [-0.07, 1.29, 0.02], [0.1, 1.02, -0.26], [-0.1, 1.02, -0.26], [0, 1.0, -0.28], [0.16, 0.9, -0.24], [-0.16, 0.9, -0.24], [0, 0.86, -0.3]];
  spots.forEach((s, i) => {
    const dir = [s[0] * 0.8, 0.5 + (i % 3) * 0.2, s[2] < -0.1 ? -1 : -0.3];
    const l = Math.hypot(dir[0], dir[1], dir[2]);
    const tip = [s[0] + (dir[0] / l) * 0.16, s[1] + (dir[1] / l) * 0.16, s[2] + (dir[2] / l) * 0.16];
    out.push({ type: 'cone', a: s, b: tip, ra: 0.016, rb: 0.003, color: '$quill', name: 'quill', blend: 0.008 });
    out.push({ type: 'sphere', c: tip, r: 0.006, color: '$quill_tip', name: 'quill_tip', op: 'sharp', blend: 0 });
  });
  return out;
}

module.exports = {
  id: 'hub_needles',
  out: 'hub/needles.glb',
  resolution: 0.009,
  target_tris: 8000,
  blend: 0.035,
  palette: P,
  default_color: '$fur',
  materials: C.materials({ can: { roughness: 0.35, metallic: 0.5 } }),
  parts: [
    // oversized lab coat: a long tapered coat body down to the shins
    { type: 'cone', a: [0, 1.0, 0], b: [0, 0.3, 0.02], ra: 0.22, rb: 0.3, color: '$coat', material: 'cloth', name: 'coat', blend: 0.04 },
    { type: 'capsule', a: [-0.2, 1.0, 0], b: [0.2, 1.0, 0], r: 0.14, color: '$coat', material: 'cloth', name: 'coat', blend: 0.04 },
    { type: 'box', c: [0, 0.75, 0.27], size: [0.012, 0.6, 0.06], color: '$coat_sh', paint: true, name: 'placket' },
    { type: 'box', c: [0.1, 0.52, 0.27], size: [0.12, 0.1, 0.04], round: 0.01, color: '$coat_sh', material: 'cloth', name: 'pocket', mirror: true, blend: 0.004, op: 'sharp' },
    // sleeves past the hands (hands hidden), shoulders up
    { type: 'cone', a: [0.24, 1.02, 0.02], b: [0.3, 0.6, 0.14], ra: 0.085, rb: 0.1, color: '$coat', material: 'cloth', name: 'sleeve', mirror: true, blend: 0.03 },
    { type: 'sphere', c: [0.3, 0.57, 0.15], r: 0.1, color: '$coat', material: 'cloth', name: 'sleeve', mirror: true, blend: 0.02 },
    { type: 'sphere', c: [0.3, 0.52, 0.19], r: 0.045, color: '$fur', material: 'fur', name: 'fingers', mirror: true, blend: 0.015 },
    // legs under the coat
    C.legs({ x: 0.09, hip: 0.35, r: 0.06, color: '$fur', material: 'fur', foot: '$quill' }),
    // head: rounded porcupine face with a dark nose, nervous eyes behind round glasses
    { type: 'sphere', c: [0, 1.17, 0.06], r: 0.14, color: '$fur', material: 'fur', name: 'head', blend: 0.04 },
    { type: 'cone', a: [0, 1.12, 0.12], b: [0, 1.08, 0.3], ra: 0.09, rb: 0.035, color: '$fur', material: 'fur', name: 'snout', blend: 0.03 },
    { type: 'sphere', c: [0, 1.085, 0.31], r: 0.028, color: '$nose', name: 'nose', op: 'sharp', blend: 0.004 },
    H.eye({ c: [0.055, 1.19, 0.17], r: 0.032, dir: [0.25, 0, 1], white: '$eye', pupil: '$pupil', pupil_r: 0.014, material: 'eye', brow: { a: [0.02, 1.24, 0.18], b: [0.09, 1.23, 0.16], w: 0.02, h: 0.012, color: '$quill' } }),
    H.eye({ c: [-0.055, 1.19, 0.17], r: 0.032, dir: [-0.25, 0, 1], white: '$eye', pupil: '$pupil', pupil_r: 0.014, material: 'eye', brow: { a: [-0.02, 1.24, 0.18], b: [-0.09, 1.23, 0.16], w: 0.02, h: 0.012, color: '$quill' } }),
    { type: 'torus', c: [0.055, 1.19, 0.195], axis: [0.25, 0, 1], R: 0.04, r: 0.006, color: '$glass', material: 'gold', name: 'glasses', op: 'sharp', blend: 0, mirror: true },
    { type: 'capsule', a: [-0.02, 1.19, 0.2], b: [0.02, 1.19, 0.2], r: 0.005, color: '$glass', material: 'gold', name: 'glasses', op: 'sharp', blend: 0 },
    { type: 'box', c: [0, 1.05, 0.25], size: [0.07, 0.008, 0.06], color: '#2A1E16', paint: true, name: 'mouth' },
    // sweat drops
    { type: 'sphere', c: [0.1, 1.27, 0.1], r: 0.012, color: '$sweat', material: 'eye', name: 'sweat', op: 'sharp', blend: 0 },
    { type: 'sphere', c: [-0.11, 1.22, 0.12], r: 0.01, color: '$sweat', material: 'eye', name: 'sweat', op: 'sharp', blend: 0 },
    quills(),
    // a Glandco can clipped to the belt
    { type: 'cylinder', a: [0.2, 0.62, 0.18], b: [0.2, 0.74, 0.18], r: 0.035, round: 0.006, color: '$can', material: 'can', name: 'can', op: 'sharp', blend: 0 },
  ],
  paints: [
    { type: 'facing', target: { zones: ['coat', 'sleeve'] }, dir: [0, -1, 0], start: 0.3, end: 0.9, color: '$coat_sh', strength: 0.6 },
  ],
};
