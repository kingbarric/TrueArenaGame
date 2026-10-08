import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Group, Mesh, BoxGeometry, MeshStandardMaterial } from 'three';
import { presentBody, presentFace } from '../src/presentation.ts';

test('grouped skin receives tint without changing shared wardrobe material', () => {
  const body = new Group(), region = new Group(); region.name = 'region_head';
  const original = new MeshStandardMaterial({color: '#ffffff'});
  const skin = new Mesh(new BoxGeometry(), [original, original]);
  region.add(skin); body.add(region);
  const outfit = new Mesh(new BoxGeometry(), original); body.add(outfit);
  presentBody(body, '#623a27', new Set());
  assert.equal(skin.material[0].color.getHexString(), '623a27');
  assert.equal(skin.material[1].color.getHexString(), '623a27');
  assert.equal(outfit.material.color.getHexString(), 'ffffff');
  const firstMaterial = skin.material[0];
  presentBody(body, '#abcdef', new Set());
  assert.equal(skin.material[0], firstMaterial, 'reuse isolated material rather than leak one per change');
  assert.equal(firstMaterial.color.getHexString(), 'abcdef');
});

test('every mesh/group with a covered region is hidden and restored on unequip', () => {
  const body = new Group();
  const regions = [new Group(), new Mesh(new BoxGeometry(), new MeshStandardMaterial())];
  for (const region of regions) { region.name = 'region_arms'; body.add(region); }
  presentBody(body, '#623a27', new Set(['arms']));
  assert.ok(regions.every(region => !region.visible));
  presentBody(body, '#623a27', new Set());
  assert.ok(regions.every(region => region.visible));
});

test('face presets and expressions stay synchronized across avatar and makeup overlays', () => {
  const root = new Group();
  const meshes = [new Mesh(), new Mesh()];
  for (const mesh of meshes) {
    mesh.morphTargetDictionary = {face_classic: 0, face_soft: 1, expression_smile: 2, other: 3};
    mesh.morphTargetInfluences = [1, 0, 0, .3]; root.add(mesh);
  }
  presentFace(root, 'soft', 'confident');
  assert.deepEqual(meshes.map(mesh => mesh.morphTargetInfluences), [[0, 1, 1, .3], [0, 1, 1, .3]]);
  presentFace(root, 'classic', 'signature');
  assert.deepEqual(meshes.map(mesh => mesh.morphTargetInfluences), [[1, 0, 0, .3], [1, 0, 0, .3]]);
});
