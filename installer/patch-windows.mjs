#!/usr/bin/env node
/**
 * patch-windows.mjs — Apply the Windows-specific fixes that make
 * deepseek-harness install & build correctly on Windows + pnpm 11.
 *
 * WHY these patches exist (audit trail — every change is explained):
 *
 *  1. .npmrc  -> registry=https://registry.npmmirror.com
 *     Reason: default npmjs.org is slow/unreachable from mainland China.
 *
 *  2. pnpm-workspace.yaml -> nodeLinker: hoisted
 *     Reason: pnpm's default isolated linker fails to create top-level
 *     symlinks for this project on some Windows setups (typescript,
 *     @types/node and native prebuilts end up missing -> tsc TS2688).
 *     hoisted = npm-classic flat node_modules, uses hardlinks, no symlinks.
 *
 *  3. pnpm-workspace.yaml -> verifyDepsBeforeRun: false
 *     Reason: `pnpm run` would re-run `pnpm install` first and wipe the
 *     manually-created workspace junctions (see link-workspace.mjs).
 *
 *  4. pnpm-workspace.yaml -> allowBuilds: koffi=false,
 *     subprocess-local=false
 *     Reason: koffi's cnoke source build picks the "MinGW Makefiles" CMake
 *     generator under MSYSTEM (Git Bash) and fails (no MinGW installed);
 *     the prebuilt @koromix/koffi-win32-x64 binary is used instead.
 *     subprocess-local's postinstall (macOS spawn-helper bit fix) throws
 *     because node-pty isn't resolvable from its context; it's macOS-only
 *     and not needed on Windows.
 *
 *  5. package.json (root) postinstall -> no-op
 *     Reason: installs lefthook git hooks; fails without the lefthook
 *     windows binary and is not needed to build/run.
 *
 *  6. packages/subprocess/subprocess-local/package.json postinstall -> no-op
 *     Reason: see #4. A failing workspace postinstall aborts the whole
 *     `pnpm install` (exit 1) and leaves node_modules incomplete.
 *
 * The script is IDEMPOTENT (safe to re-run) and transparent:
 *   node patch-windows.mjs [targetDir]        -> apply patches
 *   node patch-windows.mjs [targetDir] --review -> print what WOULD change
 *                                                  without changing anything
 */
import fs from 'node:fs';
import path from 'node:path';

const targetDir = path.resolve(process.argv[2] || process.cwd());
const review = process.argv.includes('--review');

const actions = []; // collected {file, what, done}

function log(file, what) {
  actions.push({ file: path.relative(targetDir, file) || '.', what });
}

function readIfExists(p) {
  try { return fs.readFileSync(p, 'utf8'); } catch { return null; }
}

function writeIfChanged(file, content, what) {
  const before = readIfExists(file);
  if (before === content) { actions.push({ file: path.relative(targetDir, file), what: what + ' (already ok)', done: true }); return; }
  log(file, what);
  if (!review) fs.writeFileSync(file, content, 'utf8');
}

// ---------------------------------------------------------------- .npmrc
const npmrcPath = path.join(targetDir, '.npmrc');
const npmrcContent = 'registry=https://registry.npmmirror.com\n';
writeIfChanged(npmrcPath, npmrcContent, 'set npm mirror registry (npmmirror)');

// ------------------------------------------------- pnpm-workspace.yaml
const wsPath = path.join(targetDir, 'pnpm-workspace.yaml');
let ws = readIfExists(wsPath);
if (ws !== null) {
  let changed = false;
  const insertTop = (block, key, what) => {
    if (ws.includes(key)) {
      actions.push({ file: path.relative(targetDir, wsPath), what: what + ' (already ok)', done: true });
    } else {
      ws = block + ws;
      changed = true;
      log(wsPath, what);
    }
  };
  insertTop(
    '# Workaround (Windows): isolated linker fails to link top-level deps.\nnodeLinker: hoisted\n\n',
    'nodeLinker: hoisted',
    'add nodeLinker: hoisted (flat node_modules, avoids broken top-level symlinks)'
  );
  insertTop(
    '# Workaround (Windows): do not auto re-install before `pnpm run` (keeps workspace junctions).\nverifyDepsBeforeRun: false\n\n',
    'verifyDepsBeforeRun: false',
    'add verifyDepsBeforeRun: false (pnpm run will not wipe manual junctions)'
  );
  // allowBuilds: koffi -> false
  if (/koffi:\s*true/.test(ws)) {
    ws = ws.replace(/koffi:\s*true/, 'koffi: false');
    changed = true;
    log(wsPath, 'set allowBuilds.koffi: false (skip failing source build, use prebuilt binary)');
  } else if (/koffi:\s*false/.test(ws)) {
    actions.push({ file: path.relative(targetDir, wsPath), what: 'allowBuilds.koffi already false', done: true });
  }
  // allowBuilds: subprocess-local -> false
  const subRe = /'@deepseek-ai\/dsh-subprocess-local[^']*':\s*true/;
  if (subRe.test(ws)) {
    ws = ws.replace(subRe, (m) => m.replace(/:\s*true$/, ': false'));
    changed = true;
    log(wsPath, 'set allowBuilds.subprocess-local: false (skip macOS-only postinstall)');
  } else if (/'@deepseek-ai\/dsh-subprocess-local[^']*':\s*false/.test(ws)) {
    actions.push({ file: path.relative(targetDir, wsPath), what: 'allowBuilds.subprocess-local already false', done: true });
  }
  if (changed && !review) fs.writeFileSync(wsPath, ws, 'utf8');
} else {
  log(wsPath, 'SKIP: pnpm-workspace.yaml not found');
}

// ------------------------------------------------- package.json (root)
const rootPkgPath = path.join(targetDir, 'package.json');
const rootPkg = readIfExists(rootPkgPath);
if (rootPkg !== null) {
  try {
    const pkg = JSON.parse(rootPkg);
    const noop = 'node -e "process.exit(0)"';
    const pi = pkg.scripts && pkg.scripts.postinstall;
    if (pi && pi !== noop) {
      const orig = pi;
      pkg.scripts.postinstall = noop;
      if (!review) fs.writeFileSync(rootPkgPath, JSON.stringify(pkg, null, 2) + '\n', 'utf8');
      log(rootPkgPath, `postinstall -> no-op (was: ${orig}) — lefthook git hooks not needed on Windows`);
    } else {
      actions.push({ file: path.relative(targetDir, rootPkgPath), what: pi === noop ? 'postinstall already no-op' : 'no postinstall script', done: true });
    }
  } catch { log(rootPkgPath, 'SKIP: invalid JSON'); }
}

// --------------------------------- subprocess-local/package.json
const subPkgPath = path.join(targetDir, 'packages', 'subprocess', 'subprocess-local', 'package.json');
const subPkg = readIfExists(subPkgPath);
if (subPkg !== null) {
  try {
    const pkg = JSON.parse(subPkg);
    const noop = 'node -e "process.exit(0)"';
    const pi = pkg.scripts && pkg.scripts.postinstall;
    if (pi && pi !== noop) {
      const orig = pi;
      pkg.scripts.postinstall = noop;
      if (!review) fs.writeFileSync(subPkgPath, JSON.stringify(pkg, null, 2) + '\n', 'utf8');
      log(subPkgPath, `postinstall -> no-op (was: ${orig}) — macOS spawn-helper fix, not needed on Windows`);
    } else {
      actions.push({ file: path.relative(targetDir, subPkgPath), what: pi === noop ? 'postinstall already no-op' : 'no postinstall script', done: true });
    }
  } catch { log(subPkgPath, 'SKIP: invalid JSON'); }
}

// ---------------------------------------------------------------- report
console.log('\n=== Windows patch report (target: ' + targetDir + ') ===');
console.log('Mode: ' + (review ? 'REVIEW (no changes made)' : 'APPLY') + '\n');
for (const a of actions) console.log(`  [${a.done ? 'OK ' : review ? '  >' : ' + '}] ${a.file}: ${a.what}`);
if (!actions.length) console.log('  (nothing to do — already patched)');
console.log('\nDone.');
