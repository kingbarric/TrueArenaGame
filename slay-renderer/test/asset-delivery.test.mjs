import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {compressGlb, verifyCompressed} from '../scripts/compress-assets.mjs';

const read = path => readFileSync(new URL(`../../${path}`, import.meta.url));
const catalog = JSON.parse(read('backend/ta-api/src/main/resources/slay/catalog.json'));
const manifest = JSON.parse(read('backend/ta-api/src/main/resources/slay/asset-manifest.json'));

test('the delivery manifest covers every catalogue file under a content-hashed name', () => {
  const paths = [...catalog.avatars.map(a => a.assetUrl), ...catalog.items.flatMap(i => [i.assetUrl, i.thumbnailUrl])]
    .filter(path => path?.startsWith('assets/'));
  for (const path of paths) {
    const file = manifest.files[path];
    assert.ok(file, `${path} missing from asset-manifest.json; run npm run build`);
    assert.match(file.name, new RegExp(`\\.${file.sha256.slice(0, 16)}\\.(glb|png)$`));
  }
  assert.match(manifest.base, /^https:\/\/.+\/$/);
});

test('the bundled starter pack matches the manifest and can dress a new look offline', () => {
  const bundled = Object.entries(manifest.files).filter(([, file]) => file.bundled);
  for (const [path, file] of bundled) {
    const bytes = read(`app/assets/slay_renderer/starter/${path.split('/').pop()}`);
    assert.equal(createHash('sha256').update(bytes).digest('hex'), file.sha256, path);
  }
  for (const path of ['assets/female.glb', 'assets/male.glb', 'assets/female-hair-0.glb', 'assets/male-hair-0.glb']) {
    assert.equal(manifest.files[path]?.bundled, true, path);
  }
  const glbBytes = bundled.filter(([path]) => path.endsWith('.glb')).reduce((sum, [, file]) => sum + file.bytes, 0);
  assert.ok(glbBytes < 4e6, `starter models grew to ${(glbBytes / 1e6).toFixed(1)} MB`);
});

test('compression keeps the coverage-mask triangle order and refuses a reordered mesh', async () => {
  const source = read('app/assets/slay_renderer/assets/female.glb');
  const compressed = await compressGlb(source);
  assert.ok(compressed.length < source.length / 4);
  await verifyCompressed(source, compressed);
  // A source whose first two triangles swap places must not verify against it.
  const length = source.readUInt32LE(12), doc = JSON.parse(source.subarray(20, 20 + length));
  const region = doc.meshes.findIndex(mesh => mesh.name === 'region_torso');
  const accessor = doc.accessors[doc.meshes[region].primitives[0].indices];
  const view = doc.bufferViews[accessor.bufferView], start = 28 + length + (view.byteOffset ?? 0) + (accessor.byteOffset ?? 0);
  const swapped = Buffer.from(source), size = accessor.componentType === 5125 ? 4 : 2;
  swapped.copy(swapped, start, start + 3 * size, start + 6 * size);
  source.copy(swapped, start + 3 * size, start, start + 3 * size);
  await assert.rejects(verifyCompressed(swapped, compressed), /triangles changed/);
});
