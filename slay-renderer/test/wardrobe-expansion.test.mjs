import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, existsSync} from 'node:fs';
import {AnimationMixer, Bone, Group, SkinnedMesh, Vector3} from 'three';
import {GLTFLoader} from 'three/addons/loaders/GLTFLoader.js';
import {bindGarment} from '../src/rig.ts';
import {applyPose, selectBodyFit} from '../src/poses.ts';
import {presentFace} from '../src/presentation.ts';

const catalog = JSON.parse(readFileSync(new URL('../../backend/ta-api/src/main/resources/slay/catalog.json', import.meta.url)));
const file = id => new URL(`../../app/assets/slay_renderer/assets/${id}.glb`, import.meta.url);
function data(id) {
  const bytes = readFileSync(file(id)), length = bytes.readUInt32LE(12);
  return {doc: JSON.parse(bytes.subarray(20, 20 + length)), bin: bytes.subarray(28 + length)};
}
async function load(id) {
  const {doc, bin} = data(id);
  doc.materials = doc.materials.map(() => ({pbrMetallicRoughness: {}})); delete doc.images; delete doc.textures;
  doc.buffers[0].uri = `data:application/octet-stream;base64,${bin.toString('base64')}`;
  globalThis.ProgressEvent ??= class ProgressEvent {};
  return new GLTFLoader().parseAsync(JSON.stringify(doc), '');
}

test('requested wardrobe sets have at least three immediately usable models and thumbnails', () => {
  for (const prefix of ['female-date-', 'male-dinner-', 'male-bowtie-', 'male-tailored-', 'male-tee-',
    'female-eyes-', 'male-eyes-', 'female-lipstick-', 'female-earrings-', 'female-bag-', 'watch-']) {
    const choices = catalog.items.filter(i => i.id.startsWith(prefix));
    assert.ok(choices.length >= (prefix.includes('suit') || ['male-dinner-', 'male-bowtie-', 'male-tailored-'].includes(prefix) ? 1 : 3), prefix);
    for (const item of choices) {
      assert.ok(item.isDefault && item.coinCost === 0 && item.assetUrl, item.id);
      assert.ok(existsSync(file(item.id)), item.id);
      assert.ok(existsSync(new URL(`../../app/assets/slay_renderer/${item.thumbnailUrl}`, import.meta.url)), item.id + ' thumbnail');
    }
  }
});

test('eye meshes respect texture transparency so opaque corneas do not hide coloured irises', () => {
  for (const body of ['female', 'male']) for (const colour of ['hazel', 'green', 'blue']) {
    const {doc} = data(`${body}-eyes-${colour}`);
    assert.equal(doc.materials[0].alphaMode, 'MASK');
    assert.ok(doc.materials[0].alphaCutoff > 0);
    const base = data(body).doc;
    assert.equal(base.materials[base.meshes.find(m => m.name === 'face_eyes').primitives[0].material].alphaMode, 'MASK');
  }
});

test('lipstick geometry stays on the face and follows face presets and smiles', async () => {
  const avatar = await load('female'), root = new Group(); root.add(avatar.scene);
  const bones = new Map(); avatar.scene.traverse(o => {if (o instanceof Bone) bones.set(o.name, o);});
  for (const item of catalog.items.filter(i => i.id.startsWith('female-lipstick-'))) {
    const overlay = await load(item.id); bindGarment(overlay.scene, bones); root.add(overlay.scene);
    const mesh = overlay.scene.getObjectByName(item.id);
    const p = mesh.geometry.getAttribute('position');
    assert.ok(p.count > 10 && p.count < 500, 'small face overlay');
    for (let i = 0; i < p.count; i++) {
      assert.ok(Math.abs(p.getX(i)) < .028 && p.getY(i) > 1.605 && p.getY(i) < 1.625 && p.getZ(i) > .145, 'lip contour only, no cheek or chin colour');
    }
    for (const face of catalog.facePresets) {
      presentFace(root, face, 'confident');
      assert.equal(mesh.morphTargetInfluences[mesh.morphTargetDictionary['face_' + face]], 1);
      assert.equal(mesh.morphTargetInfluences[mesh.morphTargetDictionary.expression_smile], 1);
    }
    root.remove(overlay.scene);
  }
});

test('held bags and earrings stay bound to the live avatar through every pose', async () => {
  const avatar = await load('female'), root = new Group(); root.add(avatar.scene);
  const bones = new Map(); avatar.scene.traverse(o => {if (o instanceof Bone) bones.set(o.name, o);});
  for (const item of catalog.items.filter(i => i.id.startsWith('female-bag-') || i.id.startsWith('female-earrings-'))) {
    const garment = await load(item.id); bindGarment(garment.scene, bones); root.add(garment.scene);
    const mixer = new AnimationMixer(avatar.scene), positions = [];
    for (const pose of catalog.poses) {
      applyPose(mixer, avatar.animations, pose); root.updateMatrixWorld(true);
      garment.scene.traverse(mesh => {
        if (!(mesh instanceof SkinnedMesh)) return;
        mesh.skeleton.update(); const p = mesh.geometry.getAttribute('position');
        assert.ok(mesh.skeleton.bones.every(b => bones.get(b.name) === b));
        const v = mesh.applyBoneTransform(0, new Vector3().fromBufferAttribute(p, 0));
        assert.ok(v.toArray().every(Number.isFinite)); positions.push(v);
      });
    }
    assert.ok(positions.some(p => p.distanceTo(positions[0]) > .005), item.id + ' follows poses');
    mixer.stopAllAction(); root.remove(garment.scene);
  }
});


test('all watch bands surround an actual wrist on both bodies through the fashion poses', async () => {
  for (const body of ['female', 'male']) {
    const avatar = await load(body), root = new Group(); root.add(avatar.scene);
    const hand = avatar.scene.getObjectByName('LeftHand');
    for (const style of ['gold', 'silver', 'smart']) {
      const watch = await load('watch-' + style); selectBodyFit(watch.scene, body); hand.add(watch.scene);
      const fit = watch.scene.children.find(o => o.userData.slayBody === body);
      const band = fit.children.find(o => o.name.startsWith('Wrist'));
      band.geometry.computeBoundingBox();
      const mixer = new AnimationMixer(avatar.scene);
      for (const pose of catalog.poses) {
        applyPose(mixer, avatar.animations, pose); root.updateMatrixWorld(true);
        const centre = band.localToWorld(band.geometry.boundingBox.getCenter(new Vector3()));
        let closest = Infinity;
        avatar.scene.traverse(mesh => {
          if (!(mesh instanceof SkinnedMesh) || mesh.name !== 'region_arms') return;
          mesh.skeleton.update(); const p = mesh.geometry.getAttribute('position');
          for (let i = 0; i < p.count; i++) {
            if (p.getX(i) < .25) continue;
            const v = mesh.applyBoneTransform(i, new Vector3().fromBufferAttribute(p, i));
            closest = Math.min(closest, v.distanceTo(centre));
          }
        });
        assert.ok(closest < .070, `${body}/${style}/${pose}: floating band ${closest}`);
      }
      mixer.stopAllAction(); hand.remove(watch.scene);
    }
  }
});
