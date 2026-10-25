export function glb(document, binary) {
  const json = Buffer.from(JSON.stringify(document));
  const padded = Buffer.alloc(Math.ceil(json.length / 4) * 4, 0x20); json.copy(padded);
  const size = 20 + padded.length + (binary ? 8 + Math.ceil(binary.length / 4) * 4 : 0);
  const bytes = Buffer.alloc(size);
  bytes.write('glTF'); bytes.writeUInt32LE(2, 4); bytes.writeUInt32LE(size, 8);
  bytes.writeUInt32LE(padded.length, 12); bytes.writeUInt32LE(0x4e4f534a, 16); padded.copy(bytes, 20);
  if (binary) {
    const offset = 20 + padded.length;
    bytes.writeUInt32LE(Math.ceil(binary.length / 4) * 4, offset); bytes.writeUInt32LE(0x004e4942, offset + 4); binary.copy(bytes, offset + 8);
  }
  return bytes;
}
