'use strict';
// Deterministic pseudo-random numbers (xoshiro128**) so every render is reproducible.
// Seeds are derived from strings (asset id + variant) with FNV-1a, never from the clock.

function fnv1a(str) {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

class Rng {
  constructor(seed) {
    if (typeof seed === 'string') seed = fnv1a(seed);
    seed = (seed >>> 0) || 0x9e3779b9;
    // splitmix32 to spread the seed over 4 words
    const sm = () => {
      seed = (seed + 0x9e3779b9) >>> 0;
      let z = seed;
      z = Math.imul(z ^ (z >>> 16), 0x85ebca6b) >>> 0;
      z = Math.imul(z ^ (z >>> 13), 0xc2b2ae35) >>> 0;
      return (z ^ (z >>> 16)) >>> 0;
    };
    this.s0 = sm(); this.s1 = sm(); this.s2 = sm(); this.s3 = sm();
    if ((this.s0 | this.s1 | this.s2 | this.s3) === 0) this.s0 = 1;
  }
  next() { // uint32
    const result = Math.imul(rotl(Math.imul(this.s1, 5) >>> 0, 7), 9) >>> 0;
    const t = (this.s1 << 9) >>> 0;
    this.s2 ^= this.s0; this.s3 ^= this.s1; this.s1 ^= this.s2; this.s0 ^= this.s3;
    this.s2 ^= t; this.s3 = rotl(this.s3, 11);
    return result;
  }
  float() { return this.next() / 4294967296; }          // [0,1)
  range(a, b) { return a + (b - a) * this.float(); }
  int(n) { return Math.floor(this.float() * n); }
  pick(arr) { return arr[this.int(arr.length)]; }
  sign() { return this.float() < 0.5 ? -1 : 1; }
  gauss() { // Box-Muller, mean 0 sd 1
    let u = 0, v = 0;
    while (u === 0) u = this.float();
    while (v === 0) v = this.float();
    return Math.sqrt(-2.0 * Math.log(u)) * Math.cos(2.0 * Math.PI * v);
  }
  bool(p = 0.5) { return this.float() < p; }
  fork(tag) { return new Rng((this.next() ^ fnv1a(String(tag))) >>> 0); }
}

function rotl(x, k) { return ((x << k) | (x >>> (32 - k))) >>> 0; }

module.exports = { Rng, fnv1a };
