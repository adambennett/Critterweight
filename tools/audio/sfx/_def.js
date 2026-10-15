'use strict';
// Helper for SFX definition modules. A definition describes one bank id:
//   id        bank id (also the file stem; variants become <id>_<n>.wav)
//   group     output folder under game/assets/audio/ (impacts, movement, ...)
//   bus       Godot bus: Impacts | Movement | Zones | Creatures | Dialogue | UI | Crowd | Ambience
//   variants  number of rendered variations (>= 3 for frequent one-shots)
//   sr        render rate (44100 default; voices/ambience may use 22050)
//   gain      bank volume in dB applied at play time (files are peak-normalized to `peak` dBFS)
//   pitch     [lo, hi] random pitch multiplier range at play time
//   cooldown  seconds before the same id may play again
//   priority  0..100 (voice stealing: higher wins)
//   max_voices simultaneous instances
//   loop      true for seamless loops (imported with loop_mode forward)
//   spatial   true = 3D positional when a position is given
//   alias     id of another definition (no files rendered; the bank points at its files)
//   gen(rng, sr, k, ctx) -> Float64Array mono (k = variant index)

const DEFAULTS = {
  variants: 1, sr: 44100, gain: 0, pitch: [0.96, 1.04], cooldown: 0, priority: 50, max_voices: 4, loop: false, spatial: true, peak: -1,
};

function def(id, opts, gen) {
  if (typeof opts === 'function') { gen = opts; opts = {}; }
  return Object.assign({ id }, DEFAULTS, opts, gen ? { gen } : {});
}

function alias(id, target, opts = {}) {
  return Object.assign({ id, alias: target }, opts);
}

/** Jitter helper: multiplies by a random factor in [1-amt, 1+amt]. */
function jit(rng, v, amt = 0.1) { return v * (1 + rng.range(-amt, amt)); }

module.exports = { def, alias, jit, DEFAULTS };
