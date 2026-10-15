'use strict';
// Pattern sequencer ("tracker") for the music scores in tools/audio/scores/*.js.
//
// A song = { id, bpm, sr, stereo, steps, swing, sections: [...arrangement], bars: {name: n},
//            loop: {startBar, endBar} (1-based inclusive), tracks: [...], master: {...}, layers: [...] }
// A track = { name, inst, params, gain (dB), pan (-1..1), send (0..1 to the master reverb), octave,
//             transpose, humanize, gate (0..1 step fraction), fx: [...], patterns: {section: bars} }
// Pattern bars are strings of whitespace-separated step tokens (or compact per-character drum
// strings such as "x..x..x." ):
//   .            rest                      -           tie: extend the previous note by a step
//   c3 eb4 f#2   note (optionally c3+eb3+g3 chord)      x X o r   drum hit / accent / soft / roll
//   suffixes     :v velocity (1-9 or 0.0-1.0)   *n gate length in steps   ~ glide from the previous note
// The renderer folds the tail of the loop region back into the loop start so loops are seamless,
// measures loudness, normalizes to the master target and limits to the ceiling.

const D = require('./dsp');
const INST = require('./instruments');
const { Rng } = require('./rng');

const NOTE_RE = /^([a-gA-G])([#b]?)(-?\d)(~?)(?::([0-9.]+))?(?:\*(\d+))?$/;
const SEMI = { c: 0, d: 2, e: 4, f: 5, g: 7, a: 9, b: 11 };

function noteFreq(name, acc, oct, transpose = 0) {
  let n = SEMI[name.toLowerCase()] + (acc === '#' ? 1 : acc === 'b' ? -1 : 0) + (parseInt(oct, 10) + 1) * 12;
  n += transpose;
  return 440 * Math.pow(2, (n - 69) / 12);
}

function parseVel(v, def = 0.8) {
  if (v === undefined) return def;
  if (v.includes('.')) return D.clamp(parseFloat(v), 0, 1.2);
  const i = parseInt(v, 10);
  return i <= 1 && !v.includes('.') && v.length === 1 && i === 1 ? 1 / 9 : D.clamp(i / 9, 0, 1.2);
}

/** Parses "1/8d" style divisions into seconds. */
function division(spec, bpm) {
  if (typeof spec === 'number') return spec;
  const m = /^(\d+)\/(\d+)([dt]?)$/.exec(spec);
  if (!m) throw new Error('bad division ' + spec);
  let beats = (4 * parseInt(m[1], 10)) / parseInt(m[2], 10);
  if (m[3] === 'd') beats *= 1.5;
  if (m[3] === 't') beats *= 2 / 3;
  return (beats * 60) / bpm;
}

function tokenizeBar(bar) {
  const s = String(bar).trim();
  if (!s.includes(' ') && /^[xXo.r?\-]+$/.test(s)) return s.split('');
  return s.split(/\s+/).filter((t) => t.length);
}

/** Builds note events for one track across the arrangement. */
function trackEvents(song, track, rng) {
  const bpm = song.bpm, bpb = song.beatsPerBar || 4;
  const barLen = (60 / bpm) * bpb;
  const events = [];
  const transpose = (song.transpose || 0) + (track.transpose || 0) + (track.octave || 0) * 12;
  const gate = track.gate === undefined ? 0.85 : track.gate;
  const swing = track.swing === undefined ? song.swing || 0 : track.swing;
  const humanize = track.humanize || 0;
  let barIndex = 0;
  let lastFreq = 0;
  const arrangement = song.sections;
  for (let si = 0; si < arrangement.length; si++) {
    const sec = arrangement[si];
    const nbars = song.bars[sec];
    if (nbars === undefined) throw new Error(`song ${song.id}: section ${sec} has no bar count`);
    let pat = track.patterns ? track.patterns[sec] : undefined;
    if (pat === undefined && track.patterns && track.patterns['*']) pat = track.patterns['*'];
    for (let b = 0; b < nbars; b++, barIndex++) {
      if (pat === undefined || pat === null) continue;
      let barStr;
      if (typeof pat === 'function') barStr = pat(b, sec, { bar: barIndex, song, rng, nbars });
      else if (Array.isArray(pat)) barStr = pat[b % pat.length];
      else barStr = pat;
      if (!barStr) continue;
      if (typeof barStr === 'function') barStr = barStr(b, sec);
      const tokens = tokenizeBar(barStr);
      const stepLen = barLen / tokens.length;
      const barStart = barIndex * barLen;
      let lastGroup = null;
      for (let k = 0; k < tokens.length; k++) {
        const tok = tokens[k];
        if (tok === '.') { lastGroup = null; continue; }
        if (tok === '-') { if (lastGroup) for (const e of lastGroup) e.dur += stepLen; continue; }
        let t = barStart + k * stepLen;
        if (swing > 0 && tokens.length >= 8 && k % 2 === 1) t += (stepLen * swing) / 3;
        if (humanize > 0) t += rng.range(-1, 1) * humanize * 0.006;
        if (t < 0) t = 0;
        const velJitter = humanize > 0 ? 1 + rng.range(-1, 1) * humanize * 0.08 : 1;
        // drums
        if (/^[xXor](\?)?(:[0-9.]+)?$/.test(tok)) {
          const m = /^([xXor])(\?)?(?::([0-9.]+))?$/.exec(tok);
          if (m[2] && rng.float() < 0.5) { lastGroup = null; continue; }
          let vel = m[1] === 'X' ? 1.0 : m[1] === 'o' ? 0.5 : 0.85;
          if (m[3] !== undefined) vel = parseVel(m[3], vel);
          vel *= velJitter;
          if (m[1] === 'r') {
            const group = [];
            for (let j = 0; j < 4; j++) {
              const e = { t: t + (j * stepLen) / 4, dur: stepLen / 4, freq: 0, vel: vel * (0.6 + 0.4 * (j / 3)), glideFrom: 0 };
              events.push(e); group.push(e);
            }
            lastGroup = group;
          } else {
            const e = { t, dur: stepLen * gate, freq: 0, vel, glideFrom: 0 };
            events.push(e); lastGroup = [e];
          }
          continue;
        }
        // notes / chords: a trailing ":vel" / "*len" suffix applies to every note of a chord
        const sm = /^(.*?)((?::[0-9.]+)?(?:\*\d+)?)$/.exec(tok);
        const suffix = sm[2] || '';
        const parts = sm[1].split('+');
        const group = [];
        for (const part of parts) {
          const m = NOTE_RE.exec(part + suffix);
          if (!m) throw new Error(`song ${song.id} track ${track.name}: bad token '${tok}' in section ${sec}`);
          const freq = noteFreq(m[1], m[2], m[3], transpose);
          const len = m[6] ? parseInt(m[6], 10) : 1;
          const vel = parseVel(m[5], track.vel === undefined ? 0.8 : track.vel) * velJitter;
          const e = { t, dur: stepLen * len * gate, freq, vel, glideFrom: m[4] === '~' ? lastFreq : 0 };
          events.push(e); group.push(e);
        }
        lastFreq = group[0].freq;
        lastGroup = group;
      }
    }
  }
  return events;
}

// ---------------------------------------------------------------------------------------
// FX chain
// ---------------------------------------------------------------------------------------

function applyFx(buf, fxList, sr, song, ctx) {
  let b = buf;
  for (const fx of fxList || []) {
    switch (fx.type) {
      case 'hp': D.filterBuf(b, sr, 'highpass', fx.f, fx.q || 0.707); break;
      case 'lp': D.filterBuf(b, sr, 'lowpass', fx.f, fx.q || 0.707); break;
      case 'bp': D.filterBuf(b, sr, 'bandpass', fx.f, fx.q || 1); break;
      case 'eq': D.filterBuf(b, sr, 'peaking', fx.f, fx.q || 1, fx.gain || 0); break;
      case 'shelf': D.filterBuf(b, sr, fx.kind === 'high' ? 'highshelf' : 'lowshelf', fx.f, fx.q || 0.707, fx.gain || 0); break;
      case 'sat': D.saturate(b, fx.drive || 2, fx.mode || 'tanh', fx.mix === undefined ? 1 : fx.mix); break;
      case 'crush': D.bitcrush(b, fx.bits || 8, fx.down || 1); break;
      case 'gain': D.applyGain(b, D.db(fx.db || 0)); break;
      case 'chorus': b = D.chorus(b, sr, fx); break;
      case 'delay': b = D.delayFx(b, sr, Object.assign({}, fx, { time: division(fx.time || '1/8', song.bpm) })); break;
      case 'reverb': b = D.reverb(b, sr, fx); break;
      case 'comp': D.compressor(b, sr, fx); break;
      case 'trem': {
        const lfo = new D.Lfo(sr, fx.shape || 'sine');
        const depth = fx.depth === undefined ? 0.5 : fx.depth;
        const apply = (ch) => { for (let i = 0; i < ch.length; i++) ch[i] *= 1 - depth * 0.5 * (1 + lfo.next(fx.rate || 4)); };
        if (D.isStereo(b)) { const l2 = new D.Lfo(sr); const save = lfo.phase; apply(b.l); lfo.phase = save; apply(b.r); void l2; } else apply(b);
        break;
      }
      case 'autopan': {
        b = D.toStereo(b);
        const lfo = new D.Lfo(sr, 'sine', fx.phase || 0);
        const depth = fx.depth === undefined ? 0.6 : fx.depth;
        for (let i = 0; i < b.l.length; i++) {
          const p = lfo.next(fx.rate || 0.5) * depth;
          const a = ((p + 1) * Math.PI) / 4;
          const m = (b.l[i] + b.r[i]) * 0.5;
          b.l[i] = m * Math.cos(a) * 1.41; b.r[i] = m * Math.sin(a) * 1.41;
        }
        break;
      }
      case 'filterLfo': {
        const apply = (ch, phase) => {
          const f = new D.SVF(sr, fx.f || 1000, fx.q || 1);
          const lfo = new D.Lfo(sr, fx.shape || 'sine', phase);
          for (let i = 0; i < ch.length; i++) {
            f.set((fx.f || 1000) * Math.pow(2, lfo.next(fx.rate || 0.25) * (fx.depth || 1)), fx.q || 1);
            ch[i] = fx.mode === 'hp' ? f.hp(ch[i]) : fx.mode === 'bp' ? f.bp(ch[i]) : f.lp(ch[i]);
          }
        };
        if (D.isStereo(b)) { apply(b.l, 0); apply(b.r, 0); } else apply(b, 0);
        break;
      }
      case 'sidechain': {
        const src = ctx.events[fx.source];
        if (!src) break;
        const amount = fx.amount === undefined ? 0.5 : fx.amount;
        const rel = fx.release || 0.18;
        const env = new Float64Array(D.length(b)).fill(1);
        for (const e of src) {
          const s = Math.round(e.t * sr);
          const n = Math.round(rel * sr);
          for (let i = 0; i < n && s + i < env.length; i++) {
            const g = 1 - amount * (1 - i / n) * (1 - i / n);
            if (g < env[s + i]) env[s + i] = g;
          }
        }
        D.multiply(b, env);
        break;
      }
      case 'fade': D.fade(b, sr, fx.in || 0, fx.out || 0); break;
      default: throw new Error('unknown fx ' + fx.type);
    }
  }
  return b;
}

// ---------------------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------------------

function renderTrack(song, track, sr, totalSamples, tailSamples, rng, cache, ctx, log) {
  const inst = INST.make(track.inst, track.params);
  const events = ctx.events[track.name];
  const mono = D.zeros(totalSamples + tailSamples);
  let rendered = 0, cached = 0;
  for (const e of events) {
    const key = `${track.inst}|${JSON.stringify(track.params || {})}|${e.freq.toFixed(2)}|${e.dur.toFixed(3)}|${e.vel.toFixed(2)}|${e.glideFrom.toFixed(1)}`;
    let buf = cache.get(key);
    if (!buf) {
      buf = inst.render(e, sr, rng.fork(key));
      cache.set(key, buf);
      rendered++;
    } else cached++;
    D.mixInto(mono, buf, 1, e.t * sr);
  }
  let out = applyFx(mono, track.fx, sr, song, ctx);
  const gain = D.db(track.gain || 0);
  if (!D.isStereo(out)) out = D.pan(out, track.pan || 0);
  else if (track.pan) { // balance on an already-stereo track
    const a = ((track.pan + 1) * Math.PI) / 4;
    D.applyGain(out.l, Math.cos(a) * 1.414); D.applyGain(out.r, Math.sin(a) * 1.414);
  }
  D.applyGain(out, gain);
  if (log) log(`    ${track.name.padEnd(14)} ${String(events.length).padStart(5)} notes (${rendered} rendered, ${cached} cached) peak ${D.peakDb(out).toFixed(1)} dB`);
  return out;
}

function sumMix(stems, n, sends, sr, song) {
  const mix = D.stereo(n);
  const sendBus = D.stereo(n);
  let anySend = false;
  for (const s of stems) {
    D.mixInto(mix, s.buf, 1, 0);
    if (s.send > 0) { D.mixInto(sendBus, s.buf, s.send, 0); anySend = true; }
  }
  const rv = (song.master && song.master.reverb) || {};
  if (anySend && sends !== false) {
    const wet = D.reverb(sendBus, sr, Object.assign({ size: 0.55, damp: 0.4, predelay: 0.02, lowcut: 180 }, rv, { mix: 1 }));
    D.mixInto(mix, wet, rv.level === undefined ? 1 : rv.level, 0);
  }
  return mix;
}

function foldLoop(buf, loopBegin, loopEnd, tailSamples) {
  // adds whatever rings past loopEnd back onto the loop start, then truncates
  const st = D.isStereo(buf);
  const chans = st ? [buf.l, buf.r] : [buf];
  for (const ch of chans) {
    const n = Math.min(tailSamples, ch.length - loopEnd);
    for (let i = 0; i < n; i++) {
      const dst = loopBegin + i;
      if (dst < loopEnd) ch[dst] += ch[loopEnd + i];
    }
  }
}

function finalizeMix(buf, sr, totalSamples, loop, tailSamples, master) {
  if (loop) foldLoop(buf, loop.begin, loop.end, tailSamples);
  const keep = loop ? totalSamples : totalSamples + tailSamples; // one-shots keep their ring-out
  const cut = (ch) => ch.slice(0, keep);
  let out = D.isStereo(buf) ? { l: cut(buf.l), r: cut(buf.r) } : cut(buf);
  if (!loop) D.fade(out, sr, 0, 0.4);
  D.dcBlock(out, sr);
  if (master.hp) D.filterBuf(out, sr, 'highpass', master.hp, 0.707);
  for (const eq of master.eq || []) D.filterBuf(out, sr, 'peaking', eq.f, eq.q || 1, eq.gain || 0);
  if (master.width && master.width !== 1 && D.isStereo(out)) D.widen(out, master.width);
  if (master.comp) D.compressor(out, sr, master.comp);
  return out;
}

/**
 * Renders a song. Returns { base: {buf, sr}, layers: [{id, buf, sr, loop, bars}], loop, meta, stats }.
 * opts.log: function(line) for progress.
 */
function renderSong(song, opts = {}) {
  const log = opts.log || (() => {});
  const sr = song.sr || 44100;
  const rng = new Rng(song.seed || song.id);
  const bpb = song.beatsPerBar || 4;
  const barLen = (60 / song.bpm) * bpb;
  let totalBars = 0;
  const sectionTable = [];
  for (const sec of song.sections) { sectionTable.push({ id: sec, startBar: totalBars + 1, bars: song.bars[sec] }); totalBars += song.bars[sec]; }
  const totalSamples = Math.round(totalBars * barLen * sr);
  const tailSec = song.tail === undefined ? 4 : song.tail;
  const tailSamples = Math.round(tailSec * sr);
  let loop = null;
  if (song.loop) {
    const sb = song.loop.startBar, eb = song.loop.endBar;
    loop = { begin: Math.round((sb - 1) * barLen * sr), end: Math.round(eb * barLen * sr), startBar: sb, endBar: eb };
    if (loop.end > totalSamples) loop.end = totalSamples;
  }
  const master = Object.assign({ hp: 28, lufs: -15, ceiling: -1 }, song.master || {});
  log(`  ${song.id}: ${song.bpm} bpm, ${totalBars} bars, ${(totalSamples / sr).toFixed(1)} s${loop ? `, loop bars ${loop.startBar}-${loop.endBar}` : ''}`);

  // events for every track (needed before rendering for sidechains)
  const ctx = { events: {} };
  for (const t of song.tracks) ctx.events[t.name] = trackEvents(song, t, rng.fork('ev:' + t.name));

  // which tracks belong to layers
  const layerOf = {};
  for (const L of song.layers || []) for (const tn of L.tracks) layerOf[tn] = L.id;

  const cache = new Map();
  const stems = [];
  for (const t of song.tracks) {
    if (t.mute) continue;
    const buf = renderTrack(song, t, sr, totalSamples, tailSamples, rng.fork('tr:' + t.name), cache, ctx, log);
    stems.push({ name: t.name, buf, send: t.send || 0, layer: layerOf[t.name] || null });
  }
  const n = totalSamples + tailSamples;
  const baseStems = stems.filter((s) => !s.layer);
  const baseMix = sumMix(baseStems, n, true, sr, song);
  const layerMixes = [];
  for (const L of song.layers || []) {
    const ls = stems.filter((s) => s.layer === L.id);
    layerMixes.push({ def: L, buf: sumMix(ls, n, true, sr, song) });
  }
  // loudness normalization computed on the full mix (base + full-length layers)
  const full = D.stereo(n);
  D.mixInto(full, baseMix, 1, 0);
  for (const lm of layerMixes) if (!lm.def.loopBars) D.mixInto(full, lm.buf, 1, 0);
  const fullFinal = finalizeMix(full, sr, totalSamples, loop, tailSamples, master);
  const measured = D.lufs(fullFinal, sr);
  const gainDb = (master.lufs === null ? 0 : master.lufs - measured) + (master.gain || 0);
  log(`    full mix ${measured.toFixed(1)} LUFS -> gain ${gainDb >= 0 ? '+' : ''}${gainDb.toFixed(1)} dB`);

  const finish = (mix, lp, tailS, isBase) => {
    let out = finalizeMix(mix, sr, lp ? lp.total : totalSamples, lp ? lp.loop : loop, tailS, isBase ? master : Object.assign({}, master, { comp: null }));
    D.applyGain(out, D.db(gainDb));
    const pre = D.peakDb(out);
    D.limiter(out, sr, { ceiling: master.ceiling, release: 0.1, lookahead: 0.005 });
    return { out, pre };
  };
  const base = finish(baseMix, null, tailSamples, true);
  const result = {
    base: { buf: song.stereo === false ? toMono(base.out) : base.out, sr },
    layers: [],
    loop,
    meta: { bpm: song.bpm, beatsPerBar: bpb, bars: totalBars, barSeconds: barLen, seconds: totalSamples / sr, sections: sectionTable, loopBars: loop ? { start: loop.startBar, end: loop.endBar } : null },
    stats: { lufsFull: measured, gainDb, basePeakPreLimit: base.pre },
  };
  for (const lm of layerMixes) {
    const L = lm.def;
    let buf = lm.buf;
    let lp = null;
    let tailS = tailSamples;
    if (L.loopBars) { // a short loop that stays phase-locked with the base (loopBars divides every section)
      const ls = Math.round(L.loopBars * barLen * sr);
      lp = { total: ls, loop: { begin: 0, end: ls } };
    }
    const f = finish(buf, lp, tailS, false);
    let outBuf = f.out;
    const lsr = L.sr || sr;
    if (L.mono) outBuf = toMono(outBuf);
    if (lsr !== sr) outBuf = D.isStereo(outBuf) ? { l: D.resample(outBuf.l, lsr / sr), r: D.resample(outBuf.r, lsr / sr) } : D.resample(outBuf, lsr / sr);
    const lloop = lp ? { begin: 0, end: D.length(outBuf), startBar: 1, endBar: L.loopBars } : loop ? { begin: Math.round(loop.begin * lsr / sr), end: Math.round(loop.end * lsr / sr), startBar: loop.startBar, endBar: loop.endBar } : null;
    if (lsr !== sr && lloop && !lp) lloop.end = Math.min(lloop.end, D.length(outBuf));
    result.layers.push({ id: L.id, buf: outBuf, sr: lsr, loop: lloop, bars: L.loopBars || totalBars, defaultDb: L.defaultDb === undefined ? 0 : L.defaultDb, kind: L.kind || 'layer' });
  }
  return result;
}

function toMono(st) {
  if (!D.isStereo(st)) return st;
  const out = D.zeros(st.l.length);
  for (let i = 0; i < out.length; i++) out[i] = (st.l[i] + st.r[i]) * 0.5;
  return out;
}

module.exports = { renderSong, trackEvents, division, noteFreq, tokenizeBar, toMono };
