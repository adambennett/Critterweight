#!/usr/bin/env node
'use strict';
// CRITTERWEIGHT creature forge — builds every creature/NPC/prop model from the art definitions
// in tools/forge/defs/**. Zero dependencies (Node >= 18).
//
//   node tools/forge/forge.js                 rebuild everything into game/assets/models
//   node tools/forge/forge.js f_stoke boss_bilge   only these definition ids
//   options: --out <dir>  --res <m>  --tris <n>  --quiet  --list  --stats <json>
//
// Definitions are .js modules (module.exports = {...}) or .json files; see docs/ART_PIPELINE.md.

const fs = require('fs');
const path = require('path');
const { forgeDefinition } = require('./lib/pipeline');

const repoRoot = path.resolve(__dirname, '..', '..');
const defsDir = path.join(__dirname, 'defs');

function listDefs(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) listDefs(p, out);
    else if (/\.(js|json)$/.test(e.name) && !e.name.startsWith('_')) out.push(p);
  }
  return out;
}

function loadDef(file) {
  if (file.endsWith('.json')) return JSON.parse(fs.readFileSync(file, 'utf8'));
  delete require.cache[require.resolve(file)];
  const d = require(file);
  return typeof d === 'function' ? d() : d;
}

function main(argv) {
  const args = argv.slice(2);
  const opts = { out: path.join(repoRoot, 'game', 'assets', 'models'), quiet: false, ids: [], stats: null };
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--out') opts.out = path.resolve(args[++i]);
    else if (a === '--res') opts.res = parseFloat(args[++i]);
    else if (a === '--tris') opts.targetTris = parseInt(args[++i], 10);
    else if (a === '--quiet') opts.quiet = true;
    else if (a === '--list') opts.list = true;
    else if (a === '--stats') opts.stats = path.resolve(args[++i]);
    else if (a.startsWith('--')) throw new Error('unknown option ' + a);
    else opts.ids.push(a);
  }
  const files = listDefs(defsDir, []).sort();
  const defs = files.map((f) => ({ file: f, def: loadDef(f) }));
  if (opts.list) {
    for (const d of defs) console.log(`${d.def.id.padEnd(20)} ${path.relative(repoRoot, d.file)} -> ${d.def.out || 'creatures/' + d.def.id + '.glb'}`);
    return 0;
  }
  const selected = opts.ids.length ? defs.filter((d) => opts.ids.includes(d.def.id)) : defs;
  if (opts.ids.length && selected.length !== opts.ids.length) {
    const known = new Set(defs.map((d) => d.def.id));
    for (const id of opts.ids) if (!known.has(id)) throw new Error('unknown definition id ' + id);
  }
  const log = opts.quiet ? () => {} : (m) => console.log(m);
  const all = [];
  let failures = 0;
  for (const { file, def } of selected) {
    try {
      const stats = forgeDefinition(def, { repoRoot, outDir: opts.out, res: opts.res, targetTris: opts.targetTris, log });
      stats.definition = path.relative(repoRoot, file).replace(/\\/g, '/');
      all.push(stats);
    } catch (e) {
      failures++;
      console.error(`FAILED ${def.id}: ${e.stack || e}`);
    }
  }
  const statsPath = opts.stats || path.join(__dirname, 'build', 'stats.json');
  fs.mkdirSync(path.dirname(statsPath), { recursive: true });
  let merged = [];
  if (fs.existsSync(statsPath)) {
    try { merged = JSON.parse(fs.readFileSync(statsPath, 'utf8')); } catch (e) { merged = []; }
  }
  const byId = new Map(merged.map((s) => [s.id, s]));
  for (const s of all) byId.set(s.id, s);
  const list = Array.from(byId.values()).sort((a, b) => a.id.localeCompare(b.id));
  fs.writeFileSync(statsPath, JSON.stringify(list, null, 1) + '\n');
  log(`forged ${all.length} model(s), ${failures} failure(s); stats: ${path.relative(repoRoot, statsPath)}`);
  return failures ? 1 : 0;
}

if (require.main === module) process.exit(main(process.argv));
module.exports = { main, loadDef, listDefs };
