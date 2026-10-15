'use strict';
// Quadric error metric edge-collapse decimation (Garland & Heckbert) for closed triangle
// meshes. Honours per-vertex zone ids: an edge joining two zones only collapses onto one of
// its endpoints (never a new in-between position) and pays a cost penalty, so colour/material
// boundaries stay where the SDF put them. Rejects collapses that flip faces or pinch the mesh.

class MinHeap {
  constructor() { this.a = []; }
  get size() { return this.a.length; }
  push(e) {
    const a = this.a; a.push(e);
    let i = a.length - 1;
    while (i > 0) { const p = (i - 1) >> 1; if (a[p].c <= a[i].c) break; [a[p], a[i]] = [a[i], a[p]]; i = p; }
  }
  pop() {
    const a = this.a; const top = a[0]; const last = a.pop();
    if (a.length) {
      a[0] = last; let i = 0;
      for (;;) {
        const l = 2 * i + 1, r = l + 1; let m = i;
        if (l < a.length && a[l].c < a[m].c) m = l;
        if (r < a.length && a[r].c < a[m].c) m = r;
        if (m === i) break; [a[m], a[i]] = [a[i], a[m]]; i = m;
      }
    }
    return top;
  }
}

function decimate(positions, tris, zones, targetTris, opts = {}) {
  const zonePenalty = opts.zonePenalty == null ? 6 : opts.zonePenalty;
  const n = positions.length / 3;
  const m = tris.length / 3;
  const P = Float64Array.from(positions);
  const F = Int32Array.from(tris);
  const alive = new Uint8Array(n).fill(1);
  const faceAlive = new Uint8Array(m).fill(1);
  const Q = new Float64Array(n * 10);
  const vfaces = new Array(n);
  for (let i = 0; i < n; i++) vfaces[i] = [];
  const faceNormal = (f, pos) => {
    const a = F[f * 3], b = F[f * 3 + 1], c = F[f * 3 + 2];
    const ax = pos[b * 3] - pos[a * 3], ay = pos[b * 3 + 1] - pos[a * 3 + 1], az = pos[b * 3 + 2] - pos[a * 3 + 2];
    const bx = pos[c * 3] - pos[a * 3], by = pos[c * 3 + 1] - pos[a * 3 + 1], bz = pos[c * 3 + 2] - pos[a * 3 + 2];
    return [ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx];
  };
  for (let f = 0; f < m; f++) {
    const a = F[f * 3], b = F[f * 3 + 1], c = F[f * 3 + 2];
    vfaces[a].push(f); vfaces[b].push(f); vfaces[c].push(f);
    const nrm = faceNormal(f, P);
    const area2 = Math.hypot(nrm[0], nrm[1], nrm[2]);
    if (area2 < 1e-18) continue;
    const nx = nrm[0] / area2, ny = nrm[1] / area2, nz = nrm[2] / area2;
    const d = -(nx * P[a * 3] + ny * P[a * 3 + 1] + nz * P[a * 3 + 2]);
    const w = area2 * 0.5;
    const q = [nx * nx, nx * ny, nx * nz, nx * d, ny * ny, ny * nz, ny * d, nz * nz, nz * d, d * d];
    for (const vi of [a, b, c]) for (let k = 0; k < 10; k++) Q[vi * 10 + k] += q[k] * w;
  }
  const edgeKey = (u, v) => (u < v ? u * n + v : v * n + u);
  const version = new Map();
  const heap = new MinHeap();
  const qsum = new Float64Array(10);
  const evalQ = (q, x, y, z) => q[0] * x * x + 2 * q[1] * x * y + 2 * q[2] * x * z + 2 * q[3] * x + q[4] * y * y + 2 * q[5] * y * z + 2 * q[6] * y + q[7] * z * z + 2 * q[8] * z + q[9];

  function edgeCost(u, v) {
    for (let k = 0; k < 10; k++) qsum[k] = Q[u * 10 + k] + Q[v * 10 + k];
    const q = qsum;
    let best = null, bestCost = Infinity;
    const cands = [];
    const sameZone = zones[u] === zones[v];
    if (sameZone) {
      // optimal point: solve A x = -b
      const a11 = q[0], a12 = q[1], a13 = q[2], a22 = q[4], a23 = q[5], a33 = q[7];
      const det = a11 * (a22 * a33 - a23 * a23) - a12 * (a12 * a33 - a23 * a13) + a13 * (a12 * a23 - a22 * a13);
      if (Math.abs(det) > 1e-14) {
        const bx = -q[3], by = -q[6], bz = -q[8];
        const x = (bx * (a22 * a33 - a23 * a23) - a12 * (by * a33 - a23 * bz) + a13 * (by * a23 - a22 * bz)) / det;
        const y = (a11 * (by * a33 - a23 * bz) - bx * (a12 * a33 - a23 * a13) + a13 * (a12 * bz - by * a13)) / det;
        const z = (a11 * (a22 * bz - by * a23) - a12 * (a12 * bz - by * a13) + bx * (a12 * a23 - a22 * a13)) / det;
        // guard against runaway solutions far from the edge
        const mx = (P[u * 3] + P[v * 3]) * 0.5, my = (P[u * 3 + 1] + P[v * 3 + 1]) * 0.5, mz = (P[u * 3 + 2] + P[v * 3 + 2]) * 0.5;
        const el = Math.hypot(P[u * 3] - P[v * 3], P[u * 3 + 1] - P[v * 3 + 1], P[u * 3 + 2] - P[v * 3 + 2]);
        if (Math.hypot(x - mx, y - my, z - mz) < el * 1.5) cands.push([x, y, z]);
      }
      cands.push([(P[u * 3] + P[v * 3]) * 0.5, (P[u * 3 + 1] + P[v * 3 + 1]) * 0.5, (P[u * 3 + 2] + P[v * 3 + 2]) * 0.5]);
    }
    cands.push([P[u * 3], P[u * 3 + 1], P[u * 3 + 2]], [P[v * 3], P[v * 3 + 1], P[v * 3 + 2]]);
    for (const c of cands) {
      const cost = evalQ(q, c[0], c[1], c[2]);
      if (cost < bestCost) { bestCost = cost; best = c; }
    }
    if (!sameZone) bestCost = Math.max(bestCost, 0) * zonePenalty + 1e-9;
    return { c: Math.max(bestCost, 0), p: best };
  }

  function pushEdge(u, v) {
    const key = edgeKey(u, v);
    const ver = (version.get(key) || 0) + 1;
    version.set(key, ver);
    const { c, p } = edgeCost(u, v);
    heap.push({ c, u, v, ver, key, p });
  }
  function pushAround(u) {
    const seen = new Set();
    for (const f of vfaces[u]) {
      if (!faceAlive[f]) continue;
      for (let k = 0; k < 3; k++) {
        const w = F[f * 3 + k];
        if (w !== u && !seen.has(w)) { seen.add(w); pushEdge(u, w); }
      }
    }
  }
  for (let f = 0; f < m; f++) {
    const a = F[f * 3], b = F[f * 3 + 1], c = F[f * 3 + 2];
    for (const [u, v] of [[a, b], [b, c], [c, a]]) {
      const key = edgeKey(u, v);
      if (!version.has(key)) pushEdge(u, v);
    }
  }
  let faces = m;
  const neighbours = (u) => {
    const s = new Set();
    for (const f of vfaces[u]) if (faceAlive[f]) for (let k = 0; k < 3; k++) if (F[f * 3 + k] !== u) s.add(F[f * 3 + k]);
    return s;
  };
  const tmpPos = new Float64Array(3);
  while (faces > targetTris && heap.size > 0) {
    const e = heap.pop();
    if (version.get(e.key) !== e.ver) continue;
    const u = e.u, v = e.v;
    if (!alive[u] || !alive[v]) continue;
    // edge must still exist and satisfy the link condition
    const nu = neighbours(u), nv = neighbours(v);
    if (!nu.has(v)) continue;
    let common = 0;
    for (const w of nu) if (nv.has(w)) common++;
    if (common !== 2) continue;
    // flip test: faces around u and v that survive, evaluated at the new position
    const np = e.p;
    let flip = false;
    const check = (vert) => {
      for (const f of vfaces[vert]) {
        if (!faceAlive[f]) continue;
        const a = F[f * 3], b = F[f * 3 + 1], c = F[f * 3 + 2];
        if ((a === u || b === u || c === u) && (a === v || b === v || c === v)) continue;
        const before = faceNormal(f, P);
        const save = [P[vert * 3], P[vert * 3 + 1], P[vert * 3 + 2]];
        P[vert * 3] = np[0]; P[vert * 3 + 1] = np[1]; P[vert * 3 + 2] = np[2];
        const after = faceNormal(f, P);
        P[vert * 3] = save[0]; P[vert * 3 + 1] = save[1]; P[vert * 3 + 2] = save[2];
        const lb = Math.hypot(before[0], before[1], before[2]), la = Math.hypot(after[0], after[1], after[2]);
        if (la < 1e-14 || (before[0] * after[0] + before[1] * after[1] + before[2] * after[2]) / (lb * la) < 0.2) { flip = true; return; }
      }
    };
    check(u); if (!flip) check(v);
    if (flip) continue;
    // collapse v into u
    P[u * 3] = np[0]; P[u * 3 + 1] = np[1]; P[u * 3 + 2] = np[2];
    if (zones[u] !== zones[v]) {
      // keep the zone of whichever endpoint the new position coincides with
      const du = Math.hypot(np[0] - P[v * 3], np[1] - P[v * 3 + 1], np[2] - P[v * 3 + 2]);
      if (du < 1e-12) zones[u] = zones[v];
    }
    for (let k = 0; k < 10; k++) Q[u * 10 + k] += Q[v * 10 + k];
    for (const f of vfaces[v]) {
      if (!faceAlive[f]) continue;
      const a = F[f * 3], b = F[f * 3 + 1], c = F[f * 3 + 2];
      if (a === u || b === u || c === u) { faceAlive[f] = 0; faces--; continue; }
      for (let k = 0; k < 3; k++) if (F[f * 3 + k] === v) F[f * 3 + k] = u;
      vfaces[u].push(f);
    }
    alive[v] = 0;
    vfaces[v] = [];
    // drop dead faces from u's list
    vfaces[u] = vfaces[u].filter((f) => faceAlive[f]);
    pushAround(u);
  }
  // compact
  const remap = new Int32Array(n).fill(-1);
  const outPos = [];
  const outZone = [];
  let nv = 0;
  for (let i = 0; i < n; i++) {
    if (!alive[i]) continue;
    remap[i] = nv++;
    outPos.push(P[i * 3], P[i * 3 + 1], P[i * 3 + 2]);
    outZone.push(zones[i]);
  }
  const outTris = [];
  for (let f = 0; f < m; f++) {
    if (!faceAlive[f]) continue;
    const a = remap[F[f * 3]], b = remap[F[f * 3 + 1]], c = remap[F[f * 3 + 2]];
    if (a === b || b === c || a === c) continue;
    outTris.push(a, b, c);
  }
  return { positions: Float64Array.from(outPos), tris: Int32Array.from(outTris), zones: Int32Array.from(outZone) };
}

module.exports = { decimate };
