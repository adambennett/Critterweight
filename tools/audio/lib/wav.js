'use strict';
// 16-bit PCM WAV writer/reader (RIFF). Optional `smpl` chunk carries loop points for tools that
// read them; Godot gets its loop points from the generated .import file instead.

const fs = require('fs');
const path = require('path');
const { isStereo } = require('./dsp');

/** Encodes a mono Float64Array or stereo {l, r} into a WAV Buffer (16-bit PCM, TPDF dither). */
function encode(buf, sr, { loop = null, dither = true } = {}) {
  const st = isStereo(buf);
  const chans = st ? 2 : 1;
  const n = st ? buf.l.length : buf.length;
  const dataBytes = n * chans * 2;
  const smpl = loop ? 36 + 24 + 8 : 0; // smpl chunk (header + one loop)
  const out = Buffer.alloc(44 + dataBytes + smpl);
  out.write('RIFF', 0);
  out.writeUInt32LE(36 + dataBytes + smpl, 4);
  out.write('WAVE', 8);
  out.write('fmt ', 12);
  out.writeUInt32LE(16, 16);
  out.writeUInt16LE(1, 20);
  out.writeUInt16LE(chans, 22);
  out.writeUInt32LE(sr, 24);
  out.writeUInt32LE(sr * chans * 2, 28);
  out.writeUInt16LE(chans * 2, 32);
  out.writeUInt16LE(16, 34);
  out.write('data', 36);
  out.writeUInt32LE(dataBytes, 40);
  let o = 44;
  // deterministic TPDF dither from a tiny LCG so re-renders are byte-identical
  let seed = 0x1234567;
  const rnd = () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed / 4294967296; };
  const q = (v) => {
    let x = v * 32767;
    if (dither) x += (rnd() - rnd()) * 0.8;
    x = Math.round(x);
    return x > 32767 ? 32767 : x < -32768 ? -32768 : x;
  };
  if (st) {
    for (let i = 0; i < n; i++) { out.writeInt16LE(q(buf.l[i]), o); out.writeInt16LE(q(buf.r[i]), o + 2); o += 4; }
  } else {
    for (let i = 0; i < n; i++) { out.writeInt16LE(q(buf[i]), o); o += 2; }
  }
  if (loop) {
    out.write('smpl', o); out.writeUInt32LE(36 + 24, o + 4); o += 8;
    out.writeUInt32LE(0, o); out.writeUInt32LE(0, o + 4); out.writeUInt32LE(Math.round(1e9 / sr), o + 8);
    out.writeUInt32LE(60, o + 12); out.writeUInt32LE(0, o + 16); out.writeUInt32LE(0, o + 20);
    out.writeUInt32LE(0, o + 24); out.writeUInt32LE(0, o + 28); out.writeUInt32LE(1, o + 32); out.writeUInt32LE(0, o + 36);
    o += 36;
    out.writeUInt32LE(0, o); out.writeUInt32LE(0, o + 4); out.writeUInt32LE(loop.begin, o + 8);
    out.writeUInt32LE(loop.end - 1, o + 12); out.writeUInt32LE(0, o + 16); out.writeUInt32LE(0, o + 20);
  }
  return out;
}

function write(file, buf, sr, opts) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const data = encode(buf, sr, opts);
  fs.writeFileSync(file, data);
  return data;
}

/** Reads a 16-bit PCM WAV into {sr, channels, data: [Float64Array...]} */
function read(file) {
  const b = fs.readFileSync(file);
  if (b.toString('ascii', 0, 4) !== 'RIFF' || b.toString('ascii', 8, 12) !== 'WAVE') throw new Error('not a WAV: ' + file);
  let o = 12, sr = 0, chans = 0, bits = 0, data = null;
  while (o + 8 <= b.length) {
    const id = b.toString('ascii', o, o + 4);
    const size = b.readUInt32LE(o + 4);
    if (id === 'fmt ') { chans = b.readUInt16LE(o + 10); sr = b.readUInt32LE(o + 12); bits = b.readUInt16LE(o + 22); }
    else if (id === 'data') { data = b.subarray(o + 8, o + 8 + size); }
    o += 8 + size + (size & 1);
  }
  if (!data || bits !== 16) throw new Error('unsupported WAV: ' + file);
  const n = data.length / (2 * chans);
  const out = [];
  for (let c = 0; c < chans; c++) out.push(new Float64Array(n));
  for (let i = 0; i < n; i++) for (let c = 0; c < chans; c++) out[c][i] = data.readInt16LE((i * chans + c) * 2) / 32768;
  return { sr, channels: chans, data: out, frames: n };
}

module.exports = { encode, write, read };
