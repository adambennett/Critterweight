'use strict';
// Signed-distance primitives and the "part list" compiler.
//
// A creature art definition is an ordered list of PARTS. Each part is one primitive (sphere,
// ellipsoid, capsule, cone, box, cylinder, torus, half-space) bound to a body segment (`seg`),
// combined into the running field with an op:
//   union (smooth, default) | sharp (plain min) | subtract (carve) | intersect
// Parts flagged `paint: true` do not touch geometry; they only recolour the surface inside
// their volume (decals: eye markings, stripes on one area, rust stains...).
// Coordinates are FIGHTER REST SPACE (+Z forward, +Y up, +X = creature's left, metres),
// exactly the space the body JSON uses, so art and physics are authored against one frame.

const V = require('./vec');
const C = require('./color');
const { mirrorSegId } = require('./body');

const BIG = 1e3;

function smin(a, b, k) {
  if (k <= 0) return a < b ? a : b;
  const h = Math.max(k - Math.abs(a - b), 0) / k;
  return (a < b ? a : b) - h * h * k * 0.25;
}
function smax(a, b, k) {
  return -smin(-a, -b, k);
}

// ---- primitive distance functions (p in fighter space) -------------------------------------

function makeSphere(q) {
  const c = q.c, r = q.r;
  return {
    dist: (p) => Math.hypot(p[0] - c[0], p[1] - c[1], p[2] - c[2]) - r,
    aabb: [[c[0] - r, c[1] - r, c[2] - r], [c[0] + r, c[1] + r, c[2] + r]],
  };
}

function withRotation(q) {
  // returns world->local rotation (transpose of the local->world matrix)
  if (q.rot) return V.matTranspose(V.eulerDeg(q.rot));
  if (q.dir) return V.matTranspose(V.frameFromY(q.dir));
  return null;
}

function rotatedAabb(c, half, m) {
  // m: world->local; local->world = transpose. Extent along world axis i = sum_j |lw[i][j]| * half[j]
  if (!m) return [[c[0] - half[0], c[1] - half[1], c[2] - half[2]], [c[0] + half[0], c[1] + half[1], c[2] + half[2]]];
  const lw = V.matTranspose(m);
  const e = [0, 1, 2].map((i) => Math.abs(lw[i * 3]) * half[0] + Math.abs(lw[i * 3 + 1]) * half[1] + Math.abs(lw[i * 3 + 2]) * half[2]);
  return [[c[0] - e[0], c[1] - e[1], c[2] - e[2]], [c[0] + e[0], c[1] + e[1], c[2] + e[2]]];
}

function makeEllipsoid(q) {
  const c = q.c, r = q.r;
  const m = withRotation(q);
  return {
    dist: (p) => {
      let l = [p[0] - c[0], p[1] - c[1], p[2] - c[2]];
      if (m) l = V.matApply(m, l);
      const k0 = Math.hypot(l[0] / r[0], l[1] / r[1], l[2] / r[2]);
      const k1 = Math.hypot(l[0] / (r[0] * r[0]), l[1] / (r[1] * r[1]), l[2] / (r[2] * r[2]));
      return k1 > 1e-9 ? (k0 * (k0 - 1)) / k1 : -Math.min(r[0], r[1], r[2]);
    },
    aabb: rotatedAabb(c, r, m),
  };
}

function makeCapsule(q) {
  const a = q.a, b = q.b, r = q.r;
  const ab = V.sub(b, a);
  const l2 = Math.max(V.dot(ab, ab), 1e-12);
  return {
    dist: (p) => {
      const pa = [p[0] - a[0], p[1] - a[1], p[2] - a[2]];
      let t = (pa[0] * ab[0] + pa[1] * ab[1] + pa[2] * ab[2]) / l2;
      t = t < 0 ? 0 : t > 1 ? 1 : t;
      return Math.hypot(pa[0] - ab[0] * t, pa[1] - ab[1] * t, pa[2] - ab[2] * t) - r;
    },
    aabb: [[Math.min(a[0], b[0]) - r, Math.min(a[1], b[1]) - r, Math.min(a[2], b[2]) - r],
      [Math.max(a[0], b[0]) + r, Math.max(a[1], b[1]) + r, Math.max(a[2], b[2]) + r]],
  };
}

// Round cone (tapered capsule): radius ra at a, rb at b. Exact (Inigo Quilez).
function makeCone(q) {
  const a = q.a, b = q.b, r1 = q.ra, r2 = q.rb;
  const ba = V.sub(b, a);
  const l2 = V.dot(ba, ba);
  const rr = r1 - r2;
  const a2 = l2 - rr * rr;
  const il2 = 1 / Math.max(l2, 1e-12);
  const rm = Math.max(r1, r2);
  return {
    dist: (p) => {
      const pa = [p[0] - a[0], p[1] - a[1], p[2] - a[2]];
      const y = pa[0] * ba[0] + pa[1] * ba[1] + pa[2] * ba[2];
      const z = y - l2;
      const xx = pa[0] - ba[0] * y * il2, xy = pa[1] - ba[1] * y * il2, xz = pa[2] - ba[2] * y * il2;
      const x2 = (xx * xx + xy * xy + xz * xz) * l2 * l2;
      const y2 = y * y * l2;
      const z2 = z * z * l2;
      const k = Math.sign(rr) * rr * rr * x2;
      if (Math.sign(z) * a2 * z2 > k) return Math.sqrt(x2 + z2) * il2 - r2;
      if (Math.sign(y) * a2 * y2 < k) return Math.sqrt(x2 + y2) * il2 - r1;
      return (Math.sqrt(x2 * a2 * il2) + y * rr) * il2 - r1;
    },
    aabb: [[Math.min(a[0], b[0]) - rm, Math.min(a[1], b[1]) - rm, Math.min(a[2], b[2]) - rm],
      [Math.max(a[0], b[0]) + rm, Math.max(a[1], b[1]) + rm, Math.max(a[2], b[2]) + rm]],
  };
}

// Rounded box. Either centred (`c`, `size` full extents, optional `rot`) or a beam from `a` to
// `b` with cross-section `w` x `h` (local x, y) whose local +Z runs along a->b.
// `taper`: scale of the local x/y cross-section at the +Z end relative to the -Z end (1 = none).
function makeBox(q) {
  let c, half, m;
  if (q.a && q.b) {
    c = V.lerp(q.a, q.b, 0.5);
    const d = V.sub(q.b, q.a);
    half = [q.w * 0.5, q.h * 0.5, V.len(d) * 0.5];
    m = V.matTranspose(V.frameFromZ(d));
    if (q.rot) m = V.matMul(V.matTranspose(V.eulerDeg(q.rot)), m);
  } else {
    c = q.c;
    half = [q.size[0] * 0.5, q.size[1] * 0.5, q.size[2] * 0.5];
    m = q.rot ? V.matTranspose(V.eulerDeg(q.rot)) : null;
  }
  const round = Math.min(q.round || 0, half[0], half[1], half[2]);
  const hx = half[0] - round, hy = half[1] - round, hz = half[2] - round;
  const taper = q.taper == null ? 1 : q.taper;
  const taperY = q.taper_y == null ? taper : q.taper_y;
  const aabbHalf = [half[0] * Math.max(1, taper), half[1] * Math.max(1, taperY), half[2]];
  return {
    dist: (p) => {
      let l = [p[0] - c[0], p[1] - c[1], p[2] - c[2]];
      if (m) l = V.matApply(m, l);
      let sx = 1, sy = 1;
      if (taper !== 1 || taperY !== 1) {
        const t = Math.max(0, Math.min(1, (l[2] / half[2] + 1) * 0.5));
        sx = 1 + (taper - 1) * t;
        sy = 1 + (taperY - 1) * t;
      }
      const qx = Math.abs(l[0] / sx) - hx, qy = Math.abs(l[1] / sy) - hy, qz = Math.abs(l[2]) - hz;
      const ox = qx > 0 ? qx : 0, oy = qy > 0 ? qy : 0, oz = qz > 0 ? qz : 0;
      const inside = Math.min(Math.max(qx, qy, qz), 0);
      return Math.sqrt(ox * ox + oy * oy + oz * oz) + inside - round;
    },
    aabb: rotatedAabb(c, aabbHalf, m),
  };
}

// Rounded capped cylinder from a to b, radius r, edge rounding `round`.
function makeCylinder(q) {
  const a = q.a, b = q.b, r = q.r;
  const d = V.sub(b, a);
  const h = V.len(d) * 0.5;
  const c = V.lerp(a, b, 0.5);
  const m = V.matTranspose(V.frameFromY(d));
  const round = Math.min(q.round || 0, r, h);
  const rr = r - round, hh = h - round;
  return {
    dist: (p) => {
      const l = V.matApply(m, [p[0] - c[0], p[1] - c[1], p[2] - c[2]]);
      const qx = Math.hypot(l[0], l[2]) - rr, qy = Math.abs(l[1]) - hh;
      const ox = qx > 0 ? qx : 0, oy = qy > 0 ? qy : 0;
      return Math.min(Math.max(qx, qy), 0) + Math.sqrt(ox * ox + oy * oy) - round;
    },
    aabb: rotatedAabb(c, [r, h, r], m),
  };
}

// Torus around `axis` through `c`, major radius R, tube radius r.
function makeTorus(q) {
  const c = q.c, R = q.R, r = q.r;
  const m = V.matTranspose(V.frameFromY(q.axis || [0, 1, 0]));
  return {
    dist: (p) => {
      const l = V.matApply(m, [p[0] - c[0], p[1] - c[1], p[2] - c[2]]);
      const qx = Math.hypot(l[0], l[2]) - R;
      return Math.hypot(qx, l[1]) - r;
    },
    aabb: rotatedAabb(c, [R + r, r, R + r], m),
  };
}

// Half-space: everything on the +n side of the plane through p0 (use with op subtract to slice).
function makeHalf(q) {
  const n = V.norm(q.n), p0 = q.p;
  const ext = q.extent || 3;
  return {
    dist: (p) => (p[0] - p0[0]) * n[0] + (p[1] - p0[1]) * n[1] + (p[2] - p0[2]) * n[2],
    aabb: [[p0[0] - ext, p0[1] - ext, p0[2] - ext], [p0[0] + ext, p0[1] + ext, p0[2] + ext]],
  };
}

const BUILDERS = { sphere: makeSphere, ellipsoid: makeEllipsoid, capsule: makeCapsule, cone: makeCone,
  box: makeBox, cylinder: makeCylinder, torus: makeTorus, half: makeHalf };

// ---- definition expansion -------------------------------------------------------------------

const POINT_KEYS = ['c', 'a', 'b', 'p'];
const VEC_KEYS = ['axis', 'dir', 'n'];

function mirrorPart(part) {
  const m = Object.assign({}, part);
  delete m.mirror;
  for (const k of POINT_KEYS) if (m[k]) m[k] = [-m[k][0], m[k][1], m[k][2]];
  for (const k of VEC_KEYS) if (m[k]) m[k] = [-m[k][0], m[k][1], m[k][2]];
  if (m.clip) m.clip = m.clip.map((h) => ({ p: [-h.p[0], h.p[1], h.p[2]], n: [-h.n[0], h.n[1], h.n[2]] }));
  if (m.rot) m.rot = [m.rot[0], -m.rot[1], -m.rot[2]];
  if (m.seg) m.seg = mirrorSegId(m.seg);
  if (m.name) m.name = mirrorSegId(m.name);
  if (m.mirror_color) m.color = m.mirror_color;
  return m;
}

function flatten(parts, out) {
  for (const p of parts) {
    if (p == null) continue;
    if (Array.isArray(p)) flatten(p, out);
    else out.push(p);
  }
  return out;
}

function scalePart(part, k) {
  const s = Object.assign({}, part);
  for (const key of POINT_KEYS) if (s[key]) s[key] = s[key].map((x) => x * k);
  if (s.clip) s.clip = s.clip.map((h) => ({ p: h.p.map((x) => x * k), n: h.n }));
  for (const key of ['r', 'ra', 'rb', 'R', 'round', 'w', 'h', 'blend', 'skin_soft']) if (typeof s[key] === 'number') s[key] *= k;
  if (Array.isArray(s.r)) s.r = s.r.map((x) => x * k);
  if (s.size) s.size = s.size.map((x) => x * k);
  return s;
}

// Compiles def.parts into primitives. Returns { prims, materials, bounds }.
function compile(def, bones, opts) {
  const res = opts.res;
  const palette = def.palette || {};
  const materials = Object.assign({ skin: { roughness: 0.7, metallic: 0 } }, def.materials || {});
  const boneIds = new Set(bones.map((b) => b.id));
  const defaultSeg = bones[0].id;
  let raw = flatten(def.parts || [], []);
  const expanded = [];
  for (const p of raw) {
    if (def.scale && def.scale !== 1) {
      expanded.push(scalePart(p, def.scale));
      if (p.mirror) expanded.push(scalePart(mirrorPart(p), def.scale));
    } else {
      expanded.push(p);
      if (p.mirror) expanded.push(mirrorPart(p));
    }
  }
  const prims = [];
  const defaultBlend = def.blend == null ? 0.04 : def.blend;
  let bmin = [Infinity, Infinity, Infinity], bmax = [-Infinity, -Infinity, -Infinity];
  expanded.forEach((p, i) => {
    const type = p.type || 'sphere';
    const build = BUILDERS[type];
    if (!build) throw new Error(`${def.id}: part ${i} has unknown type '${type}'`);
    const seg = p.seg || defaultSeg;
    if (!boneIds.has(seg)) throw new Error(`${def.id}: part ${i} (${p.name || type}) binds unknown segment '${seg}'`);
    const material = p.material || 'skin';
    if (!materials[material]) throw new Error(`${def.id}: part ${i} uses unknown material '${material}'`);
    let { dist, aabb } = build(p);
    if (p.clip && p.clip.length) {
      // keep only the side of each plane where (x - p).n < 0 (clips this part alone)
      const planes = p.clip.map((h) => ({ p: h.p, n: V.norm(h.n) }));
      const inner = dist;
      dist = (x) => {
        let d = inner(x);
        for (const h of planes) {
          const s = (x[0] - h.p[0]) * h.n[0] + (x[1] - h.p[1]) * h.n[1] + (x[2] - h.p[2]) * h.n[2];
          if (s > d) d = s;
        }
        return d;
      };
    }
    const blend = p.blend == null ? defaultBlend : p.blend;
    const op = p.op || (p.paint ? 'paint' : 'union');
    const margin = (op === 'union' || op === 'subtract' || op === 'intersect' ? blend : 0) + res * 2.5;
    const prim = {
      index: i, name: p.name || `${type}_${i}`, type, seg, op, paint: !!p.paint, blend,
      color: p.color != null ? C.resolve(p.color, palette) : null,
      material, glow: p.glow || 0, skinSoft: p.skin_soft == null ? (opts.skinSoft || 0.035) : p.skin_soft,
      skin: p.skin == null ? !p.paint : !!p.skin,
      crisp: p.crisp == null ? true : !!p.crisp,
      dist, aabb: [[aabb[0][0] - margin, aabb[0][1] - margin, aabb[0][2] - margin], [aabb[1][0] + margin, aabb[1][1] + margin, aabb[1][2] + margin]],
      weight: p.weight == null ? 1 : p.weight,
    };
    if (prim.color == null && !prim.paint && op !== 'subtract' && op !== 'intersect') {
      prim.color = C.resolve(def.default_color || '$primary', palette);
    }
    prims.push(prim);
    if (op === 'union' || op === 'sharp') {
      for (let k = 0; k < 3; k++) {
        bmin[k] = Math.min(bmin[k], prim.aabb[0][k]);
        bmax[k] = Math.max(bmax[k], prim.aabb[1][k]);
      }
    }
  });
  if (!isFinite(bmin[0])) throw new Error(`${def.id}: no solid parts`);
  return { prims, materials, bounds: [bmin, bmax], palette };
}

// Full sequential field evaluation at one point (used for normals/gradients).
function evalField(prims, p) {
  let f = BIG;
  for (let i = 0; i < prims.length; i++) {
    const q = prims[i];
    if (q.paint) continue;
    const bb = q.aabb;
    if (p[0] < bb[0][0] || p[0] > bb[1][0] || p[1] < bb[0][1] || p[1] > bb[1][1] || p[2] < bb[0][2] || p[2] > bb[1][2]) continue;
    const d = q.dist(p);
    switch (q.op) {
      case 'union': f = smin(f, d, q.blend); break;
      case 'sharp': f = f < d ? f : d; break;
      case 'subtract': f = smax(f, -d, q.blend); break;
      case 'intersect': f = smax(f, d, q.blend); break;
      default: break;
    }
  }
  return f;
}

function gradient(prims, p, h) {
  const dx = evalField(prims, [p[0] + h, p[1], p[2]]) - evalField(prims, [p[0] - h, p[1], p[2]]);
  const dy = evalField(prims, [p[0], p[1] + h, p[2]]) - evalField(prims, [p[0], p[1] - h, p[2]]);
  const dz = evalField(prims, [p[0], p[1], p[2] + h]) - evalField(prims, [p[0], p[1], p[2] - h]);
  return V.norm([dx, dy, dz]);
}

// Splats every primitive into a corner-sampled grid (Float32Array) in definition order.
function splat(prims, grid) {
  const { nx, ny, nz, origin, res, field } = grid;
  field.fill(BIG);
  const p = [0, 0, 0];
  for (const q of prims) {
    if (q.paint) continue;
    const i0 = Math.max(0, Math.floor((q.aabb[0][0] - origin[0]) / res));
    const j0 = Math.max(0, Math.floor((q.aabb[0][1] - origin[1]) / res));
    const k0 = Math.max(0, Math.floor((q.aabb[0][2] - origin[2]) / res));
    const i1 = Math.min(nx - 1, Math.ceil((q.aabb[1][0] - origin[0]) / res));
    const j1 = Math.min(ny - 1, Math.ceil((q.aabb[1][1] - origin[1]) / res));
    const k1 = Math.min(nz - 1, Math.ceil((q.aabb[1][2] - origin[2]) / res));
    const op = q.op, k = q.blend, dist = q.dist;
    for (let i = i0; i <= i1; i++) {
      p[0] = origin[0] + i * res;
      for (let j = j0; j <= j1; j++) {
        p[1] = origin[1] + j * res;
        let idx = (i * ny + j) * nz + k0;
        for (let kk = k0; kk <= k1; kk++, idx++) {
          p[2] = origin[2] + kk * res;
          const d = dist(p);
          const f = field[idx];
          let r;
          if (op === 'union') r = smin(f, d, k);
          else if (op === 'sharp') r = f < d ? f : d;
          else if (op === 'subtract') r = smax(f, -d, k);
          else r = smax(f, d, k);
          field[idx] = r;
        }
      }
    }
  }
}

module.exports = { BIG, smin, smax, compile, evalField, gradient, splat, BUILDERS };
