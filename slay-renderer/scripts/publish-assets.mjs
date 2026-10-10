// Prepares SlayHuud art for delivery from the source files in
// app/assets/slay_renderer/assets (which the app no longer bundles):
//   - every GLB compressed (and verified against its source), every thumbnail
//     palette-packed, written under a content-hashed name to website/slay-assets
//     for playhuud.com to serve as immutable files;
//   - the starter pack (both bodies, their first hairstyle, all thumbnails)
//     copied to app/assets/slay_renderer/starter so a fresh install styles offline;
//   - asset-manifest.json mapping each catalogue path to its hashed file.
import {createHash} from 'node:crypto';
import {existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync} from 'node:fs';
import {basename, extname} from 'node:path';
import sharp from 'sharp';
import {compressGlb, verifyCompressed} from './compress-assets.mjs';

const SOURCE = '../app/assets/slay_renderer/';
const STARTER = '../app/assets/slay_renderer/starter/';
const PUBLISHED = '../website/slay-assets/';
const CACHE = '.asset-cache/';
const DEFAULT_BASE = 'https://playhuud.com/slay-assets/';
/** A new look is a body plus its first hairstyle (SlayLook.initial). */
const STARTER_ITEMS = new Set(['female-hair-0', 'male-hair-0']);

const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');

async function deliver(path) {
  const source = readFileSync(SOURCE + path), cached = CACHE + sha256(source) + extname(path);
  if (existsSync(cached)) return readFileSync(cached);
  let output;
  if (path.endsWith('.glb')) {
    output = await compressGlb(source);
    await verifyCompressed(source, output);
  } else if (path.endsWith('.png')) {
    const packed = await sharp(source).png({palette: true, quality: 90, effort: 10, compressionLevel: 9}).toBuffer();
    output = packed.length < source.length ? packed : source;
  } else output = source;
  writeFileSync(cached, output);
  return output;
}

export async function publishAssets(catalog, {log = console.log} = {}) {
  const starter = new Set(catalog.avatars.map(avatar => avatar.assetUrl));
  const paths = new Set(catalog.avatars.map(avatar => avatar.assetUrl));
  for (const item of catalog.items) {
    if (item.assetUrl) paths.add(item.assetUrl);
    if (item.thumbnailUrl) { paths.add(item.thumbnailUrl); starter.add(item.thumbnailUrl); }
    if (item.assetUrl && STARTER_ITEMS.has(item.id)) starter.add(item.assetUrl);
  }
  for (const directory of [CACHE, PUBLISHED]) mkdirSync(directory, {recursive: true});
  rmSync(STARTER, {recursive: true, force: true}); mkdirSync(STARTER, {recursive: true});

  const files = {};
  let sourceBytes = 0, deliveredBytes = 0, bundledBytes = 0;
  for (const path of [...paths].filter(path => path?.startsWith('assets/')).sort()) {
    const bytes = await deliver(path), hash = sha256(bytes), extension = extname(path);
    const name = `${basename(path, extension)}.${hash.slice(0, 16)}${extension}`;
    if (!existsSync(PUBLISHED + name)) writeFileSync(PUBLISHED + name, bytes);
    const bundled = starter.has(path);
    if (bundled) { writeFileSync(STARTER + basename(path), bytes); bundledBytes += bytes.length; }
    files[path] = {name, sha256: hash, bytes: bytes.length, bundled};
    sourceBytes += readFileSync(SOURCE + path).length; deliveredBytes += bytes.length;
  }
  const manifest = {base: DEFAULT_BASE, files};
  log(`slay assets: ${Object.keys(files).length} files, ${(sourceBytes / 1e6).toFixed(1)} MB source → ` +
    `${(deliveredBytes / 1e6).toFixed(1)} MB delivered, ${(bundledBytes / 1e6).toFixed(1)} MB bundled in the app`);
  const current = new Set(Object.values(files).map(file => file.name));
  const stale = readdirSync(PUBLISHED).filter(name => !current.has(name));
  // Older hashed files stay published: installed apps on an older catalogue still request them.
  if (stale.length) log(`slay assets: ${stale.length} older published files kept in ${PUBLISHED}`);
  return manifest;
}
