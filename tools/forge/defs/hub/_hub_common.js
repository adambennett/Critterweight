'use strict';
// Shared bits for the static hub NPC models (HUB.md §2). Hub NPCs are not ragdolls: every part
// binds to a single "root" bone at the origin, standing on the floor at y = 0, facing +Z.
// (File names starting with "_" are ignored by the forge's definition scan.)

const BASE_MATERIALS = {
  skin: { roughness: 0.7, metallic: 0 },
  fur: { roughness: 0.85, metallic: 0 },
  cloth: { roughness: 0.92, metallic: 0 },
  eye: { roughness: 0.2, metallic: 0 },
  metal: { roughness: 0.45, metallic: 0.7 },
  gold: { roughness: 0.3, metallic: 0.9 },
  wood: { roughness: 0.65, metallic: 0 },
  glow: { roughness: 0.4, metallic: 0, emissive: '#FFD9A0' },
};

function materials(extra) {
  return Object.assign({}, BASE_MATERIALS, extra || {});
}

// A simple stand-up body: belly ellipsoid + shoulders + neck, in `color`.
function torso(o) {
  return [
    { type: 'ellipsoid', c: [0, o.y, 0], r: [o.w, o.h, o.d], color: o.color, material: o.material, name: o.name || 'torso', blend: 0.05 },
    { type: 'capsule', a: [-o.w * 0.75, o.y + o.h * 0.75, 0], b: [o.w * 0.75, o.y + o.h * 0.75, 0], r: o.w * 0.4, color: o.color, material: o.material, name: o.name || 'torso', blend: 0.05 },
  ];
}

// Two stubby legs + feet.
function legs(o) {
  const out = [];
  for (const s of [1, -1]) {
    out.push({ type: 'cone', a: [o.x * s, o.hip, 0], b: [o.x * s, 0.06, 0.02], ra: o.r, rb: o.r * 0.8, color: o.color, material: o.material, name: 'leg', blend: 0.04 });
    out.push({ type: 'ellipsoid', c: [o.x * s, 0.045, 0.05], r: [o.r * 1.1, 0.045, o.r * 1.9], color: o.foot || o.color, material: o.foot_material || o.material, name: 'foot', blend: 0.02 });
  }
  return out;
}

// Two arms hanging from the shoulders toward `hand` positions.
function arms(o) {
  const out = [];
  for (const s of [1, -1]) {
    const sh = [o.sx * s, o.sy, 0];
    const el = [o.ex * s, o.ey, o.ez || 0.04];
    const hd = [o.hx * s, o.hy, o.hz || 0.1];
    out.push({ type: 'cone', a: sh, b: el, ra: o.r, rb: o.r * 0.85, color: o.color, material: o.material, name: 'arm', blend: 0.04 });
    out.push({ type: 'cone', a: el, b: hd, ra: o.r * 0.85, rb: o.r * 0.7, color: o.sleeve || o.color, material: o.sleeve_material || o.material, name: 'arm', blend: 0.04 });
    out.push({ type: 'sphere', c: hd, r: o.r * (o.hand_scale || 1.2), color: o.hand || o.color, material: o.hand_material || 'skin', name: 'hand', blend: 0.03 });
  }
  return out;
}

module.exports = { materials, torso, legs, arms };
