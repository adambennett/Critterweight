'use strict';
// Interface sounds (AUDIO_DIRECTION.md §3.6): everything under 120 ms except the card stamp and the
// round card. Bus "UI", never positional.
const K = require('../lib/sfxkit');
const D = require('../lib/dsp');
const INST = require('../lib/instruments');
const { def, alias, jit } = require('./_def');

const UI = { bus: 'UI', group: 'ui', priority: 70, max_voices: 4, spatial: false, pitch: [0.99, 1.01], gain: -2 };

function blip(sr, f, dur = 0.08, ratio = 2, index = 1.2) {
  return K.fmHit(sr, { f, ratio, index, dur, idxDecay: 0.5, curve: 1.4, a: 0.002 });
}

module.exports = [
  def('ui_move', Object.assign({ variants: 1, cooldown: 0.03, gain: -8 }, UI, { pitch: [1, 1] }), (rng, sr) =>
    K.tidy(K.burst(sr, rng, { dur: 0.04, filt: [{ type: 'bp', f: jit(rng, 2400, 0.1), q: 2 }, { type: 'hp', f: 800 }], a: 0.001, curve: 2.2 }), sr)),
  def('ui_accept', Object.assign({ variants: 2 }, UI), (rng, sr) =>
    K.tidy(K.mix(sr, [{ buf: blip(sr, 523.25, 0.06), gain: 0 }, { buf: blip(sr, 783.99, 0.08), gain: 0, at: 0.04 }]), sr)),
  def('ui_back', Object.assign({ variants: 2 }, UI), (rng, sr) => K.tidy(blip(sr, 392.0, 0.08), sr)),
  def('ui_error', Object.assign({ variants: 2 }, UI), (rng, sr) =>
    K.tidy(K.tone(sr, { f: 110, dur: 0.1, wave: 'square', a: 0.002, d: 0.02, s: 0.8, r: 0.02, lp: 1800, gain: 0.5 }), sr)),
  def('ui_toggle', Object.assign({ variants: 2 }, UI), (rng, sr) =>
    K.tidy(K.mix(sr, [{ buf: K.burst(sr, rng, { dur: 0.012, filt: [{ type: 'bp', f: 1800, q: 2 }], curve: 2.5 }), gain: 0 }, { buf: blip(sr, 659.25, 0.05, 2, 0.8), gain: -6, at: 0.01 }]), sr)),
  def('ui_slider', Object.assign({ variants: 3, cooldown: 0.02, gain: -10 }, UI), (rng, sr) =>
    K.tidy(K.fmHit(sr, { f: 1760, ratio: 2, index: 0.8, dur: 0.03, idxDecay: 0.5, curve: 2 }), sr)),
  def('ui_tab', Object.assign({ variants: 2 }, UI), (rng, sr) =>
    K.tidy(K.mix(sr, [{ buf: K.sweep(sr, rng, { dur: 0.07, f0: 1800, f1: 4000, q: 1.5, peakAt: 0.5, gain: 0.8 }), gain: -4 }, { buf: blip(sr, 587.33, 0.06, 2, 1), gain: 0, at: 0.03 }]), sr)),
  def('ui_stamp', Object.assign({ variants: 2, priority: 80 }, UI), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.thump(sr, { f0: 180, f1: 90, sweep: 0.015, dur: 0.12, drive: 1.6, curve: 2 }), gain: 0 },
    { buf: K.burst(sr, rng, { dur: 0.06, filt: [{ type: 'bp', f: 900, q: 1 }], curve: 2 }), gain: -3 },
    { buf: K.burst(sr, rng, { dur: 0.09, color: 'pink', filt: [{ type: 'bp', f: 2500, q: 0.8 }], a: 0.004, curve: 1.6, gain: 0.7 }), gain: -6, at: 0.05 }]), sr)),
  def('ui_scrip', Object.assign({ variants: 3, cooldown: 0.05 }, UI), (rng, sr) =>
    K.tidy(K.fmHit(sr, { f: jit(rng, 2093, 0.03), ratio: 3.0, index: 1.4, dur: 0.22, idxDecay: 0.3, curve: 1.6, detune: 4 }), sr)),
  def('ui_supplement', Object.assign({ variants: 2 }, UI), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.burst(sr, rng, { dur: 0.015, filt: [{ type: 'hp', f: 2500 }], curve: 2.5, gain: 1.4 }), gain: 0 },
    { buf: K.fmHit(sr, { f: 1500, ratio: 2.76, index: 1.5, dur: 0.08, idxDecay: 0.3 }), gain: -6, at: 0.004 },
    { buf: K.crackle(sr, rng, { dur: 0.45, density: 700, tone: 5500, decayMs: 1.5, gain: 0.6 }), gain: -8, at: 0.03 }]), sr)),
  def('ui_banned', Object.assign({ variants: 1, priority: 85 }, UI), (rng, sr) => {
    const o = new D.Osc(sr, 'saw'), lfo = new D.Lfo(sr, 'tri');
    const n = D.secs(sr, 0.5);
    const sirenBuf = D.zeros(n);
    const lp = new D.SVF(sr, 2500, 1);
    for (let i = 0; i < n; i++) sirenBuf[i] = Math.tanh(lp.lp(o.next(600 * Math.pow(1.6, 0.5 + 0.5 * lfo.next(4)))) * 2) * Math.pow(1 - i / n, 0.8) * 0.5;
    return K.tidy(K.mix(sr, [
      { buf: K.burst(sr, rng, { dur: 0.015, filt: [{ type: 'hp', f: 2500 }], curve: 2.5, gain: 1.4 }), gain: 0 },
      { buf: K.crackle(sr, rng, { dur: 0.3, density: 700, tone: 5500, decayMs: 1.5, gain: 0.6 }), gain: -8, at: 0.03 },
      { buf: sirenBuf, gain: -4, at: 0.12 }]), sr);
  }),
  def('ui_hype_full', Object.assign({ variants: 1, priority: 80 }, UI), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.sweep(sr, rng, { dur: 0.5, f0: 1500, f1: 6000, q: 1.5, peakAt: 0.7, curve: 1.5, gain: 1 }), gain: -4 },
    { buf: K.fmHit(sr, { f: 1046.5, ratio: 1.5, index: 2.5, dur: 0.5, idxDecay: 0.5, detune: 8 }), gain: -6, at: 0.1 },
    { buf: K.rattle(sr, rng, { dur: 0.4, f: 220, density: 90, gain: 0.8, hp: 900 }), gain: -3, at: 0.25 }]), sr)),
  def('ui_hype_loop', Object.assign({ loop: true, gain: -16, pitch: [1, 1], priority: 20 }, UI), (rng, sr) => {
    const n = D.secs(sr, 1.2);
    const out = D.zeros(n);
    const o1 = new D.Osc(sr, 'sine'), o2 = new D.Osc(sr, 'sine', 0.5);
    const lfo = new D.Lfo(sr, 'sine');
    for (let i = 0; i < n; i++) out[i] = (o1.next(1046.5) * 0.5 + o2.next(1568) * 0.3) * (0.6 + 0.4 * lfo.next(2.5)) * 0.4;
    return K.seamless(K.mix(sr, [{ buf: out, gain: 0 }, { buf: K.rattle(sr, rng, { dur: 1.2, f: 240, density: 40, gain: 0.5, hp: 1000 }), gain: -6 }]).slice(0, n), sr, 0.3);
  }),
  def('ui_cooldown_ready', Object.assign({ variants: 2 }, UI), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.burst(sr, rng, { dur: 0.01, filt: [{ type: 'bp', f: 2000, q: 2 }], curve: 2.5 }), gain: 0 },
    { buf: K.fmHit(sr, { f: 1318.5, ratio: 2, index: 1.2, dur: 0.18, idxDecay: 0.4 }), gain: -3, at: 0.015 }]), sr)),
  def('ui_round_card', Object.assign({ variants: 1, priority: 90, gain: 0 }, UI), (rng, sr) => {
    const brass = INST.make('fmBrass', { index: 3, a: 0.02, d: 0.2, s: 0.7, r: 0.25 });
    const chord = K.mix(sr, [['f3', 174.61], ['a3', 220.0], ['c4', 261.63], ['f4', 349.23]].map(([_, f]) => ({ buf: brass.render({ freq: f, dur: 0.35, vel: 1 }, sr, rng), gain: -4 })));
    const bell = K.fmHit(sr, { f: 880, ratio: 1.6, index: 2.5, dur: 1.2, idxDecay: 0.3, detune: 6 });
    return K.tidy(K.mix(sr, [{ buf: chord, gain: 0 }, { buf: bell, gain: -4, at: 0.3 }]), sr);
  }),
  def('ui_fight', Object.assign({ variants: 1, priority: 90, gain: 0 }, UI), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.fmHit(sr, { f: 660, ratio: 1.6, index: 3, dur: 1.4, idxDecay: 0.3, detune: 6 }), gain: 0 },
    { buf: K.burst(sr, rng, { dur: 0.01, filt: [{ type: 'hp', f: 3000 }], curve: 2.5 }), gain: -4 }]), sr)),
  def('ui_pause', Object.assign({ variants: 1 }, UI), (rng, sr) => K.tidy(K.mix(sr, [{ buf: blip(sr, 523.25, 0.06), gain: 0 }, { buf: blip(sr, 392.0, 0.09), gain: 0, at: 0.05 }]), sr)),
  def('ui_unpause', Object.assign({ variants: 1 }, UI), (rng, sr) => K.tidy(K.mix(sr, [{ buf: blip(sr, 392.0, 0.06), gain: 0 }, { buf: blip(sr, 523.25, 0.09), gain: 0, at: 0.05 }]), sr)),
  def('ui_timer_tick', Object.assign({ variants: 2, gain: -6 }, UI), (rng, sr) =>
    K.tidy(K.mix(sr, [{ buf: K.burst(sr, rng, { dur: 0.008, filt: [{ type: 'bp', f: 3000, q: 3 }], curve: 2.5, gain: 1.5 }), gain: 0 }, { buf: K.tone(sr, { f: 1200, dur: 0.03, a: 0.001, d: 0.02, s: 0.3, r: 0.01 }), gain: -6 }]), sr)),
  def('ui_open', Object.assign({ variants: 1, gain: -4 }, UI), (rng, sr) => K.tidy(K.mix(sr, [{ buf: K.sweep(sr, rng, { dur: 0.1, f0: 900, f1: 3500, q: 1.4, peakAt: 0.5, gain: 0.8 }), gain: -3 }, { buf: blip(sr, 659.25, 0.07, 2, 0.9), gain: 0, at: 0.05 }]), sr)),
  def('ui_close', Object.assign({ variants: 1, gain: -4 }, UI), (rng, sr) => K.tidy(K.mix(sr, [{ buf: K.sweep(sr, rng, { dur: 0.1, f0: 3500, f1: 900, q: 1.4, peakAt: 0.3, gain: 0.8 }), gain: -3 }, { buf: blip(sr, 440, 0.07, 2, 0.9), gain: 0, at: 0.03 }]), sr)),
  def('ui_card_flip', Object.assign({ variants: 2, gain: -4 }, UI), (rng, sr) =>
    K.tidy(K.burst(sr, rng, { dur: 0.09, color: 'pink', filt: [{ type: 'bp', f: 1800, q: 0.7 }, { type: 'hp', f: 600 }], a: 0.01, curve: 1.5 }), sr)),
  def('ui_purchase', Object.assign({ variants: 1 }, UI), (rng, sr) => K.tidy(K.mix(sr, [
    { buf: K.fmHit(sr, { f: 1568, ratio: 3, index: 1.4, dur: 0.2, idxDecay: 0.3 }), gain: 0 }, { buf: K.fmHit(sr, { f: 2093, ratio: 3, index: 1.4, dur: 0.3, idxDecay: 0.3 }), gain: 0, at: 0.09 },
    { buf: K.burst(sr, rng, { dur: 0.06, filt: [{ type: 'bp', f: 1000, q: 1 }], curve: 2 }), gain: -8 }]), sr)),
  def('ui_notify', Object.assign({ variants: 1, gain: -4 }, UI), (rng, sr) => K.tidy(K.mix(sr, [{ buf: blip(sr, 783.99, 0.09, 2, 1.2), gain: 0 }, { buf: blip(sr, 1046.5, 0.14, 2, 1.2), gain: -1, at: 0.08 }]), sr)),
  alias('ui_denied', 'ui_error'), alias('ui_focus', 'ui_move'), alias('ui_select', 'ui_accept'), alias('ui_cancel', 'ui_back'),
];
