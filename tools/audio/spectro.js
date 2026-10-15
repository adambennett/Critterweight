#!/usr/bin/env node
'use strict';
// Renders a spectrogram + waveform PNG of a WAV (or several, stacked) for visual verification.
// Usage: node tools/audio/spectro.js <in.wav> [more.wav...] --out <file.png> [--seconds 20] [--from 0] [--width 1400] [--height 240]
// No dependencies: PNG is written with Node's zlib.

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const WAV = require('./lib/wav');

const args = process.argv.slice(2);
const val = (f, d) => { const i = args.indexOf(f); return i >= 0 ? args[i + 1] : d; };
const inputs = args.filter((a, i) => !a.startsWith('--') && (i === 0 || !args[i - 1].startsWith('--')));
const out = val('--out', 'spectro.png');
const WIDTH = parseInt(val('--width', '1400'), 10);
const H = parseInt(val('--height', '240'), 10);
const SECONDS = parseFloat(val('--seconds', '0'));
const FROM = parseFloat(val('--from', '0'));
const N = 1024;

function fft(re, im) { // in-place radix-2
  const n = re.length;
  for (let i = 1, j = 0; i < n; i++) {
    let bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) { [re[i], re[j]] = [re[j], re[i]]; [im[i], im[j]] = [im[j], im[i]]; }
  }
  for (let len = 2; len <= n; len <<= 1) {
    const ang = -2 * Math.PI / len;
    const wr = Math.cos(ang), wi = Math.sin(ang);
    for (let i = 0; i < n; i += len) {
      let cr = 1, ci = 0;
      for (let k = 0; k < len / 2; k++) {
        const ur = re[i + k], ui = im[i + k];
        const vr = re[i + k + len / 2] * cr - im[i + k + len / 2] * ci;
        const vi = re[i + k + len / 2] * ci + im[i + k + len / 2] * cr;
        re[i + k] = ur + vr; im[i + k] = ui + vi; re[i + k + len / 2] = ur - vr; im[i + k + len / 2] = ui - vi;
        const nr = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = nr;
      }
    }
  }
}

function crc32(buf) {
  let c, crc = 0xffffffff;
  for (let n = 0; n < buf.length; n++) {
    c = (crc ^ buf[n]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc = (crc >>> 8) ^ c;
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function png(width, height, rgb) {
  const raw = Buffer.alloc((width * 3 + 1) * height);
  for (let y = 0; y < height; y++) { raw[y * (width * 3 + 1)] = 0; rgb.copy(raw, y * (width * 3 + 1) + 1, y * width * 3, (y + 1) * width * 3); }
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(width, 0); ihdr.writeUInt32BE(height, 4); ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}

function color(v) { // 0..1 -> inferno-ish
  const stops = [[0, 0, 4], [40, 11, 84], [101, 21, 110], [159, 42, 99], [212, 72, 66], [245, 125, 21], [250, 193, 39], [252, 255, 164]];
  const x = Math.max(0, Math.min(1, v)) * (stops.length - 1);
  const i = Math.min(stops.length - 2, Math.floor(x)), f = x - i;
  return [0, 1, 2].map((c) => Math.round(stops[i][c] + (stops[i + 1][c] - stops[i][c]) * f));
}

const panels = [];
for (const file of inputs) {
  const w = WAV.read(file);
  const mono = new Float64Array(w.frames);
  for (let i = 0; i < w.frames; i++) { let s = 0; for (const ch of w.data) s += ch[i]; mono[i] = s / w.data.length; }
  const start = Math.round(FROM * w.sr);
  const len = SECONDS > 0 ? Math.min(mono.length - start, Math.round(SECONDS * w.sr)) : mono.length - start;
  const specH = H - 50;
  const img = Buffer.alloc(WIDTH * H * 3);
  const hop = Math.max(1, Math.floor(len / WIDTH));
  const win = new Float64Array(N);
  for (let i = 0; i < N; i++) win[i] = 0.5 - 0.5 * Math.cos(2 * Math.PI * i / N);
  const re = new Float64Array(N), im = new Float64Array(N);
  const maxF = Math.min(w.sr / 2, 16000);
  for (let x = 0; x < WIDTH; x++) {
    const pos = start + x * hop;
    for (let i = 0; i < N; i++) { const s = pos + i < mono.length ? mono[pos + i] : 0; re[i] = s * win[i]; im[i] = 0; }
    fft(re, im);
    for (let y = 0; y < specH; y++) {
      // log frequency axis from 30 Hz to maxF
      const fy = 30 * Math.pow(maxF / 30, 1 - y / specH);
      const bin = Math.min(N / 2 - 1, Math.round(fy / (w.sr / N)));
      const mag = Math.sqrt(re[bin] * re[bin] + im[bin] * im[bin]) / (N / 4);
      const db = 20 * Math.log10(mag + 1e-9);
      const v = (db + 72) / 72;
      const [r, g, b] = color(v);
      const o = (y * WIDTH + x) * 3;
      img[o] = r; img[o + 1] = g; img[o + 2] = b;
    }
    // waveform strip
    let pk = 0;
    for (let i = 0; i < hop && pos + i < mono.length; i++) pk = Math.max(pk, Math.abs(mono[pos + i]));
    const wy0 = specH + 25, amp = Math.round(pk * 24);
    for (let y = specH; y < H; y++) { const o = (y * WIDTH + x) * 3; img[o] = 20; img[o + 1] = 20; img[o + 2] = 28; }
    for (let y = wy0 - amp; y <= wy0 + amp; y++) { const o = (y * WIDTH + x) * 3; img[o] = pk > 0.89 ? 255 : 90; img[o + 1] = pk > 0.89 ? 60 : 200; img[o + 2] = 120; }
  }
  // second markers every 5 s on the waveform strip (and loop markers if given)
  const secPx = (w.sr / hop);
  for (let s = 0; s * secPx < WIDTH; s += 5) { const x = Math.round(s * secPx); for (let y = specH; y < specH + 6; y++) { const o = (y * WIDTH + x) * 3; img[o] = 255; img[o + 1] = 255; img[o + 2] = 255; } }
  panels.push({ img, file, sr: w.sr, seconds: len / w.sr });
  console.log(`${path.basename(file)}: ${w.sr} Hz, ${w.channels} ch, ${(w.frames / w.sr).toFixed(2)} s shown ${(len / w.sr).toFixed(2)} s from ${FROM} s (${hop} samples/px)`);
}
const total = Buffer.concat(panels.map((p) => p.img));
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, png(WIDTH, H * panels.length, total));
console.log('wrote', out);
