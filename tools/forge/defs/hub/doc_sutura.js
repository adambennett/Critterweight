'use strict';
// DOC SUTURA — octopus veterinarian (HUB.md): eight hands, one cigarette she never lights,
// brisk and unimpressed. Pose: mantle upright on a skirt of tentacles, two arms holding
// suture tools, reading glasses, a surgical cap.
const H = require('../../lib/helpers');
const C = require('./_hub_common');

const P = { skin: '#8A5C8E', skin_lt: '#B98BB5', sucker: '#E8C8E0', cap: '#F2F2EC', cross: '#8BD426', eye: '#F6F4EE', pupil: '#2A1A2E', cig: '#EDE6D6', cig_tip: '#C47A3A', steel: '#9FA6AD', bag: '#4A3F33' };

function tentacle(angle, len, lift, curl) {
  const out = [];
  const ca = Math.cos(angle), sa = Math.sin(angle);
  let p = [ca * 0.16, 0.55, sa * 0.16];
  let r = 0.065;
  const n = 5;
  for (let i = 0; i < n; i++) {
    const t = i / (n - 1);
    const q = [ca * (0.16 + len * (t + 0.2)), Math.max(0.045, 0.55 - 0.5 * Math.pow(t, 0.8) + lift * Math.sin(t * Math.PI) ), sa * (0.16 + len * (t + 0.2)) + curl * t * t];
    out.push({ type: 'cone', a: p, b: q, ra: r, rb: r * 0.72, color: '$skin', name: 'tentacle', blend: 0.03 });
    p = q; r *= 0.72;
  }
  out.push({ type: 'sphere', c: p, r: r * 1.1, color: '$skin', name: 'tentacle', blend: 0.02 });
  return out;
}

module.exports = {
  id: 'hub_doc_sutura',
  out: 'hub/doc_sutura.glb',
  resolution: 0.009,
  target_tris: 9000,
  blend: 0.035,
  palette: P,
  default_color: '$skin',
  materials: C.materials({ skin: { roughness: 0.45, metallic: 0 } }),
  parts: [
    // mantle (head-body) with a rounded top, slight forward lean
    { type: 'ellipsoid', c: [0, 0.98, 0], r: [0.24, 0.36, 0.22], color: '$skin', name: 'mantle', blend: 0.05 },
    { type: 'ellipsoid', c: [0, 0.68, 0.02], r: [0.26, 0.2, 0.24], color: '$skin', name: 'mantle', blend: 0.06 },
    // eight tentacles: six as a skirt, two raised holding tools
    tentacle(0.4, 0.3, 0.0, 0.0), tentacle(1.2, 0.34, 0.0, 0.02), tentacle(2.0, 0.3, 0.0, 0.0), tentacle(2.8, 0.32, 0.0, -0.02),
    tentacle(3.6, 0.3, 0.0, 0.0), tentacle(4.4, 0.34, 0.0, 0.0), tentacle(5.2, 0.3, 0.0, 0.02),
    tentacle(-0.3, 0.26, 0.5, 0.0),
    // suckers on the front tentacles (paint)
    { type: 'sphere', c: [0.2, 0.26, 0.26], r: 0.02, color: '$sucker', paint: true, name: 'sucker' },
    { type: 'sphere', c: [0.26, 0.18, 0.32], r: 0.018, color: '$sucker', paint: true, name: 'sucker' },
    { type: 'sphere', c: [-0.22, 0.24, 0.24], r: 0.02, color: '$sucker', paint: true, name: 'sucker' },
    { type: 'sphere', c: [-0.3, 0.16, 0.3], r: 0.018, color: '$sucker', paint: true, name: 'sucker' },
    // tools: a needle holder and a suture needle in the raised tentacle, a doctor's bag beside her
    { type: 'cylinder', a: [0.36, 0.78, 0.24], b: [0.36, 0.98, 0.3], r: 0.012, round: 0.003, color: '$steel', material: 'metal', name: 'tool', op: 'sharp', blend: 0 },
    { type: 'torus', c: [0.36, 1.0, 0.31], axis: [1, 0, 0], R: 0.03, r: 0.006, color: '$steel', material: 'metal', name: 'tool', op: 'sharp', blend: 0 },
    { type: 'box', c: [-0.46, 0.14, 0.1], size: [0.26, 0.22, 0.16], round: 0.03, color: '$bag', material: 'cloth', name: 'bag', blend: 0.01 },
    { type: 'torus', c: [-0.46, 0.26, 0.1], axis: [1, 0, 0], R: 0.05, r: 0.012, color: '$bag', material: 'cloth', name: 'bag', blend: 0.006 },
    // face: big tired eyes, glasses, the unlit cigarette
    H.eye({ c: [0.09, 1.04, 0.2], r: 0.05, dir: [0.25, 0, 1], white: '$eye', pupil: '$pupil', pupil_r: 0.022, material: 'eye', lid: 0.4, lid_color: '$skin' }),
    H.eye({ c: [-0.09, 1.04, 0.2], r: 0.05, dir: [-0.25, 0, 1], white: '$eye', pupil: '$pupil', pupil_r: 0.022, material: 'eye', lid: 0.4, lid_color: '$skin' }),
    { type: 'torus', c: [0.09, 1.03, 0.245], axis: [0.25, 0, 1], R: 0.055, r: 0.006, color: '$steel', material: 'metal', name: 'glasses', op: 'sharp', blend: 0, mirror: true },
    { type: 'capsule', a: [-0.035, 1.04, 0.25], b: [0.035, 1.04, 0.25], r: 0.005, color: '$steel', material: 'metal', name: 'glasses', op: 'sharp', blend: 0 },
    { type: 'box', c: [0.02, 0.9, 0.22], size: [0.1, 0.01, 0.06], rot: [0, 0, -6], color: '#3A2238', paint: true, name: 'mouth' },
    { type: 'cylinder', a: [0.05, 0.9, 0.24], b: [0.1, 0.92, 0.34], r: 0.008, round: 0.002, color: '$cig', name: 'cigarette', op: 'sharp', blend: 0 },
    { type: 'sphere', c: [0.1, 0.92, 0.34], r: 0.009, color: '$cig_tip', name: 'cig_tip', op: 'sharp', blend: 0 },
    // surgical cap with a green cross
    { type: 'ellipsoid', c: [0, 1.3, -0.02], r: [0.22, 0.1, 0.2], color: '$cap', material: 'cloth', name: 'cap', blend: 0.02 },
    { type: 'torus', c: [0, 1.24, -0.02], axis: [0, 1, 0.1], R: 0.21, r: 0.02, color: '$cap', material: 'cloth', name: 'cap', blend: 0.01 },
    { type: 'box', c: [0, 1.32, 0.15], size: [0.06, 0.012, 0.02], color: '$cross', paint: true, name: 'cross' },
    { type: 'box', c: [0, 1.32, 0.15], size: [0.02, 0.012, 0.06], color: '$cross', paint: true, name: 'cross' },
  ],
  paints: [
    { type: 'facing', target: { zones: ['mantle', 'tentacle'] }, dir: [0, -0.4, 1], start: 0.4, end: 0.95, color: '$skin_lt', strength: 0.7 },
    { type: 'spots', target: { zones: ['mantle'] }, cell: 0.09, radius: 0.018, density: 0.5, seed: 9, color: '$skin_lt' },
  ],
};
