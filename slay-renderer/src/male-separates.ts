import {BufferAttribute, BufferGeometry, Mesh, Object3D, Raycaster, Vector3} from 'three';

const original = new WeakMap<BufferGeometry, {positions: Float32Array; normals: Float32Array}>();
const waistSections = new WeakMap<Object3D,Map<number,Vector3[][]>>();
const fittedTo = new WeakMap<Object3D, string>();

/** Resolve the selected shirt/trouser overlap in bind space. Both garments
 * then follow their existing shared rig; fitting never runs during animation. */
export function fitMaleSeparates(shirt: Object3D, trousers: Object3D | undefined, tucked: boolean) {
  const key = `${trousers?.uuid ?? 'none'}:${tucked}`;
  if (fittedTo.get(shirt) === key) return;
  let sections=trousers?waistSections.get(trousers):undefined;
  if(trousers&&!sections){
    sections=new Map();
    trousers.traverse(o=>{if(!(o instanceof Mesh)||!o.visible)return;const p=o.geometry.attributes.position,index=o.geometry.index;if(!index)return;
      for(let i=0;i<index.count;i+=3){const triangle=[0,1,2].map(k=>new Vector3().fromBufferAttribute(p,index.getX(i+k))),low=Math.min(...triangle.map(v=>v.y)),high=Math.max(...triangle.map(v=>v.y));if(low>1.26||high<.94)continue;
        for(let bin=Math.floor(Math.max(.94,low)*100);bin<=Math.floor(Math.min(1.26,high)*100);bin++){if(!sections!.has(bin))sections!.set(bin,[]);sections!.get(bin)!.push(triangle);}
      }
    });waistSections.set(trousers,sections);
  }
  const ray = new Raycaster(), direction = new Vector3(),hit=new Vector3();
  shirt.traverse(o => {
    if (!(o instanceof Mesh)) return;
    const geometry = o.geometry, p = geometry.attributes.position as BufferAttribute;
    let saved = original.get(geometry);
    if (!saved) {saved = {positions: new Float32Array(p.array), normals: new Float32Array(geometry.attributes.normal.array)}; original.set(geometry, saved);}
    p.array.set(saved.positions); geometry.attributes.normal.array.set(saved.normals);
    if (trousers) for (let i = 0; i < p.count; i++) {
      const y = p.getY(i); if (y > 1.26 || y < (tucked?1.02:.94)) continue;
      const x = p.getX(i), z = p.getZ(i) - .025, radius = Math.hypot(x, z);
      if (radius < .001 || Math.abs(x) > .3) continue;
      direction.set(x / radius, 0, z / radius); ray.set(new Vector3(0, y, .025), direction);
      const hits:number[]=[];for(const triangle of sections?.get(Math.floor(y*100))??[]){if(ray.ray.intersectTriangle(triangle[0],triangle[1],triangle[2],false,hit))hits.push(hit.distanceTo(ray.ray.origin));}hits.sort((a,b)=>a-b);if(!hits.length)continue;
      const target = tucked ? Math.min(radius, hits[0] - .008) : Math.max(radius, hits[hits.length-1] + .022);
      // Fade an untucked hem into the unchanged torso instead of creating
      // a hard radial step that folds neighbouring triangles into holes.
      const fade=tucked?1:Math.max(0,Math.min(1,(1.26-y)/.13));
      const fitted=radius+(target-radius)*fade;
      p.setXYZ(i, direction.x * fitted, y, .025 + direction.z * fitted);
    }
    p.needsUpdate = true;
    if (trousers) geometry.computeVertexNormals(); else geometry.attributes.normal.needsUpdate = true;
    geometry.computeBoundingBox(); geometry.computeBoundingSphere();
  });
  fittedTo.set(shirt, key);
}
