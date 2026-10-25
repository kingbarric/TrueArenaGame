// Delivery compression for SlayHuud GLBs: quantized Meshopt geometry and WebP
// textures. Triangle order is never changed — body coverage masks address
// triangles by index — so this deliberately skips reorder/simplify/weld.
import {NodeIO} from '@gltf-transform/core';
import {ALL_EXTENSIONS, EXTMeshoptCompression} from '@gltf-transform/extensions';
import {quantize, textureCompress, dedup} from '@gltf-transform/functions';
import {MeshoptDecoder, MeshoptEncoder} from 'meshoptimizer';
import sharp from 'sharp';
import {SkinnedMesh, Mesh, Vector3} from 'three';
import {loadGlb} from './glb-node.mjs';

let io;
async function nodeIO() {
  if (!io) {
    await Promise.all([MeshoptDecoder.ready, MeshoptEncoder.ready]);
    io = new NodeIO().registerExtensions(ALL_EXTENSIONS)
      .registerDependencies({'meshopt.decoder': MeshoptDecoder, 'meshopt.encoder': MeshoptEncoder});
  }
  return io;
}

/** @returns compressed GLB bytes for one source GLB. */
export async function compressGlb(source) {
  const io = await nodeIO();
  const document = await io.readBinary(new Uint8Array(source));
  await document.transform(
    dedup({propertyTypes: ['Texture']}),
    // 14-bit positions are ~0.1 mm on a 2 m avatar; weights keep 8 bits per joint.
    quantize({quantizePosition: 14, quantizeNormal: 10, quantizeTexcoord: 12, quantizeWeight: 8}),
    textureCompress({encoder: sharp, targetFormat: 'webp', quality: 85, resize: [1024, 1024]}),
  );
  document.createExtension(EXTMeshoptCompression).setRequired(true)
    .setEncoderOptions({method: EXTMeshoptCompression.EncoderMethod.QUANTIZE});
  return Buffer.from(await io.writeBinary(document));
}

function describe(scene) {
  const meshes = [];
  scene.updateMatrixWorld(true);
  scene.traverse(object => {
    if (!(object instanceof Mesh)) return;
    const geometry = object.geometry, index = geometry.index;
    // Meshopt's lossless index codec may rotate a triangle's corners; only the
    // triangle's identity at each position matters to the coverage masks.
    const triangles = [];
    for (let i = 0; index && i < index.count; i += 3) {
      triangles.push([index.getX(i), index.getX(i + 1), index.getX(i + 2)].sort((a, b) => a - b).join(','));
    }
    const positions = [], vertex = new Vector3();
    for (let i = 0; i < geometry.attributes.position.count; i++) {
      vertex.fromBufferAttribute(geometry.attributes.position, i);
      if (object instanceof SkinnedMesh) object.applyBoneTransform(i, vertex);
      positions.push(vertex.clone().applyMatrix4(object.matrixWorld));
    }
    meshes.push({
      name: object.name,
      skinned: object instanceof SkinnedMesh,
      bones: object instanceof SkinnedMesh ? object.skeleton.bones.map(bone => bone.name) : [],
      morphs: Object.keys(object.morphTargetDictionary ?? {}),
      userData: JSON.stringify(object.userData),
      triangles, positions,
    });
  });
  return meshes;
}

/** Throws unless the compressed GLB keeps every name, bone, morph, mask and triangle of its source. */
export async function verifyCompressed(source, compressed, {tolerance = 0.001} = {}) {
  const [a, b] = await Promise.all([loadGlb(source), loadGlb(compressed)]);
  const before = describe(a.scene), after = describe(b.scene);
  if (before.length !== after.length) throw Error(`mesh count changed: ${before.length} → ${after.length}`);
  before.forEach((mesh, m) => {
    const other = after[m], label = mesh.name || `mesh ${m}`;
    for (const key of ['name', 'skinned', 'userData']) {
      if (mesh[key] !== other[key]) throw Error(`${label}: ${key} changed`);
    }
    for (const key of ['bones', 'morphs', 'triangles']) {
      if (mesh[key].length !== other[key].length || mesh[key].some((value, i) => value !== other[key][i])) {
        throw Error(`${label}: ${key} changed`);
      }
    }
    if (mesh.positions.length !== other.positions.length) throw Error(`${label}: vertex count changed`);
    let worst = 0;
    mesh.positions.forEach((p, i) => { worst = Math.max(worst, p.distanceTo(other.positions[i])); });
    if (worst > tolerance) throw Error(`${label}: vertices moved up to ${(worst * 1000).toFixed(2)} mm`);
  });
  const clips = gltf => gltf.animations.map(clip => clip.name).join('|');
  if (clips(a) !== clips(b)) throw Error('animation clips changed');
}
