'use strict';
// Tiny allocation-light vector helpers on plain [x, y, z] arrays. Forge-internal.

const v3 = (x = 0, y = 0, z = 0) => [x, y, z];
const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const mul = (a, s) => [a[0] * s, a[1] * s, a[2] * s];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const len = (a) => Math.sqrt(dot(a, a));
const dist = (a, b) => len(sub(a, b));
const norm = (a) => { const l = len(a); return l > 1e-12 ? mul(a, 1 / l) : [0, 1, 0]; };
const lerp = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);
const mix = (a, b, t) => a + (b - a) * t;
const smoothstep = (e0, e1, x) => { const t = clamp((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t); };

// 3x3 rotation matrices stored row-major as 9 numbers. apply(m, p) = m * p.
const matIdentity = () => [1, 0, 0, 0, 1, 0, 0, 0, 1];
const matApply = (m, p) => [
  m[0] * p[0] + m[1] * p[1] + m[2] * p[2],
  m[3] * p[0] + m[4] * p[1] + m[5] * p[2],
  m[6] * p[0] + m[7] * p[1] + m[8] * p[2]];
const matTranspose = (m) => [m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8]];
const matMul = (a, b) => {
  const o = new Array(9);
  for (let r = 0; r < 3; r++) for (let c = 0; c < 3; c++) {
    o[r * 3 + c] = a[r * 3] * b[c] + a[r * 3 + 1] * b[3 + c] + a[r * 3 + 2] * b[6 + c];
  }
  return o;
};
const rotX = (a) => { const c = Math.cos(a), s = Math.sin(a); return [1, 0, 0, 0, c, -s, 0, s, c]; };
const rotY = (a) => { const c = Math.cos(a), s = Math.sin(a); return [c, 0, s, 0, 1, 0, -s, 0, c]; };
const rotZ = (a) => { const c = Math.cos(a), s = Math.sin(a); return [c, -s, 0, s, c, 0, 0, 0, 1]; };
// Euler degrees, intrinsic X then Y then Z (same convention as the game's MathX.euler_deg).
const eulerDeg = (e) => {
  const d = Math.PI / 180;
  return matMul(rotX(e[0] * d), matMul(rotY(e[1] * d), rotZ(e[2] * d)));
};
// Rotation taking local +Y onto `dir` (used by cylinders / beams).
const frameFromY = (dir) => {
  const y = norm(dir);
  let h = Math.abs(y[1]) < 0.9 ? [0, 1, 0] : [1, 0, 0];
  const x = norm(cross(h, y));
  const z = cross(x, y);
  return [x[0], y[0], z[0], x[1], y[1], z[1], x[2], y[2], z[2]];
};
// Rotation taking local +Z onto `dir`.
const frameFromZ = (dir) => {
  const z = norm(dir);
  let h = Math.abs(z[1]) < 0.9 ? [0, 1, 0] : [1, 0, 0];
  const x = norm(cross(h, z));
  const y = cross(z, x);
  return [x[0], y[0], z[0], x[1], y[1], z[1], x[2], y[2], z[2]];
};

module.exports = { v3, add, sub, mul, dot, cross, len, dist, norm, lerp, clamp, mix, smoothstep,
  matIdentity, matApply, matTranspose, matMul, rotX, rotY, rotZ, eulerDeg, frameFromY, frameFromZ };
