import { BufferAttribute, Mesh, Object3D } from 'three';

const originals = new WeakMap<Mesh, {index: BufferAttribute; key: string}>();

/** Apply authored garment masks once per outfit change, in the bind mesh.
 * Skinning then moves the remaining exposed skin normally in every pose. */
export function coverBody(body: Object3D, items: string[]) {
  const key = [...items].sort().join('|');
  body.traverse(object => {
    if (!(object instanceof Mesh) || !object.name.startsWith('region_')) return;
    const masks = object.userData.slayCoverage as Record<string, number[]> | undefined;
    if (!masks) return;
    let original = originals.get(object);
    if (!original) {
      // Each generated body region owns its geometry and masking state.
      if (!object.geometry.index) throw Error('Garment coverage requires indexed body geometry');
      original = {index: object.geometry.index!, key: ''};
      originals.set(object, original);
    }
    if (original.key === key) return;
    const hidden = new Set(items.flatMap(id => masks[id] ?? []));
    if (!hidden.size) object.geometry.setIndex(original.index);
    else {
      const indices: number[] = [];
      for (let i = 0; i < original.index.count; i += 3) {
        if (hidden.has(i / 3)) continue;
        indices.push(original.index.getX(i), original.index.getX(i + 1), original.index.getX(i + 2));
      }
      object.geometry.setIndex(indices);
    }
    original.key = key;
  });
}
