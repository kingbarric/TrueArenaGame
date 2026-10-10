import {BufferAttribute, BufferGeometry, DoubleSide, Mesh, MeshBasicMaterial, Object3D, Raycaster, Vector3} from 'three';

const original = new WeakMap<BufferGeometry, {positions: Float32Array; normals: Float32Array}>();
const fittedTo = new WeakMap<Object3D, string>();

/** Resolve the selected shirt/trouser overlap in bind space. Both garments
 * then follow their existing shared rig; fitting never runs during animation. */
export function fitMaleSeparates(shirt: Object3D, trousers: Object3D | undefined, tucked: boolean) {
  const key = `${trousers?.uuid ?? 'none'}:${tucked}`;
  if (fittedTo.get(shirt) === key) return;
  const material = new MeshBasicMaterial({side: DoubleSide}), surfaces: Mesh[] = [];
  trousers?.traverse(o => {if (o instanceof Mesh) {const surface = new Mesh(o.geometry, material); surface.updateMatrixWorld(true); surfaces.push(surface);}});
  const ray = new Raycaster(), direction = new Vector3();
  shirt.traverse(o => {
    if (!(o instanceof Mesh)) return;
    const geometry = o.geometry, p = geometry.attributes.position as BufferAttribute;
    let saved = original.get(geometry);
    if (!saved) {saved = {positions: new Float32Array(p.array), normals: new Float32Array(geometry.attributes.normal.array)}; original.set(geometry, saved);}
    p.array.set(saved.positions); geometry.attributes.normal.array.set(saved.normals);
    if (trousers) for (let i = 0; i < p.count; i++) {
      const y = p.getY(i); if (y > 1.26 || y < 1.02) continue;
      const x = p.getX(i), z = p.getZ(i) - .025, radius = Math.hypot(x, z);
      if (radius < .001 || Math.abs(x) > .3) continue;
      direction.set(x / radius, 0, z / radius); ray.set(new Vector3(0, y, .025), direction);
      const hits = ray.intersectObjects(surfaces, false); if (!hits.length) continue;
      const target = tucked ? Math.min(radius, hits[0].distance - .008) : Math.max(radius, hits[hits.length-1].distance + .022);
      p.setXYZ(i, direction.x * target, y, .025 + direction.z * target);
    }
    p.needsUpdate = true;
    if (trousers) geometry.computeVertexNormals(); else geometry.attributes.normal.needsUpdate = true;
    geometry.computeBoundingBox(); geometry.computeBoundingSphere();
  });
  material.dispose(); fittedTo.set(shirt, key);
}
