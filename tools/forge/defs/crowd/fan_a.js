'use strict';
// CROWD FAN A — low-poly bleacher critter with a foam finger (ART_DIRECTION §2 crowd budget).
// Round-bodied generic "cannery regular", arms up. Vertex colours only, ~500 tris.
const P = { body: '#6E6A7A', belly: '#9A95A8', foam: '#FFD23F', eye: '#F6F4EE', pupil: '#1C1A1A', cap: '#C23A2B' };

module.exports = {
  id: 'crowd_fan_a',
  out: 'crowd/fan_a.glb',
  resolution: 0.014,
  target_tris: 520,
  blend: 0.04,
  palette: P,
  default_color: '$body',
  materials: { skin: { roughness: 0.85, metallic: 0 }, eye: { roughness: 0.3, metallic: 0 } },
  parts: [
    { type: 'ellipsoid', c: [0, 0.55, 0], r: [0.3, 0.42, 0.26], color: '$body', name: 'body', blend: 0.05 },
    { type: 'sphere', c: [0, 1.05, 0.02], r: 0.22, color: '$body', name: 'head', blend: 0.05 },
    { type: 'cone', a: [0.28, 0.8, 0], b: [0.46, 1.3, 0.05], ra: 0.07, rb: 0.055, color: '$body', name: 'arm', mirror: true, blend: 0.04 },
    { type: 'box', c: [0.5, 1.5, 0.05], size: [0.16, 0.32, 0.08], round: 0.03, color: '$foam', name: 'foam', blend: 0.01 },
    { type: 'sphere', c: [-0.48, 1.36, 0.06], r: 0.08, color: '$body', name: 'hand', blend: 0.02 },
    { type: 'sphere', c: [0.08, 1.1, 0.2], r: 0.04, color: '$eye', material: 'eye', name: 'eye', op: 'sharp', blend: 0, mirror: true },
    { type: 'sphere', c: [0.085, 1.11, 0.235], r: 0.018, color: '$pupil', material: 'eye', name: 'pupil', op: 'sharp', blend: 0, mirror: true },
    { type: 'ellipsoid', c: [0, 1.0, 0.2], r: [0.08, 0.03, 0.04], color: '$pupil', paint: true, name: 'mouth' },
    { type: 'cylinder', a: [0, 1.2, 0.02], b: [0, 1.3, 0.02], r: 0.18, round: 0.02, color: '$cap', name: 'cap', blend: 0.01 },
  ],
  paints: [{ type: 'facing', target: { zones: ['body', 'head'] }, dir: [0, -0.3, 1], start: 0.4, end: 0.95, color: '$belly', strength: 0.7 }],
};
