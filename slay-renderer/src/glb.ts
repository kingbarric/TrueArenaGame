export const MAX_ASSET_BYTES = 32 * 1024 * 1024;
export type GlbDocument = {
  asset: {version: string};
  nodes?: {name?: string}[];
  skins?: {joints: number[]}[];
  animations?: {name?: string}[];
  buffers?: {uri?: string; byteLength: number}[];
  bufferViews?: {buffer: number; byteOffset?: number; byteLength: number; extensions?: {EXT_meshopt_compression?: {buffer: number; byteOffset?: number; byteLength: number}}}[];
  images?: {uri?: string}[];
  extensionsRequired?: string[];
  meshes?: {extras?: {targetNames?: string[]}}[];
};

// Shared runtime/delivery preflight, not a full glTF or visual-fit certificate.
export function inspectGlb(bytes: ArrayBuffer): GlbDocument {
  if (bytes.byteLength > MAX_ASSET_BYTES) throw Error('exceeds the 32 MB renderer asset limit');
  if (bytes.byteLength < 20) throw Error('truncated GLB header');
  const view = new DataView(bytes);
  if (view.getUint32(0, true) !== 0x46546c67 || view.getUint32(4, true) !== 2 || view.getUint32(8, true) !== bytes.byteLength) throw Error('invalid GLB 2 header');
  let offset = 12, document: GlbDocument | undefined, binaryLength = 0, chunks = 0, hasBinary = false;
  while (offset < bytes.byteLength) {
    if (offset + 8 > bytes.byteLength) throw Error('truncated GLB chunk header');
    const length = view.getUint32(offset, true), type = view.getUint32(offset + 4, true);
    const start = offset + 8, end = start + length;
    if (length % 4 || end > bytes.byteLength) throw Error('invalid GLB chunk bounds/alignment');
    if (chunks === 0 && type !== 0x4e4f534a) throw Error('first GLB chunk must be JSON');
    if (type === 0x4e4f534a) {
      if (document) throw Error('duplicate JSON chunk');
      document = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(new Uint8Array(bytes, start, length)).trim());
    } else if (type === 0x004e4942) {
      if (hasBinary) throw Error('duplicate binary chunk');
      binaryLength = length; hasBinary = true;
    }
    offset = end; chunks++;
  }
  if (!document || document.asset?.version !== '2.0') throw Error('missing glTF 2.0 asset metadata');
  for (const resource of [...(document.buffers ?? []), ...(document.images ?? [])]) {
    if (resource.uri && !resource.uri.startsWith('data:')) throw Error('external buffers/textures are unsupported; embed them in the GLB');
  }
  if (document.extensionsRequired?.includes('KHR_draco_mesh_compression')) throw Error('Draco compression is unsupported; export Meshopt or uncompressed geometry');
  for (const [index, buffer] of (document.buffers ?? []).entries()) {
    if (!Number.isInteger(buffer.byteLength) || buffer.byteLength < 0) throw Error('invalid buffer length');
    // Meshopt permits URI-less placeholder buffers above index zero; these
    // describe decompressed storage, not another embedded binary chunk.
    const fallback = index > 0 && document.extensionsRequired?.includes('EXT_meshopt_compression') &&
      (document.bufferViews ?? []).filter(view => view.buffer === index).every(view => view.extensions?.EXT_meshopt_compression) &&
      !(document.bufferViews ?? []).some(view => view.extensions?.EXT_meshopt_compression?.buffer === index);
    if (!buffer.uri && !fallback && (index !== 0 || !hasBinary || buffer.byteLength > binaryLength || binaryLength - buffer.byteLength > 3)) throw Error('embedded buffer does not match the binary chunk');
  }
  for (const bufferView of document.bufferViews ?? []) {
    const buffer = document.buffers?.[bufferView.buffer], start = bufferView.byteOffset ?? 0;
    if (!buffer || !Number.isInteger(start) || !Number.isInteger(bufferView.byteLength) || start < 0 || bufferView.byteLength < 0 || start + bufferView.byteLength > buffer.byteLength) throw Error('buffer view extends outside its buffer');
    const compressed = bufferView.extensions?.EXT_meshopt_compression;
    if (compressed) {
      const source = document.buffers?.[compressed.buffer], offset = compressed.byteOffset ?? 0;
      if (!source || !Number.isInteger(offset) || offset < 0 || !Number.isInteger(compressed.byteLength) || compressed.byteLength < 0 || offset + compressed.byteLength > source.byteLength) throw Error('compressed view extends outside its buffer');
    }
  }
  for (const skin of document.skins ?? []) {
    if (!Array.isArray(skin.joints) || !skin.joints.length || new Set(skin.joints).size !== skin.joints.length) throw Error('invalid or duplicate skin joints');
    for (const joint of skin.joints) if (!Number.isInteger(joint) || joint < 0 || !document.nodes?.[joint]) throw Error('skin joint references an absent node');
  }
  return document;
}
