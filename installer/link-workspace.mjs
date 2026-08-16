#!/usr/bin/env node
/**
 * link-workspace.mjs — Create directory junctions for all workspace packages
 * into <target>/node_modules/<name>.
 *
 * WHY: with `nodeLinker: hoisted`, pnpm does not create the top-level
 * workspace symlinks (node_modules/@deepseek-ai/*), so tsc/tsdown can't
 * resolve packages that aren't listed in tsconfig paths (TS2307). We create
 * Windows directory junctions instead — junctions don't need admin rights
 * (real symlinks do).
 *
 * Usage: node link-workspace.mjs [targetDir]
 *   targetDir defaults to the current directory. Must be run AFTER
 *   `pnpm install` (and every time node_modules is recreated).
 */
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const root = path.resolve(process.argv[2] || process.cwd());
const nmDir = path.join(root, 'node_modules');

const candidates = [];
function addDir(p) { if (fs.existsSync(path.join(p, 'package.json'))) candidates.push(p); }
function addGlob(dir) {
  if (!fs.existsSync(dir)) return;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.isDirectory()) addDir(path.join(dir, e.name));
  }
}
addGlob(path.join(root, 'vendor'));
const pkgRoot = path.join(root, 'packages');
if (fs.existsSync(pkgRoot)) {
  for (const cat of fs.readdirSync(pkgRoot, { withFileTypes: true })) {
    if (cat.isDirectory()) addGlob(path.join(pkgRoot, cat.name));
  }
}
addDir(path.join(root, 'native', 'landlock-run'));
addGlob(path.join(root, 'native', 'landlock-run', 'packages'));
addGlob(path.join(root, 'apps'));
addDir(path.join(root, 'website'));
addDir(path.join(root, 'examples'));
addDir(path.join(root, 'python', 'sdk-runtime'));

let created = 0, skipped = 0, errored = 0;
for (const dir of candidates) {
  let pj;
  try { pj = JSON.parse(fs.readFileSync(path.join(dir, 'package.json'), 'utf8')); } catch { continue; }
  const name = pj.name;
  if (!name) continue;
  const linkPath = path.join(nmDir, name);
  if (fs.existsSync(linkPath)) { skipped++; continue; }
  fs.mkdirSync(path.dirname(linkPath), { recursive: true });
  const r = spawnSync('cmd', ['/c', 'mklink', '/J', linkPath, dir], { encoding: 'utf8' });
  if (r.status === 0) { created++; }
  else { errored++; console.log('ERR ', name, r.stderr || r.stdout); }
}
console.log(`\nWorkspace junctions: created=${created} skipped=${skipped} errored=${errored} (target: ${root})`);
if (errored > 0) process.exitCode = 1;
