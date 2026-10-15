'use strict';
// KID LAMPREY — lamprey in a hoodie (HUB.md): hood always up, mouthful of teeth, cocky and
// insecure. Pose: leaning back on the lockers, hands in the hoodie pocket, tail curled.
const C = require('./_hub_common');

const P = { hoodie: '#3F4A5C', hoodie_dk: '#2C3340', string: '#EDE6D6', skin: '#6E8B8E', skin_lt: '#A9C4C2', mouth: '#4A1A2A', teeth: '#F2EFE4', eye: '#F6F4EE', pupil: '#101418', sneaker: '#F2F2EC', sole: '#C23A2B' };

function teethRing(c, R, n, len, inward) {
  const out = [];
  for (let i = 0; i < n; i++) {
    const a = (i / n) * Math.PI * 2;
    const base = [c[0] + Math.cos(a) * R, c[1] + Math.sin(a) * R, c[2]];
    const tip = [c[0] + Math.cos(a) * (R - inward), c[1] + Math.sin(a) * (R - inward), c[2] + len];
    out.push({ type: 'cone', a: base, b: tip, ra: 0.012, rb: 0.003, color: '$teeth', material: 'eye', name: 'tooth', op: 'sharp', blend: 0 });
  }
  return out;
}

module.exports = {
  id: 'hub_kid_lamprey',
  out: 'hub/kid_lamprey.glb',
  resolution: 0.009,
  target_tris: 8000,
  blend: 0.035,
  palette: P,
  default_color: '$skin',
  materials: C.materials({ skin: { roughness: 0.4, metallic: 0 } }),
  parts: [
    // eel body standing upright: tail curls on the floor behind, body rises into the hoodie
    { type: 'cone', a: [0, 0.08, -0.45], b: [0, 0.12, -0.1], ra: 0.04, rb: 0.09, color: '$skin', name: 'tail', blend: 0.05 },
    { type: 'cone', a: [0, 0.12, -0.1], b: [0, 0.5, 0.0], ra: 0.09, rb: 0.12, color: '$skin', name: 'body', blend: 0.05 },
    { type: 'box', a: [0, 0.06, -0.52], b: [0, 0.1, -0.2], w: 0.02, h: 0.12, round: 0.006, color: '$skin_lt', name: 'fin', blend: 0.02 },
    // hoodie: a soft torso tube, kangaroo pocket, hood up around the head
    { type: 'cone', a: [0, 0.48, 0.0], b: [0, 1.1, 0.02], ra: 0.17, rb: 0.16, color: '$hoodie', material: 'cloth', name: 'hoodie', blend: 0.04 },
    { type: 'capsule', a: [-0.18, 1.06, 0], b: [0.18, 1.06, 0], r: 0.1, color: '$hoodie', material: 'cloth', name: 'hoodie', blend: 0.04 },
    { type: 'box', c: [0, 0.72, 0.15], size: [0.26, 0.14, 0.06], round: 0.02, color: '$hoodie_dk', material: 'cloth', name: 'pocket', blend: 0.01 },
    { type: 'cone', a: [0.2, 1.05, 0.02], b: [0.2, 0.78, 0.12], ra: 0.065, rb: 0.06, color: '$hoodie', material: 'cloth', name: 'sleeve', mirror: true, blend: 0.03 },
    { type: 'sphere', c: [0.2, 1.35, -0.02], r: 0.2, color: '$hoodie', material: 'cloth', name: 'hood', blend: 0.04 },
    { type: 'sphere', c: [-0.2, 1.35, -0.02], r: 0.2, color: '$hoodie', material: 'cloth', name: 'hood', blend: 0.04 },
    { type: 'ellipsoid', c: [0, 1.4, -0.06], r: [0.26, 0.26, 0.24], color: '$hoodie', material: 'cloth', name: 'hood', blend: 0.04 },
    { type: 'ellipsoid', c: [0, 1.36, 0.1], r: [0.14, 0.16, 0.18], op: 'subtract', blend: 0.015, name: 'hood_hole' },
    { type: 'capsule', a: [0.07, 1.14, 0.17], b: [0.09, 0.9, 0.19], r: 0.008, color: '$string', material: 'cloth', name: 'string', mirror: true, blend: 0.004 },
    // the lamprey face inside the hood: round sucker mouth with rings of teeth, tiny eyes
    { type: 'sphere', c: [0, 1.36, 0.06], r: 0.15, color: '$skin', name: 'head', blend: 0.03 },
    { type: 'cylinder', a: [0, 1.32, 0.16], b: [0, 1.32, 0.22], r: 0.1, round: 0.02, color: '$skin_lt', name: 'lips', blend: 0.015 },
    { type: 'cylinder', a: [0, 1.32, 0.19], b: [0, 1.32, 0.25], r: 0.07, op: 'subtract', blend: 0.01, name: 'mouth_hole' },
    { type: 'sphere', c: [0, 1.32, 0.17], r: 0.065, color: '$mouth', paint: true, name: 'mouth' },
    teethRing([0, 1.32, 0.2], 0.08, 10, 0.03, 0.03),
    teethRing([0, 1.32, 0.19], 0.05, 7, 0.025, 0.02),
    { type: 'sphere', c: [0.09, 1.44, 0.14], r: 0.02, color: '$eye', material: 'eye', name: 'eye', op: 'sharp', blend: 0, mirror: true },
    { type: 'sphere', c: [0.095, 1.44, 0.158], r: 0.009, color: '$pupil', material: 'eye', name: 'pupil', op: 'sharp', blend: 0, mirror: true },
    // sneakers (he has no legs; the sneakers are just there, on the tail, unexplained)
    { type: 'ellipsoid', c: [0.1, 0.05, 0.08], r: [0.06, 0.05, 0.13], color: '$sneaker', material: 'cloth', name: 'sneaker', mirror: true, blend: 0.015 },
    { type: 'box', c: [0.1, 0.02, 0.08], size: [0.12, 0.02, 0.26], round: 0.008, color: '$sole', material: 'cloth', name: 'sole', mirror: true, blend: 0.004, op: 'sharp' },
  ],
  paints: [
    { type: 'facing', target: { zones: ['body', 'tail', 'head'] }, dir: [0, -0.3, 1], start: 0.4, end: 0.95, color: '$skin_lt', strength: 0.7 },
    { type: 'facing', target: { zones: ['hoodie', 'hood', 'sleeve'] }, dir: [0, -1, 0], start: 0.3, end: 0.9, color: '$hoodie_dk', strength: 0.5 },
  ],
};
