#!/usr/bin/env node
/**
 * make-icon.mjs — Generate <repo>/dsh.ico from the repo's favicon.svg.
 *
 * Pipeline: sharp (resolvable from <repo>/node_modules, already installed by
 * the installer) renders the SVG at 16/24/32/48/64/128/256 px, and the PNGs
 * are packed into a multi-size ICO container (Vista+ ICO supports raw PNG
 * entries, so no image encoder other than sharp is needed — no Pillow,
 * no cairosvg, no Python).
 *
 * Usage: node make-icon.mjs <repoDir>
 * Output: <repoDir>/dsh.ico
 */
import { createRequire } from 'node:module';
import path from 'node:path';
import fs from 'node:fs';

const repo = path.resolve(process.argv[2] || process.cwd());
const req = createRequire(path.join(repo, 'package.json'));
const SIZES = [16, 24, 32, 48, 64, 128, 256];

/** Pack an array of {size, pngBuffer} into a Windows .ico (PNG entries). */
function buildIco(pngs) {
  const count = pngs.length;
  const header = Buffer.alloc(6);
  header.writeUInt16LE(0, 0); // reserved
  header.writeUInt16LE(1, 2); // type = icon
  header.writeUInt16LE(count, 4);
  const entries = [];
  let offset = 6 + 16 * count;
  for (const p of pngs) {
    const e = Buffer.alloc(16);
    e.writeUInt8(p.size >= 256 ? 0 : p.size, 0); // 0 means 256
    e.writeUInt8(p.size >= 256 ? 0 : p.size, 1);
    e.writeUInt8(0, 2);  // palette
    e.writeUInt8(0, 3);  // reserved
    e.writeUInt16LE(1, 4);   // planes
    e.writeUInt16LE(32, 6);  // bits per pixel
    e.writeUInt32LE(p.png.length, 8);
    e.writeUInt32LE(offset, 12);
    offset += p.png.length;
    entries.push(e);
  }
  return Buffer.concat([header, ...entries, ...pngs.map((p) => p.png)]);
}

(async () => {
  const sharp = req('sharp');
  const favicon = path.join(repo, 'website', 'public', 'favicon.svg');
  if (!fs.existsSync(favicon)) {
    console.error('favicon.svg not found at ' + favicon);
    process.exit(1);
  }
  const svg = fs.readFileSync(favicon);
  const pngs = [];
  for (const size of SIZES) {
    const png = await sharp(svg).resize(size, size).png().toBuffer();
    pngs.push({ size, png });
  }
  const ico = buildIco(pngs);
  const out = path.join(repo, 'dsh.ico');
  fs.writeFileSync(out, ico);
  console.log('wrote ' + out + ' (' + ico.length + ' bytes, ' + SIZES.length + ' sizes)');
})().catch((e) => { console.error('icon generation failed: ' + e.message); process.exit(1); });
