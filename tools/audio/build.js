#!/usr/bin/env node
'use strict';
// CRITTERWEIGHT audio build. Renders every music track, sound effect, creature voice, crowd and
// ambience bed and announcer grain bank from the editable sources in this folder into
// game/assets/audio/ (16-bit WAV + Godot .import files set to QOA), plus:
//   game/assets/audio/bank.json      runtime bank read by the Audio autoload (ids -> files/params)
//   game/assets/audio/manifest.json  per-file sha256/peak/loudness used by the headless audio tests
//   tools/audio/report.md            human-readable showcase report
//
// Usage:  node tools/audio/build.js [--only <substring>] [--music] [--sfx] [--voice] [--clean]
//         node tools/audio/build.js --say "Text to babble" [--speaker barnaby|granny] [--out file.wav]
//         node tools/audio/build.js --check          (re-render everything in memory, compare hashes)
// Everything is deterministic: a rebuild reproduces byte-identical files.

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const D = require('./lib/dsp');
const WAV = require('./lib/wav');
const { Rng } = require('./lib/rng');
const SEQ = require('./lib/sequencer');
const BABBLE = require('./lib/babble');

const ROOT = path.resolve(__dirname, '..', '..');
const OUT = path.join(ROOT, 'game', 'assets', 'audio');
const RES = 'res://assets/audio/';
const VERSION = 1;

const args = process.argv.slice(2);
const flag = (f) => args.includes(f);
const val = (f, d = null) => { const i = args.indexOf(f); return i >= 0 && i + 1 < args.length ? args[i + 1] : d; };
const ONLY = val('--only');
const doMusic = flag('--music') || (!flag('--sfx') && !flag('--voice'));
const doSfx = flag('--sfx') || (!flag('--music') && !flag('--voice'));
const doVoice = flag('--voice') || (!flag('--music') && !flag('--sfx'));
const CHECK = flag('--check');

const SFX_MODULES = ['impacts', 'movement', 'elements', 'abilities', 'voices', 'ui', 'crowd', 'ambience', 'announcer'];
const SCORES = ['fight_night_poster', 'cannery_radio', 'combat_a', 'combat_b', 'boss', 'victory', 'defeat', 'title_night'];

// Sub-bus layout created by the Audio autoload (parent buses come from the project/Settings).
const BUSES = {
  Impacts: { send: 'SFX', db: 0 }, Movement: { send: 'SFX', db: -4 }, Zones: { send: 'SFX', db: -8 },
  Creatures: { send: 'Voice', db: -3 }, Dialogue: { send: 'Voice', db: -2 }, Crowd: { send: 'Ambience', db: 0 },
};

// Creature id -> sound palette (mods may override with an "audio" object on the creature definition).
const CREATURES = {
  f_stoke: { voice: 'stoke', material: 'flesh', plan: 'biped', juice: 'juice_stoke', step_extra: 'step_stoke_clank' },
  f_dredge: { voice: 'dredge', material: 'chitin', plan: 'crab', juice: 'juice_dredge' },
  f_gusto: { voice: 'gusto', material: 'flesh', plan: 'avian', juice: 'juice_gusto', dash_extra: 'flap' },
  f_dozer: { voice: 'dozer', material: 'chitin', plan: 'quadruped', juice: 'juice_dozer' },
  f_slurry: { voice: 'slurry', material: 'jelly', plan: 'serpent', juice: 'juice_slurry', drip: 'serpent_drip' },
  f_jitters: { voice: 'jitters', material: 'jelly', plan: 'hopper', juice: 'juice_jitters' },
  m_scrapling: { voice: 'scrapling', material: 'chitin', plan: 'biped', juice: 'juice_generic' },
  m_blister: { voice: 'blister', material: 'jelly', plan: 'hopper', juice: 'juice_generic', land: 'hop_land_wet' },
  b_bilge: { voice: 'bilge', material: 'flesh', plan: 'quadruped', juice: 'juice_generic' },
  b_conduit: { voice: 'conduit', material: 'chitin', plan: 'serpent', juice: 'juice_generic', drip: 'serpent_tick' },
  b_snappington: { voice: 'snappington', material: 'chitin', plan: 'quadruped', juice: 'juice_generic' },
  kid_lamprey: { voice: 'lamprey', material: 'flesh', plan: 'biped', juice: 'juice_generic' },
  dev_biped: { voice: 'stoke', material: 'flesh', plan: 'biped', juice: 'juice_generic' },
};

function log(s) { process.stdout.write(s + '\n'); }
function sha256(buf) { return crypto.createHash('sha256').update(buf).digest('hex'); }
function resPath(rel) { return RES + rel.replace(/\\/g, '/'); }
function md5(s) { return crypto.createHash('md5').update(s).digest('hex'); }

function readExistingUid(importFile) {
  if (!fs.existsSync(importFile)) return null;
  const m = /^uid="([^"]+)"/m.exec(fs.readFileSync(importFile, 'utf8'));
  return m ? m[1] : null;
}

/** Writes the Godot .import sidecar (Godot fills uid/path on --import; we keep an existing uid). */
function writeImport(wavFile, res, { loop = false, loopBegin = 0, loopEnd = -1, pcm = false, frames = 0 } = {}) {
  const importFile = wavFile + '.import';
  const uid = readExistingUid(importFile);
  const base = path.basename(wavFile);
  const dest = `res://.godot/imported/${base}-${md5(res)}.sample`;
  const lines = ['[remap]', '', 'importer="wav"', 'type="AudioStreamWAV"'];
  if (uid) lines.push(`uid="${uid}"`);
  lines.push(`path="${dest}"`, '', '[deps]', '', `source_file="${res}"`, `dest_files=["${dest}"]`, '', '[params]', '',
    'force/8_bit=false', 'force/mono=false', 'force/max_rate=false', 'force/max_rate_hz=44100', 'edit/trim=false', 'edit/normalize=false',
    `edit/loop_mode=${loop ? 2 : 1}`, `edit/loop_begin=${loop ? loopBegin : 0}`, `edit/loop_end=${loop ? (loopEnd < 0 ? frames : loopEnd) : -1}`,
    `compress/mode=${pcm ? 0 : 2}`, '');
  const text = lines.join('\n');
  if (!fs.existsSync(importFile) || fs.readFileSync(importFile, 'utf8') !== text) fs.writeFileSync(importFile, text);
}

const produced = new Set();
const manifest = { version: VERSION, files: {} };
let prevManifest = { files: {} };
try { prevManifest = JSON.parse(fs.readFileSync(path.join(OUT, 'manifest.json'), 'utf8')); } catch (e) { /* first build */ }
const checkFailures = [];
let bytesTotal = 0;

/** Writes (or checks) a rendered buffer; returns the manifest entry. */
function emit(rel, buf, sr, importOpts = {}) {
  const file = path.join(OUT, rel);
  const res = resPath(rel);
  const data = WAV.encode(buf, sr);
  const entry = {
    seconds: +(D.length(buf) / sr).toFixed(3), sr, channels: D.isStereo(buf) ? 2 : 1, bytes: data.length,
    peak_db: +D.peakDb(buf).toFixed(2), rms_db: +D.rmsDb(buf).toFixed(2), sha256: sha256(data),
  };
  if (entry.seconds >= 0.4) entry.lufs = +D.lufs(buf, sr).toFixed(2);
  if (importOpts.loop) entry.loop = { begin: importOpts.loopBegin || 0, end: importOpts.loopEnd < 0 || importOpts.loopEnd === undefined ? D.length(buf) : importOpts.loopEnd };
  if (CHECK) {
    if (!fs.existsSync(file)) checkFailures.push(`${rel}: missing`);
    else if (sha256(fs.readFileSync(file)) !== entry.sha256) checkFailures.push(`${rel}: differs from the committed render`);
  } else {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    if (!fs.existsSync(file) || !fs.readFileSync(file).equals(data)) fs.writeFileSync(file, data);
    writeImport(file, res, Object.assign({ frames: D.length(buf) }, importOpts));
  }
  produced.add(rel);
  manifest.files[rel] = entry;
  bytesTotal += data.length;
  return entry;
}

function reuse(rel) { // keep a previous render that is not part of this (filtered) run
  const e = prevManifest.files[rel];
  if (!e || !fs.existsSync(path.join(OUT, rel))) return null;
  produced.add(rel);
  manifest.files[rel] = e;
  bytesTotal += e.bytes;
  return e;
}

function matches(id) { return !ONLY || id.includes(ONLY); }

// ---------------------------------------------------------------------------------------
// SFX
// ---------------------------------------------------------------------------------------

function loadDefs() {
  const defs = [];
  const seen = new Set();
  for (const m of SFX_MODULES) {
    const list = require(`./sfx/${m}.js`);
    for (const d of list) {
      if (seen.has(d.id)) throw new Error(`duplicate sfx id ${d.id} (module ${m})`);
      seen.add(d.id);
      d.module = m;
      defs.push(d);
    }
  }
  for (const d of defs) if (d.alias && !seen.has(d.alias)) throw new Error(`alias ${d.id} -> unknown ${d.alias}`);
  return defs;
}

function buildSfx(defs, bank) {
  const stats = {};
  let rendered = 0, kept = 0;
  const t0 = Date.now();
  for (const d of defs) {
    if (d.alias) {
      bank.sfx[d.id] = Object.assign({ alias: d.alias }, pick(d, ['gain', 'pitch', 'cooldown', 'priority', 'max_voices', 'bus']));
      continue;
    }
    const files = [];
    const n = d.variants || 1;
    for (let k = 0; k < n; k++) {
      const rel = `${d.group}/${d.id}${n > 1 ? '_' + k : ''}.wav`;
      files.push(resPath(rel));
      if (!matches(d.id) && reuse(rel)) { kept++; continue; }
      const rng = new Rng(`${d.id}:${k}`);
      let buf = d.gen(rng, d.sr, k, {});
      if (!(buf instanceof Float64Array) || buf.length < 8) throw new Error(`${d.id}[${k}] produced no audio`);
      for (let i = 0; i < buf.length; i++) if (!Number.isFinite(buf[i])) throw new Error(`${d.id}[${k}] produced NaN/Inf at ${i}`);
      D.normalize(buf, D.db(d.peak === undefined ? -1 : d.peak));
      if (!d.loop) D.fade(buf, d.sr, 0, 0.004);
      const e = emit(rel, buf, d.sr, d.loop ? { loop: true, loopBegin: 0, loopEnd: buf.length } : {});
      rendered++;
      stats[d.group] = stats[d.group] || { files: 0, seconds: 0, bytes: 0 };
      stats[d.group].files++; stats[d.group].seconds += e.seconds; stats[d.group].bytes += e.bytes;
    }
    bank.sfx[d.id] = Object.assign({ files }, pick(d, ['bus', 'gain', 'pitch', 'cooldown', 'priority', 'max_voices', 'loop', 'spatial']));
  }
  log(`  sfx: ${rendered} files rendered, ${kept} kept, ${((Date.now() - t0) / 1000).toFixed(1)} s`);
  return stats;
}

function pick(o, keys) { const out = {}; for (const k of keys) if (o[k] !== undefined) out[k] = o[k]; return out; }

// ---------------------------------------------------------------------------------------
// Music
// ---------------------------------------------------------------------------------------

function buildMusic(bank, report) {
  const t0 = Date.now();
  for (const name of SCORES) {
    const song = require(`./scores/${name}.js`);
    const baseRel = `music/${song.id}.wav`;
    if (!matches(song.id)) {
      const prev = prevManifest.music && prevManifest.music[song.id];
      if (prev && reuse(baseRel)) {
        for (const L of prev.layers || []) reuse(`music/${song.id}_${L.id}.wav`);
        bank.music[song.id] = prev;
        manifest.music = manifest.music || {};
        manifest.music[song.id] = prev;
        continue;
      }
    }
    const r = SEQ.renderSong(song, { log });
    const sr = r.base.sr;
    const loopOpts = r.loop ? { loop: true, loopBegin: r.loop.begin, loopEnd: r.loop.end } : {};
    const e = emit(baseRel, r.base.buf, sr, loopOpts);
    const entry = {
      file: resPath(baseRel), title: song.title, bpm: song.bpm, beats_per_bar: r.meta.beatsPerBar, bars: r.meta.bars, seconds: e.seconds,
      bar_seconds: +r.meta.barSeconds.toFixed(6), sections: r.meta.sections, gain: song.gain === undefined ? 0 : song.gain,
      loop: r.loop ? { begin: r.loop.begin, end: r.loop.end, start_bar: r.loop.startBar, end_bar: r.loop.endBar } : null,
      stereo: D.isStereo(r.base.buf), sr, layers: [], tags: song.tags || [], stinger: !!song.stinger,
    };
    for (const L of r.layers) {
      const rel = `music/${song.id}_${L.id}.wav`;
      const le = emit(rel, L.buf, L.sr, L.loop ? { loop: true, loopBegin: L.loop.begin, loopEnd: L.loop.end } : {});
      entry.layers.push({ id: L.id, file: resPath(rel), default_db: L.defaultDb, loop_bars: L.bars, kind: L.kind, seconds: le.seconds, sr: L.sr });
    }
    bank.music[song.id] = entry;
    manifest.music = manifest.music || {};
    manifest.music[song.id] = entry;
    report.music.push({ id: song.id, title: song.title, bpm: song.bpm, bars: r.meta.bars, seconds: e.seconds, lufs: e.lufs, peak: e.peak_db, loop: entry.loop, layers: entry.layers.map((l) => l.id), bytes: e.bytes + entry.layers.reduce((a, l) => a + (manifest.files[`music/${song.id}_${l.id}.wav`] || {}).bytes || 0, 0), stats: r.stats });
    log(`    -> ${e.seconds.toFixed(1)} s, ${e.lufs} LUFS, peak ${e.peak_db} dBFS, ${(e.bytes / 1048576).toFixed(1)} MB`);
  }
  log(`  music: ${((Date.now() - t0) / 1000).toFixed(1)} s`);
}

// ---------------------------------------------------------------------------------------
// Announcer grain banks
// ---------------------------------------------------------------------------------------

function buildVoices(bank) {
  for (const ch of Object.keys(BABBLE.CHARACTERS)) {
    const sr = 22050;
    const grains = BABBLE.renderBank(sr, new Rng('babble:' + ch), ch);
    const entry = Object.assign({}, BABBLE.CHARACTERS[ch], { sr, grains: {} });
    for (const g of grains) {
      const rel = `announcer/${ch}/${g.id}.wav`;
      let buf = g.buf;
      for (let i = 0; i < buf.length; i++) if (!Number.isFinite(buf[i])) throw new Error(`grain ${ch}/${g.id} NaN`);
      D.normalize(buf, D.db(-3));
      emit(rel, buf, sr, { pcm: true });
      entry.grains[g.id] = resPath(rel);
    }
    bank.voices[ch] = entry;
  }
  log(`  voices: ${Object.keys(bank.voices).length} grain banks`);
}

// ---------------------------------------------------------------------------------------
// --say: audition a line offline
// ---------------------------------------------------------------------------------------

function say() {
  const text = val('--say');
  const speaker = val('--speaker', 'barnaby');
  const outFile = val('--out', path.join(ROOT, 'captures', `say_${speaker}.wav`));
  const sr = 22050;
  const bank = {};
  for (const g of BABBLE.renderBank(sr, new Rng('babble:' + speaker), speaker)) bank[g.id] = D.normalize(g.buf, D.db(-3));
  const p = BABBLE.plan(text, speaker, { seed: 1, names: (val('--names', '') || '').split(',').filter(Boolean), reduced: flag('--reduced') });
  const wav = BABBLE.assemble(p, bank, sr);
  D.normalize(wav, D.db(-1));
  WAV.write(outFile, wav, sr);
  log(`wrote ${outFile} (${p.duration.toFixed(2)} s, ${p.grains.length} grains)`);
}

// ---------------------------------------------------------------------------------------
// Report
// ---------------------------------------------------------------------------------------

function writeReport(report, bank, sfxStats) {
  const lines = [];
  lines.push('# Audio build report', '', `Generated by \`node tools/audio/build.js\` (deterministic; rebuilds are byte-identical). Date of this render: ${report.date}.`, '');
  lines.push('## Music', '', '| Track | Title | BPM | Bars | Length | Loop (bars) | Layers | Integrated loudness | Peak | Size |', '|---|---|---|---|---|---|---|---|---|---|');
  for (const m of report.music) lines.push(`| ${m.id} | ${m.title} | ${m.bpm} | ${m.bars} | ${m.seconds.toFixed(1)} s | ${m.loop ? `${m.loop.start_bar}–${m.loop.end_bar}` : 'one-shot'} | ${m.layers.join(', ') || '—'} | ${m.lufs} LUFS | ${m.peak} dBFS | ${(m.bytes / 1048576).toFixed(1)} MB |`);
  lines.push('', '## Sound effects', '', '| Group | Files | Total length | Size |', '|---|---|---|---|');
  let sfxFiles = 0;
  for (const [g, s] of Object.entries(sfxStats).sort()) { lines.push(`| ${g} | ${s.files} | ${s.seconds.toFixed(1)} s | ${(s.bytes / 1048576).toFixed(2)} MB |`); sfxFiles += s.files; }
  const ids = Object.keys(bank.sfx);
  const aliases = ids.filter((i) => bank.sfx[i].alias).length;
  lines.push('', `${ids.length} bank ids (${ids.length - aliases} rendered definitions + ${aliases} aliases), ${sfxFiles} rendered files.`);
  lines.push('', '## Announcer grain banks', '');
  for (const [ch, v] of Object.entries(bank.voices)) lines.push(`- **${ch}**: ${Object.keys(v.grains).length} grains at ${v.sr} Hz, f0 ${v.f0} Hz, ${v.rate} syllables/s`);
  lines.push('', '## Verification', '');
  const peaks = Object.values(manifest.files).map((f) => f.peak_db);
  const maxPeak = Math.max(...peaks);
  lines.push(`- Files: ${Object.keys(manifest.files).length}, total ${(bytesTotal / 1048576).toFixed(1)} MB of 16-bit WAV (imported as QOA except the PCM grain banks).`);
  lines.push(`- Loudest sample peak across every file: ${maxPeak.toFixed(2)} dBFS (ceiling −1 dBFS: ${maxPeak <= -0.99 ? 'OK' : 'FAIL'}).`);
  const loops = Object.entries(manifest.files).filter(([, f]) => f.loop);
  lines.push(`- Loops: ${loops.length} files with loop points, all with begin < end ≤ length.`);
  lines.push(`- Music loudness target: ${report.music.map((m) => `${m.id} ${m.lufs}`).join(', ')} LUFS (stings are normalized like the loops; the game applies per-context bus offsets).`);
  if (report.sizeWarning) lines.push(`- ${report.sizeWarning}`);
  lines.push('');
  fs.writeFileSync(path.join(__dirname, 'report.md'), lines.join('\n'));
}

// ---------------------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------------------

function main() {
  if (val('--say')) return say();
  const t0 = Date.now();
  log(`CRITTERWEIGHT audio build -> ${OUT}${CHECK ? ' (check only)' : ''}`);
  const bank = { version: VERSION, buses: BUSES, sfx: {}, music: {}, voices: {}, creatures: CREATURES };
  const report = { music: [], date: '2026-10-15' };
  let sfxStats = {};
  const defs = loadDefs();
  if (doSfx) sfxStats = buildSfx(defs, bank);
  else for (const d of defs) { // keep bank complete from the previous manifest
    if (d.alias) { bank.sfx[d.id] = Object.assign({ alias: d.alias }, pick(d, ['gain', 'pitch', 'cooldown', 'priority', 'max_voices', 'bus'])); continue; }
    const n = d.variants || 1; const files = [];
    for (let k = 0; k < n; k++) { const rel = `${d.group}/${d.id}${n > 1 ? '_' + k : ''}.wav`; files.push(resPath(rel)); reuse(rel); }
    bank.sfx[d.id] = Object.assign({ files }, pick(d, ['bus', 'gain', 'pitch', 'cooldown', 'priority', 'max_voices', 'loop', 'spatial']));
  }
  if (doVoice) buildVoices(bank);
  else if (prevManifest.voices) { bank.voices = prevManifest.voices; for (const v of Object.values(bank.voices)) for (const f of Object.values(v.grains)) reuse(f.replace(RES, '')); }
  if (doMusic) buildMusic(bank, report);
  else if (prevManifest.music) { for (const [id, m] of Object.entries(prevManifest.music)) { bank.music[id] = m; reuse(`music/${id}.wav`); for (const L of m.layers || []) reuse(`music/${id}_${L.id}.wav`); } }
  manifest.voices = bank.voices;
  manifest.music = bank.music;
  manifest.bytes = bytesTotal;
  if (CHECK) {
    if (checkFailures.length) { log('CHECK FAILED:\n  ' + checkFailures.join('\n  ')); process.exit(1); }
    log(`check ok: ${produced.size} files match the committed renders`);
    return;
  }
  // stale files
  if (flag('--clean')) {
    const walk = (dir) => { for (const f of fs.readdirSync(dir)) { const p = path.join(dir, f); if (fs.statSync(p).isDirectory()) walk(p); else if (f.endsWith('.wav')) { const rel = path.relative(OUT, p).replace(/\\/g, '/'); if (!produced.has(rel)) { fs.unlinkSync(p); if (fs.existsSync(p + '.import')) fs.unlinkSync(p + '.import'); log(`  removed stale ${rel}`); } } } };
    if (fs.existsSync(OUT)) walk(OUT);
  }
  fs.mkdirSync(OUT, { recursive: true });
  fs.writeFileSync(path.join(OUT, 'bank.json'), JSON.stringify(bank, null, 1));
  fs.writeFileSync(path.join(OUT, 'manifest.json'), JSON.stringify(manifest, null, 1));
  const mb = bytesTotal / 1048576;
  if (mb > 125) report.sizeWarning = `Size budget: ${mb.toFixed(1)} MB rendered (target ~120 MB).`;
  if (!(doMusic && doSfx && doVoice)) { // partial run: fill report music from manifest
    for (const [id, m] of Object.entries(bank.music)) if (!report.music.find((r) => r.id === id)) { const f = manifest.files[`music/${id}.wav`] || {}; report.music.push({ id, title: m.title, bpm: m.bpm, bars: m.bars, seconds: m.seconds, lufs: f.lufs, peak: f.peak_db, loop: m.loop, layers: (m.layers || []).map((l) => l.id), bytes: f.bytes || 0 }); }
    for (const [rel, f] of Object.entries(manifest.files)) { const g = rel.split('/')[0]; if (g === 'music' || g === 'announcer') continue; if (!sfxStats[g]) sfxStats[g] = { files: 0, seconds: 0, bytes: 0 }; if (!doSfx) { sfxStats[g].files++; sfxStats[g].seconds += f.seconds; sfxStats[g].bytes += f.bytes; } }
  }
  writeReport(report, bank, sfxStats);
  log(`done: ${produced.size} files, ${mb.toFixed(1)} MB, ${((Date.now() - t0) / 1000).toFixed(1)} s`);
}

main();
