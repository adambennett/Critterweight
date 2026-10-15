'use strict';
// Naive surface nets over a corner-sampled signed distance grid. Produces a closed, manifold
// triangle mesh (quads split along their shorter diagonal). One vertex per sign-changing cell,
// placed at the mean of the cell's edge crossings; one quad per sign-changing lattice edge.

function makeGrid(bounds, res) {
  const origin = bounds[0].map((x) => x - res);
  const size = [0, 1, 2].map((k) => bounds[1][k] - bounds[0][k] + 2 * res);
  const nx = Math.ceil(size[0] / res) + 1, ny = Math.ceil(size[1] / res) + 1, nz = Math.ceil(size[2] / res) + 1;
  return { origin, res, nx, ny, nz, field: new Float32Array(nx * ny * nz) };
}

const EDGES = [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]];
// corner c bits: x = c>>2, y = (c>>1)&1, z = c&1

function surfaceNets(grid) {
  const { nx, ny, nz, origin, res, field } = grid;
  const cx = nx - 1, cy = ny - 1, cz = nz - 1;
  const cellVert = new Int32Array(cx * cy * cz).fill(-1);
  const pos = [];
  const v = new Float32Array(8);
  for (let i = 0; i < cx; i++) {
    for (let j = 0; j < cy; j++) {
      for (let k = 0; k < cz; k++) {
        let mask = 0;
        for (let c = 0; c < 8; c++) {
          const ii = i + (c >> 2), jj = j + ((c >> 1) & 1), kk = k + (c & 1);
          const f = field[(ii * ny + jj) * nz + kk];
          v[c] = f;
          if (f < 0) mask |= 1 << c;
        }
        if (mask === 0 || mask === 255) continue;
        let sx = 0, sy = 0, sz = 0, cnt = 0;
        for (let e = 0; e < 12; e++) {
          const c0 = EDGES[e][0], c1 = EDGES[e][1];
          const in0 = (mask >> c0) & 1, in1 = (mask >> c1) & 1;
          if (in0 === in1) continue;
          const t = v[c0] / (v[c0] - v[c1]);
          const x0 = c0 >> 2, y0 = (c0 >> 1) & 1, z0 = c0 & 1;
          const x1 = c1 >> 2, y1 = (c1 >> 1) & 1, z1 = c1 & 1;
          sx += x0 + (x1 - x0) * t;
          sy += y0 + (y1 - y0) * t;
          sz += z0 + (z1 - z0) * t;
          cnt++;
        }
        cellVert[(i * cy + j) * cz + k] = pos.length / 3;
        pos.push(origin[0] + (i + sx / cnt) * res, origin[1] + (j + sy / cnt) * res, origin[2] + (k + sz / cnt) * res);
      }
    }
  }
  const tris = [];
  const P = (idx, a) => pos[idx * 3 + a];
  function emitQuad(q0, q1, q2, q3, axis, lowerInside) {
    if (q0 < 0 || q1 < 0 || q2 < 0 || q3 < 0) return;
    // outward normal of the quad vs. the sign direction along this lattice axis
    const ax = P(q1, 0) - P(q0, 0), ay = P(q1, 1) - P(q0, 1), az = P(q1, 2) - P(q0, 2);
    const bx = P(q2, 0) - P(q0, 0), by = P(q2, 1) - P(q0, 1), bz = P(q2, 2) - P(q0, 2);
    const n = [ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx];
    const want = lowerInside ? 1 : -1;
    if (n[axis] * want < 0) { const t = q1; q1 = q3; q3 = t; }
    // split along the shorter diagonal
    const d02 = (P(q0, 0) - P(q2, 0)) ** 2 + (P(q0, 1) - P(q2, 1)) ** 2 + (P(q0, 2) - P(q2, 2)) ** 2;
    const d13 = (P(q1, 0) - P(q3, 0)) ** 2 + (P(q1, 1) - P(q3, 1)) ** 2 + (P(q1, 2) - P(q3, 2)) ** 2;
    if (d02 <= d13) tris.push(q0, q1, q2, q0, q2, q3);
    else tris.push(q0, q1, q3, q1, q2, q3);
  }
  const CV = (i, j, k) => (i < 0 || j < 0 || k < 0 || i >= cx || j >= cy || k >= cz) ? -1 : cellVert[(i * cy + j) * cz + k];
  for (let i = 0; i < nx; i++) {
    for (let j = 0; j < ny; j++) {
      for (let k = 0; k < nz; k++) {
        const f0 = field[(i * ny + j) * nz + k];
        const in0 = f0 < 0;
        // x edge
        if (i + 1 < nx) {
          const f1 = field[((i + 1) * ny + j) * nz + k];
          if ((f1 < 0) !== in0) emitQuad(CV(i, j - 1, k - 1), CV(i, j, k - 1), CV(i, j, k), CV(i, j - 1, k), 0, in0);
        }
        if (j + 1 < ny) {
          const f1 = field[(i * ny + j + 1) * nz + k];
          if ((f1 < 0) !== in0) emitQuad(CV(i - 1, j, k - 1), CV(i - 1, j, k), CV(i, j, k), CV(i, j, k - 1), 1, in0);
        }
        if (k + 1 < nz) {
          const f1 = field[(i * ny + j) * nz + k + 1];
          if ((f1 < 0) !== in0) emitQuad(CV(i - 1, j - 1, k), CV(i, j - 1, k), CV(i, j, k), CV(i - 1, j, k), 2, in0);
        }
      }
    }
  }
  return { positions: Float64Array.from(pos), tris: Int32Array.from(tris) };
}

// Area-weighted vertex normals from faces (fallback / sanity checks).
function faceNormals(positions, tris) {
  const n = positions.length / 3;
  const out = new Float64Array(n * 3);
  for (let t = 0; t < tris.length; t += 3) {
    const a = tris[t], b = tris[t + 1], c = tris[t + 2];
    const ax = positions[b * 3] - positions[a * 3], ay = positions[b * 3 + 1] - positions[a * 3 + 1], az = positions[b * 3 + 2] - positions[a * 3 + 2];
    const bx = positions[c * 3] - positions[a * 3], by = positions[c * 3 + 1] - positions[a * 3 + 1], bz = positions[c * 3 + 2] - positions[a * 3 + 2];
    const nx = ay * bz - az * by, ny = az * bx - ax * bz, nz = ax * by - ay * bx;
    for (const i of [a, b, c]) { out[i * 3] += nx; out[i * 3 + 1] += ny; out[i * 3 + 2] += nz; }
  }
  for (let i = 0; i < n; i++) {
    const l = Math.hypot(out[i * 3], out[i * 3 + 1], out[i * 3 + 2]) || 1;
    out[i * 3] /= l; out[i * 3 + 1] /= l; out[i * 3 + 2] /= l;
  }
  return out;
}

// Laplacian smoothing (a few iterations) to take the voxel grain off surface-net meshes.
function smooth(positions, tris, iterations, lambda) {
  const n = positions.length / 3;
  const adj = new Array(n);
  for (let i = 0; i < n; i++) adj[i] = [];
  for (let t = 0; t < tris.length; t += 3) {
    const a = tris[t], b = tris[t + 1], c = tris[t + 2];
    adj[a].push(b, c); adj[b].push(a, c); adj[c].push(a, b);
  }
  let cur = positions;
  for (let it = 0; it < iterations; it++) {
    const next = new Float64Array(cur.length);
    for (let i = 0; i < n; i++) {
      const nb = adj[i];
      if (nb.length === 0) { next[i * 3] = cur[i * 3]; next[i * 3 + 1] = cur[i * 3 + 1]; next[i * 3 + 2] = cur[i * 3 + 2]; continue; }
      let sx = 0, sy = 0, sz = 0;
      for (const j of nb) { sx += cur[j * 3]; sy += cur[j * 3 + 1]; sz += cur[j * 3 + 2]; }
      const k = nb.length;
      next[i * 3] = cur[i * 3] + lambda * (sx / k - cur[i * 3]);
      next[i * 3 + 1] = cur[i * 3 + 1] + lambda * (sy / k - cur[i * 3 + 1]);
      next[i * 3 + 2] = cur[i * 3 + 2] + lambda * (sz / k - cur[i * 3 + 2]);
    }
    cur = next;
  }
  return cur;
}

module.exports = { makeGrid, surfaceNets, faceNormals, smooth };
