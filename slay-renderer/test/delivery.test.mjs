import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { validateDelivery } from '../scripts/validate-assets.mjs';
import { glb } from './glb-fixture.mjs';
const catalog = {version: 1, avatars: [{body: 'female'}, {body: 'male'}], poses: ['signature'], facePresets: ['classic'], items: [{id: 'dress', body: 'female', category: 'outfit', hidesRegions: ['torso']}]};
function folder(t) {const root = mkdtempSync(join(tmpdir(), 'slay-delivery-')); t.after(() => rmSync(root, {recursive: true, force: true})); return root;}
function avatar(root, overrides = {}) {
  writeFileSync(join(root, 'female.glb'), glb({asset: {version: '2.0'}, nodes: [{name: 'Head'}, {name: 'region_torso'}], skins: [{joints: [0]}], animations: [{name: 'idle'}, {name: 'signature'}], meshes: [{extras: {targetNames: ['face_classic', 'expression_smile']}}], ...overrides}));
}
test('partial art delivery validates present files without requiring the entire wardrobe', t => {
  const root = folder(t); avatar(root);
  const report = validateDelivery(root, catalog, {partial: true});
  assert.deepEqual(report.summary, {checked: 1, missing: 0, invalid: 0, skipped: 2, warnings: 0});
  assert.equal(validateDelivery(root, catalog).summary.missing, 2);
});
test('unknown bones and ambiguous names fail delivery instead of passing an invalid rig', t => {
  const root = folder(t); avatar(root);
  writeFileSync(join(root, 'dress.glb'), glb({asset: {version: '2.0'}, nodes: [{name: 'DifferentHead'}], skins: [{joints: [0]}]}));
  let report = validateDelivery(root, catalog, {partial: true});
  assert.match(report.files.find(file => file.file === 'dress.glb').errors[0], /unknown female bone/);
  avatar(root, {nodes: [{name: 'Head'}, {name: 'Head'}], skins: [{joints: [0, 1]}]});
  report = validateDelivery(root, catalog, {partial: true});
  assert.match(report.files[0].errors[0], /duplicate bone names/);
});
test('missing animation, morph, mask and thumbnail are actionable report warnings', t => {
  const root = folder(t); avatar(root, {nodes: [{name: 'Head'}], animations: [], meshes: []});
  writeFileSync(join(root, 'dress.glb'), glb({asset: {version: '2.0'}}));
  const report = validateDelivery(root, catalog, {partial: true});
  assert.ok(report.files[0].warnings.some(warning => warning.includes('idle')));
  assert.ok(report.files[0].warnings.some(warning => warning.includes('face_classic')));
  const dress = report.files.find(file => file.file === 'dress.glb');
  assert.ok(dress.warnings.some(warning => warning.includes('region_torso')));
  assert.ok(dress.warnings.some(warning => warning.includes('thumbnail')));
});
test('delivery CLI writes a partial report, strict warnings fail, and an empty batch fails', t => {
  const root = folder(t);
  const actual = JSON.parse(readFileSync(new URL('../../backend/ta-api/src/main/resources/slay/catalog.json', import.meta.url), 'utf8'));
  const file = join(root, 'female.glb');
  const document = {asset: {version: '2.0'}, nodes: [{name: 'Head'}], skins: [{joints: [0]}], animations: ['idle', ...actual.poses].map(name => ({name})), meshes: [{extras: {targetNames: [...actual.facePresets.map(face => 'face_' + face), 'expression_smile']}}]};
  writeFileSync(file, glb(document));
  const cli = fileURLToPath(new URL('../scripts/validate-assets.mjs', import.meta.url));
  const run = (...flags) => spawnSync(process.execPath, ['--experimental-strip-types', cli, root, '--partial', ...flags], {encoding: 'utf8'});
  const reportPath = join(root, 'report.json');
  assert.equal(run('--strict', '--report', reportPath).status, 0);
  assert.equal(JSON.parse(readFileSync(reportPath)).summary.checked, 1);
  document.animations = [];
  writeFileSync(file, glb(document));
  assert.equal(run('--strict').status, 1);
  rmSync(file);
  assert.equal(run().status, 1);
});
