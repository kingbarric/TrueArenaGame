import { readFileSync, existsSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { inspectGlb } from '../src/glb.ts';

export function validateDelivery(root, catalog, {partial = false} = {}) {
  const files = [], rigs = new Map();
  const inspect = (name, check) => {
    const record = {file: name, status: 'ok', errors: [], warnings: []}; files.push(record);
    const path = resolve(root, name);
    if (!existsSync(path)) { record.status = partial ? 'skipped' : 'missing'; return; }
    try {
      const bytes = readFileSync(path);
      const document = inspectGlb(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
      record.bytes = bytes.byteLength;
      const names = (document.skins ?? []).flatMap(skin => skin.joints.map(joint => document.nodes[joint].name));
      if (names.some(name => !name?.trim())) throw Error('every skeleton bone must have a name');
      // A bone may appear in several skins, but different nodes cannot share its name.
      const joints = new Set((document.skins ?? []).flatMap(skin => skin.joints));
      if (new Set([...joints].map(joint => document.nodes[joint].name)).size !== joints.size) throw Error('ambiguous duplicate bone names');
      check(document, new Set(names), record);
    } catch (error) { record.status = 'invalid'; record.errors.push(error.message); }
  };
  for (const avatar of catalog.avatars) inspect(avatar.body + '.glb', (document, bones, record) => {
    if (!bones.size) throw Error('base avatar must have a named skeleton');
    const regions = new Set((document.nodes ?? []).filter(node => node.name?.startsWith('region_')).map(node => node.name.slice(7)));
    rigs.set(avatar.body, {bones, regions});
    const clips = new Set((document.animations ?? []).map(clip => clip.name));
    for (const clip of ['idle', ...catalog.poses]) if (!clips.has(clip)) record.warnings.push('animation missing: ' + clip);
    const morphs = new Set((document.meshes ?? []).flatMap(mesh => mesh.extras?.targetNames ?? []));
    for (const name of [...catalog.facePresets.map(face => 'face_' + face), 'expression_smile']) {
      if (!morphs.has(name)) record.warnings.push('morph missing: ' + name);
    }
  });
  for (const item of catalog.items) inspect(item.id + '.glb', (document, bones, record) => {
    const targets = item.body === 'unisex' ? ['male', 'female'] : [item.body];
    for (const body of targets) {
      const rig = rigs.get(body);
      if (!rig) { record.warnings.push('cannot verify compatibility without valid ' + body + '.glb'); continue; }
      for (const bone of bones) if (!rig.bones.has(bone)) throw Error('unknown ' + body + ' bone: ' + bone);
      if (item.attachmentBone && !rig.bones.has(item.attachmentBone)) throw Error('attachment bone absent in ' + body + ': ' + item.attachmentBone);
      for (const region of item.hidesRegions ?? []) if (!rig.regions.has(region)) record.warnings.push(body + ' body mask missing: region_' + region);
    }
    if (!existsSync(resolve(root, item.id + '.webp'))) record.warnings.push('thumbnail missing: ' + item.id + '.webp');
    const target = item.category === 'outfit' ? 2 : 1;
    if (record.bytes > target * 1024 * 1024) record.warnings.push('above suggested ' + target + ' MB item budget');
  });
  const count = status => files.filter(file => file.status === status).length;
  const summary = {checked: count('ok') + count('invalid'), missing: count('missing'), invalid: count('invalid'), skipped: count('skipped'), warnings: files.reduce((sum, file) => sum + file.warnings.length, 0)};
  return {catalogVersion: catalog.version, partial, files, summary};
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2), root = args.shift();
  let partial = false, strict = false, reportPath, invalidArgs = false;
  while (args.length) {
    const arg = args.shift();
    if (arg === '--partial') partial = true;
    else if (arg === '--strict') strict = true;
    else if (arg === '--report') {
      reportPath = args.shift();
      if (!reportPath || reportPath.startsWith('--')) invalidArgs = true;
    } else invalidArgs = true;
  }
  if (!root || root.startsWith('--') || invalidArgs) {
    console.error('Usage: node --experimental-strip-types scripts/validate-assets.mjs /path/to/delivery [--partial] [--strict] [--report /path/to/report.json]');
    process.exitCode = 1;
  } else {
    const catalog = JSON.parse(readFileSync(new URL('../../backend/ta-api/src/main/resources/slay/catalog.json', import.meta.url), 'utf8'));
    const report = validateDelivery(root, catalog, {partial});
    for (const file of report.files) {
      console.log(file.status.toUpperCase() + ' ' + file.file);
      for (const error of file.errors) console.log('  ERROR ' + error);
      for (const warning of file.warnings) console.log('  WARN ' + warning);
    }
    if (reportPath) writeFileSync(resolve(reportPath), JSON.stringify(report, null, 2) + '\n');
    const {checked, missing, invalid, skipped, warnings} = report.summary;
    console.log(`Delivery check: ${checked} checked, ${missing} missing, ${invalid} invalid, ${skipped} skipped, ${warnings} warnings.`);
    process.exitCode = missing || invalid || !checked || (strict && warnings) ? 1 : 0;
  }
}
