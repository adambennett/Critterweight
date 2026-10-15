'use strict';
// CROWD FAN B — tall, thin bleacher critter with ears and a can of JUICE, ~500 tris.
const P = { body: '#4F6B6E', belly: '#8FA9A8', can: '#8BD426', eye: '#F6F4EE', pupil: '#1C1A1A', ear: '#D98CA0' };

module.exports = {
  id: 'crowd_fan_b',
  out: 'crowd/fan_b.glb',
  resolution: 0.014,
  target_tris: 520,
  blend: 0.04,
  palette: P,
  default_color: '$body',
  materials: { skin: { roughness: 0.85, metallic: 0 }, eye: { roughness: 0.3, metallic: 0 }, can: { roughness: 0.35, metallic: 0.5 } },
  parts: [
    { type: 'capsule', a: [0, 0.35, 0], b: [0, 0.95, 0], r: 0.2, color: '$body', name: 'body', blend: 0.05 },
    { type: 'ellipsoid', c: [0, 1.25, 0.02], r: [0.2, 0.24, 0.2], color: '$body', name: 'head', blend: 0.05 },
    { type: 'cone', a: [0.12, 1.42, 0], b: [0.22, 1.7, -0.04], ra: 0.06, rb: 0.02, color: '$body', name: 'ear', mirror: true, blend: 0.03 },
    { type: 'cone', a: [0.13, 1.45, 0.01], b: [0.2, 1.62, -0.02], ra: 0.03, rb: 0.01, color: '$ear', paint: true, name: 'ear_in', mirror: true },
    { type: 'cone', a: [0.2, 0.9, 0], b: [0.3, 0.6, 0.18], ra: 0.06, rb: 0.05, color: '$body', name: 'arm', blend: 0.04 },
    { type: 'cone', a: [-0.2, 0.9, 0], b: [-0.3, 1.2, 0.16], ra: 0.06, rb: 0.05, color: '$body', name: 'arm', blend: 0.04 },
    { type: 'cylinder', a: [-0.32, 1.18, 0.2], b: [-0.32, 1.34, 0.2], r: 0.045, round: 0.006, color: '$can', material: 'can', name: 'can', op: 'sharp', blend: 0 },
    { type: 'sphere', c: [0.07, 1.3, 0.18], r: 0.035, color: '$eye', material: 'eye', name: 'eye', op: 'sharp', blend: 0, mirror: true },
    { type: 'sphere', c: [0.075, 1.31, 0.21], r: 0.016, color: '$pupil', material: 'eye', name: 'pupil', op: 'sharp', blend: 0, mirror: true },
    { type: 'box', c: [0, 1.18, 0.2], size: [0.1, 0.02, 0.04], color: '$pupil', paint: true, name: 'mouth' },
  ],
  paints: [{ type: 'facing', target: { zones: ['body', 'head'] }, dir: [0, -0.3, 1], start: 0.4, end: 0.95, color: '$belly', strength: 0.7 }],
};
