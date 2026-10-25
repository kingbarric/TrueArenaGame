import { test } from 'node:test';
import assert from 'node:assert/strict';
import { inspectGlb } from '../src/glb.ts';
import { glb } from './glb-fixture.mjs';
const inspect = bytes => inspectGlb(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));

test('valid self-contained binary and data URI resources pass structural preflight', () => {
  const document = {asset: {version: '2.0'}, buffers: [{byteLength: 3}], bufferViews: [{buffer: 0, byteLength: 3}], images: [{uri: 'data:image/png;base64,aA=='}]};
  assert.deepEqual(inspect(glb(document, Buffer.alloc(3))), document);
});
test('malformed chunk boundaries and headers fail before loading', () => {
  assert.throws(() => inspect(Buffer.alloc(4)), /truncated/);
  const bytes = glb({asset: {version: '2.0'}});
  bytes.writeUInt32LE(0xffffffff, 12);
  assert.throws(() => inspect(bytes), /bounds/);
});
test('external textures and unsupported Draco fail explicitly', () => {
  for (const uri of ['textures/skin.png', 'https://example.com/skin.png', 'http://localhost/private']) {
    assert.throws(() => inspect(glb({asset: {version: '2.0'}, images: [{uri}]})), /external buffers\/textures/);
  }
  assert.throws(() => inspect(glb({asset: {version: '2.0'}, extensionsRequired: ['KHR_draco_mesh_compression']})), /Draco/);
});
test('out-of-range joints, duplicate joints and overrunning buffer views fail', () => {
  for (const joints of [[4], [0, 0], [-1]]) {
    assert.throws(() => inspect(glb({asset: {version: '2.0'}, nodes: [{name: 'Head'}], skins: [{joints}]})), /joint/);
  }
  assert.throws(() => inspect(glb({asset: {version: '2.0'}, buffers: [{byteLength: 4}], bufferViews: [{buffer: 0, byteOffset: 3, byteLength: 2}]}, Buffer.alloc(4))), /outside/);
});
test('Meshopt placeholder buffers are accepted and compressed ranges are checked', () => {
  const document = {asset: {version: '2.0'}, extensionsRequired: ['EXT_meshopt_compression'], buffers: [{byteLength: 4}, {byteLength: 48}], bufferViews: [{buffer: 1, byteLength: 48, extensions: {EXT_meshopt_compression: {buffer: 0, byteLength: 4}}}]};
  assert.deepEqual(inspect(glb(document, Buffer.alloc(4))), document);
  document.bufferViews[0].extensions.EXT_meshopt_compression.byteLength = 5;
  assert.throws(() => inspect(glb(document, Buffer.alloc(4))), /compressed view/);
});
