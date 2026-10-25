import {BufferAttribute, Mesh, Object3D, Vector3} from 'three';

export type FitField = {version:number;avatarId:string;body:string;samples:number[][];deltas:number[][]};
type Node = {index:number;axis:number;left?:Node;right?:Node};

/** Apply a character's continuous fit once as an item is loaded, before it is
 * bound to the live rig. A spatial index avoids a full body scan per vertex. */
export class VariantFit {
  private tree?:Node;
  private field:FitField;
  constructor(field:FitField) {
    this.field=field;
    if(field.version!==1 || field.samples.length!==field.deltas.length || !field.samples.length) throw Error('Invalid avatar fit');
    const build=(indices:number[],depth:number):Node|undefined=>{
      if(!indices.length)return undefined;
      const axis=depth%3;indices.sort((a,b)=>field.samples[a][axis]-field.samples[b][axis]);const middle=indices.length>>1;
      return {index:indices[middle],axis,left:build(indices.slice(0,middle),depth+1),right:build(indices.slice(middle+1),depth+1)};
    };
    this.tree=build(field.samples.map((_,i)=>i),0);
  }
  offset(point:Vector3):Vector3 {
    const p=point.toArray(),near:{index:number;distance:number}[]=[];
    const visit=(node?:Node)=>{
      if(!node)return;
      const sample=this.field.samples[node.index],distance=sample.reduce((sum,x,i)=>sum+(x-p[i])**2,0);
      near.push({index:node.index,distance});near.sort((a,b)=>a.distance-b.distance);if(near.length>4)near.pop();
      const difference=p[node.axis]-sample[node.axis];visit(difference<0?node.left:node.right);
      if(near.length<4||difference*difference<=near[near.length-1].distance)visit(difference<0?node.right:node.left);
    };
    visit(this.tree);
    if(near[0].distance<1e-12)return new Vector3().fromArray(this.field.deltas[near[0].index]);
    const result=new Vector3();let total=0;
    for(const n of near){const weight=1/Math.max(n.distance,1e-6);total+=weight;result.addScaledVector(new Vector3().fromArray(this.field.deltas[n.index]),weight);}
    return result.multiplyScalar(1/total);
  }
  apply(root:Object3D) {
    root.traverse(object=>{
      if(!(object instanceof Mesh))return;
      const geometry=object.geometry;
      const positions=geometry.getAttribute('position') as BufferAttribute;
      for(let i=0;i<positions.count;i++){
        const point=new Vector3().fromBufferAttribute(positions,i);point.add(this.offset(point));positions.setXYZ(i,point.x,point.y,point.z);
      }
      positions.needsUpdate=true;geometry.computeVertexNormals();geometry.computeBoundingBox();geometry.computeBoundingSphere();
    });
  }
}
