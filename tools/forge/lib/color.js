'use strict';
// Colour utilities: hex (sRGB) <-> linear floats. Vertex colours in the glb are LINEAR
// (glTF spec), which is what the game's creature shader reads as albedo.

function srgbToLinear(c) {
  return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}
function linearToSrgb(c) {
  return c <= 0.0031308 ? c * 12.92 : 1.055 * Math.pow(c, 1 / 2.4) - 0.055;
}
function hexToSrgb(hex) {
  const h = hex.replace('#', '');
  const n = parseInt(h.length === 3 ? h.split('').map((x) => x + x).join('') : h, 16);
  return [((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255];
}
function hexToLinear(hex) {
  return hexToSrgb(hex).map(srgbToLinear);
}
function linearToHex(c) {
  const q = (x) => Math.max(0, Math.min(255, Math.round(linearToSrgb(x) * 255)));
  return '#' + [q(c[0]), q(c[1]), q(c[2])].map((v) => v.toString(16).padStart(2, '0')).join('');
}
// Resolve "$name" palette references, hex strings or [r,g,b] linear arrays.
function resolve(color, palette) {
  if (Array.isArray(color)) return color.slice(0, 3);
  if (typeof color !== 'string') throw new Error('bad colour ' + JSON.stringify(color));
  if (color[0] === '$') {
    const key = color.slice(1);
    if (!palette || !(key in palette)) throw new Error('unknown palette colour ' + color);
    return resolve(palette[key], palette);
  }
  return hexToLinear(color);
}
function lighten(c, k) { return c.map((x) => x + (1 - x) * k); }
function darken(c, k) { return c.map((x) => x * (1 - k)); }
function mixc(a, b, t) { return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]; }

module.exports = { srgbToLinear, linearToSrgb, hexToSrgb, hexToLinear, linearToHex, resolve, lighten, darken, mixc };
