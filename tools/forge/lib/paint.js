'use strict';
// Surface colouring. The colour of a surface point is decided in three stages:
//   1. ZONE: the nearest solid part (its colour, material and glow).
//   2. PAINT PARTS: parts with `paint: true` recolour the surface inside their volume (decals).
//   3. PAINT LAYERS (def.paints, in order): procedural patterns restricted to a target
//      (segments / zone names / materials): stripes, spots, band, edge, gradient, facing.
// Discrete results (zones, decals, stripes, spots, bands, edges) contribute to a "crisp key":
// triangles whose corners disagree are split so the boundary stays hard-edged. Continuous
// layers (gradient, facing) shade smoothly across vertices.

const V = require('./vec');
const C = require('./color');

function hash3(x, y, z, seed) {
  let h = (x * 374761393 + y * 668265263 + z * 2147483647 + seed * 1013904223) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h = (h ^ (h >>> 16)) >>> 0;
  return h / 4294967296;
}

function compileLayer(l, palette, index) {
  const out = Object.assign({}, l);
  out.id = 'L' + index;
  if (l.color != null) out.color = C.resolve(l.color, palette);
  if (l.axis) out.axis = V.norm(l.axis);
  if (l.dir) out.dir = V.norm(l.dir);
  out.origin = l.origin || [0, 0, 0];
  out.target = l.target || {};
  return out;
}

function matches(target, ctx) {
  if (target.segs && !target.segs.includes(ctx.seg)) return false;
  if (target.zones && !target.zones.includes(ctx.zoneName)) return false;
  if (target.materials && !target.materials.includes(ctx.material)) return false;
  if (target.exclude_zones && target.exclude_zones.includes(ctx.zoneName)) return false;
  return true;
}

function makePainter(def, compiled) {
  const prims = compiled.prims;
  const palette = compiled.palette;
  const geom = prims.filter((p) => !p.paint && (p.op === 'union' || p.op === 'sharp'));
  const decals = prims.filter((p) => p.paint);
  const layers = (def.paints || []).map((l, i) => compileLayer(l, palette, i));
  // parts sharing a name, material and colour form one zone (no crisp edge between them)
  const groupKeys = new Map();
  const zoneGroup = geom.map((q) => {
    const k = q.name + '|' + q.material + '|' + C.linearToHex(q.color) + '|' + (q.glow || 0);
    if (!groupKeys.has(k)) groupKeys.set(k, groupKeys.size);
    return groupKeys.get(k);
  });

  function nearestZone(p) {
    let best = -1, bd = Infinity;
    for (let i = 0; i < geom.length; i++) {
      const q = geom[i];
      const bb = q.aabb;
      if (p[0] < bb[0][0] || p[0] > bb[1][0] || p[1] < bb[0][1] || p[1] > bb[1][1] || p[2] < bb[0][2] || p[2] > bb[1][2]) continue;
      const d = q.dist(p);
      if (d < bd) { bd = d; best = i; }
    }
    if (best < 0) {
      for (let i = 0; i < geom.length; i++) { const d = geom[i].dist(p); if (d < bd) { bd = d; best = i; } }
    }
    return best;
  }

  // second-nearest distance gap (for edge highlights)
  function zoneGap(p, zi) {
    let d1 = geom[zi].dist(p), d2 = Infinity;
    for (let i = 0; i < geom.length; i++) {
      if (i === zi) continue;
      const q = geom[i];
      const bb = q.aabb;
      if (p[0] < bb[0][0] || p[0] > bb[1][0] || p[1] < bb[0][1] || p[1] > bb[1][1] || p[2] < bb[0][2] || p[2] > bb[1][2]) continue;
      const d = q.dist(p);
      if (d < d2) d2 = d;
    }
    return d2 - d1;
  }

  function colorAt(p, n, zoneHint) {
    const zi = zoneHint == null || zoneHint < 0 ? nearestZone(p) : zoneHint;
    const z = geom[zi];
    const ctx = { seg: z.seg, zoneName: z.name, material: z.material, color: z.color.slice(), glow: z.glow, key: 'z' + zoneGroup[zi] };
    for (let i = 0; i < decals.length; i++) {
      const d = decals[i];
      const bb = d.aabb;
      if (p[0] < bb[0][0] || p[0] > bb[1][0] || p[1] < bb[0][1] || p[1] > bb[1][1] || p[2] < bb[0][2] || p[2] > bb[1][2]) continue;
      if (d.dist(p) < 0) {
        if (d.color) ctx.color = d.color.slice();
        if (d.material !== 'skin' || d.materialExplicit) ctx.material = d.material;
        if (d.glow) ctx.glow = d.glow;
        ctx.key += '|d' + i;
      }
    }
    for (const l of layers) {
      if (!matches(l.target, ctx)) continue;
      switch (l.type) {
        case 'stripes': {
          const s = V.dot(V.sub(p, l.origin), l.axis) / l.period + (l.phase || 0);
          const frac = s - Math.floor(s);
          if (frac < (l.duty == null ? 0.5 : l.duty)) { applyDiscrete(ctx, l); }
          break;
        }
        case 'spots': {
          const cell = l.cell || 0.1, r = l.radius || cell * 0.3, seed = l.seed || 1;
          const cx = Math.floor(p[0] / cell), cy = Math.floor(p[1] / cell), cz = Math.floor(p[2] / cell);
          let hit = false;
          for (let dx = -1; dx <= 1 && !hit; dx++) for (let dy = -1; dy <= 1 && !hit; dy++) for (let dz = -1; dz <= 1 && !hit; dz++) {
            const ix = cx + dx, iy = cy + dy, iz = cz + dz;
            if (hash3(ix, iy, iz, seed + 7) > (l.density == null ? 0.6 : l.density)) continue;
            const jx = (ix + 0.2 + 0.6 * hash3(ix, iy, iz, seed)) * cell;
            const jy = (iy + 0.2 + 0.6 * hash3(ix, iy, iz, seed + 1)) * cell;
            const jz = (iz + 0.2 + 0.6 * hash3(ix, iy, iz, seed + 2)) * cell;
            const rr = r * (0.7 + 0.6 * hash3(ix, iy, iz, seed + 3));
            if (Math.hypot(p[0] - jx, p[1] - jy, p[2] - jz) < rr) hit = true;
          }
          if (hit) applyDiscrete(ctx, l);
          break;
        }
        case 'band': {
          const s = V.dot(V.sub(p, l.origin), l.axis);
          if (Math.abs(s - (l.center || 0)) < (l.width || 0.05) * 0.5) applyDiscrete(ctx, l);
          break;
        }
        case 'edge': {
          if (zoneGap(p, zi) < (l.width || 0.02)) applyDiscrete(ctx, l);
          break;
        }
        case 'gradient': {
          const s = V.dot(V.sub(p, l.origin), l.axis);
          const t = V.smoothstep(l.from, l.to, s) * (l.strength == null ? 1 : l.strength);
          ctx.color = C.mixc(ctx.color, l.color || C.lighten(ctx.color, 0.35), t);
          break;
        }
        case 'facing': {
          const t = V.smoothstep(l.start == null ? 0.1 : l.start, l.end == null ? 0.8 : l.end, V.dot(n, l.dir)) * (l.strength == null ? 1 : l.strength);
          ctx.color = C.mixc(ctx.color, l.color || C.lighten(ctx.color, 0.3), t);
          break;
        }
        default:
          throw new Error(`${def.id}: unknown paint layer type '${l.type}'`);
      }
    }
    return ctx;
  }

  function applyDiscrete(ctx, l) {
    if (l.color) ctx.color = l.color.slice();
    else if (l.lighten) ctx.color = C.lighten(ctx.color, l.lighten);
    else if (l.darken) ctx.color = C.darken(ctx.color, l.darken);
    if (l.material) ctx.material = l.material;
    if (l.glow != null) ctx.glow = l.glow;
    ctx.key += '|' + l.id;
  }

  return { nearestZone, colorAt, geom, zoneGroup };
}

module.exports = { makePainter };
