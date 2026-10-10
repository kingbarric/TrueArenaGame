// Parse a GLB with three.js under Node: textures are dropped (no image decoder
// here) so tests and checks exercise the real geometry, skinning and morphs.
import {GLTFLoader} from 'three/addons/loaders/GLTFLoader.js';
import {MeshoptDecoder} from 'three/addons/libs/meshopt_decoder.module.js';

export function loadGlb(file) {
  const length = file.readUInt32LE(12), doc = JSON.parse(file.subarray(20, 20 + length));
  doc.materials = (doc.materials ?? []).map(() => ({pbrMetallicRoughness: {}}));
  delete doc.images; delete doc.textures;
  doc.extensionsUsed = doc.extensionsUsed?.filter(name => name !== 'EXT_texture_webp');
  doc.buffers[0].uri = `data:application/octet-stream;base64,${file.subarray(28 + length).toString('base64')}`;
  globalThis.ProgressEvent ??= class ProgressEvent {};
  return new GLTFLoader().setMeshoptDecoder(MeshoptDecoder).parseAsync(JSON.stringify(doc), '');
}
