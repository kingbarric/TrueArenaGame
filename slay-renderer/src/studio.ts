import * as T from 'three';

/** Distant dressing-room scenery follows the viewing side, keeping every
 * prop behind the avatar even while the player rotates to inspect an outfit. */
export class StudioBackdrop {
  readonly root = new T.Group();
  constructor() {
    this.root.name = 'studio-backdrop';
    const mat = (color: string, metalness = 0) => new T.MeshStandardMaterial({color, metalness, roughness: metalness ? .4 : .8});
    const cream = mat('#e5d6c8'), rose = mat('#c99798'), gold = mat('#bf9351', .55), wood = mat('#9b7264');
    const add = (geometry: T.BufferGeometry, material: T.Material, x: number, y: number, z: number) => {
      const mesh = new T.Mesh(geometry, material); mesh.position.set(x,y,z); this.root.add(mesh); return mesh;
    };
    // The near edge is three metres away; no wall or furniture enters the
    // styling area or the runway path.
    add(new T.BoxGeometry(8,4,.08), cream, 0,1.7,-4.4);
    add(new T.BoxGeometry(8,.09,2), mat('#e4dbd0'), 0,-.09,-4.1);
    for (const x of [-3.4,-1.25,1.25,3.4]) add(new T.BoxGeometry(.025,3.5,.035),gold,x,1.7,-4.34);
    // Open wardrobe, with a rail and compact colourful garments.
    add(new T.BoxGeometry(1.55,.11,.65),wood,-2.1,.14,-3.8);
    add(new T.BoxGeometry(1.55,.11,.65),wood,-2.1,2.45,-3.8);
    for (const x of [-2.85,-1.35]) add(new T.BoxGeometry(.10,2.3,.65),wood,x,1.3,-3.8);
    const rail = add(new T.CylinderGeometry(.022,.022,1.35,8),gold,-2.1,2.17,-3.72); rail.rotation.z=Math.PI/2;
    for (const [i,color] of ['#b95972','#718d80','#e8bd68','#677494'].entries()) {
      const x=-2.61+i*.34, fabric=mat(color);
      add(new T.BoxGeometry(.29,.62,.07),fabric,x,1.58,-3.65);
      const hanger=add(new T.TorusGeometry(.12,.008,5,12,Math.PI),gold,x,1.96,-3.65);hanger.rotation.z=Math.PI;
    }
    // Warm vanity lights frame a mirror to the far side.
    add(new T.BoxGeometry(.9,1.55,.08),gold,2.1,1.75,-4.05);
    add(new T.BoxGeometry(.81,1.46,.04),mat('#c7c4bc',.3),2.1,1.75,-3.99);
    const bulb=new T.MeshStandardMaterial({color:'#fff0cc',emissive:'#ffd199',emissiveIntensity:.8});
    for (const x of [1.57,2.63]) for (const y of [1.22,1.65,2.08,2.51]) add(new T.SphereGeometry(.065,8,6),bulb,x,y,-3.97);
    add(new T.BoxGeometry(1.28,.09,.55),wood,2.1,.85,-3.8);
    // Flowers sit at the edge of the dressing area, clear of legs and shoes.
    add(new T.CylinderGeometry(.19,.13,.43,12),rose,-1.48,.24,-3.43);
    const green=mat('#648a69'), petal=mat('#e3a2b2'), centre=mat('#e7bf6c');
    for (let i=0;i<5;i++) {
      const x=-1.48+Math.sin(i*2.4)*.16, y=.75+(i%3)*.11, z=-3.43+Math.cos(i*2.4)*.12;
      add(new T.CylinderGeometry(.01,.01,y-.42,5),green,x,(y+.42)/2,z);
      for (let j=0;j<5;j++) {const a=j*Math.PI*2/5;add(new T.SphereGeometry(.064,6,4),petal,x+Math.cos(a)*.074,y+Math.sin(a)*.074,z);}
      add(new T.SphereGeometry(.035,6,4),centre,x,y,z+.035);
    }
  }
  update(camera: T.Camera, background: string) {
    this.root.visible = background === 'studio';
    this.root.rotation.y = Math.atan2(camera.position.x,camera.position.z);
  }
  dispose() {this.root.traverse(o=>{if(o instanceof T.Mesh){o.geometry.dispose();const materials=Array.isArray(o.material)?o.material:[o.material];for(const material of materials)material.dispose();}});}
}
