import { Color, Material, Mesh, Object3D } from 'three';

// Clone skin materials once: artists may reuse a material across several meshes.
// Tinting the skin must never recolour a garment that shares that material.
const isolatedSkin = new WeakSet<Mesh>();
export function presentBody(body: Object3D, skinTone: string, hiddenRegions: Set<string>) {
  body.traverse(object => {
    if (object.name.startsWith('region_')) {
      object.visible = !hiddenRegions.has(object.name.slice('region_'.length));
    }
    if (!(object instanceof Mesh)) return;
    let region: Object3D | null = object;
    while (region && region !== body && !region.name.startsWith('region_')) region = region.parent;
    if (!region?.name.startsWith('region_')) return;
    if (!isolatedSkin.has(object)) {
      object.material = Array.isArray(object.material)
        ? object.material.map(material => material.clone()) : object.material.clone();
      isolatedSkin.add(object);
    }
    const materials: Material[] = Array.isArray(object.material) ? object.material : [object.material];
    for (const material of materials) {
      const colour = (material as Material & {color?: Color}).color;
      // Baked skin already contains its base colour. Multiplying it by a
      // second dark brown makes the face nearly black; tint relative to the
      // source skin's tone instead, while keeping its facial detail.
      if ((material as Material & {map?: unknown}).map) {
        const chosen = new Color(skinTone), base = new Color('#623a27');
        colour?.setRGB(chosen.r / base.r, chosen.g / base.g, chosen.b / base.b);
      } else colour?.set(skinTone);
    }
  });
}

export function presentFace(root: Object3D, facePreset: string, pose: string) {
  root.traverse(object => {
    if (!(object instanceof Mesh) || !object.morphTargetDictionary || !object.morphTargetInfluences) return;
    for (const [name, index] of Object.entries(object.morphTargetDictionary)) {
      if (name.startsWith('face_')) object.morphTargetInfluences[index] = name === 'face_' + facePreset ? 1 : 0;
      if (name.startsWith('expression_')) {
        object.morphTargetInfluences[index] = name === 'expression_smile' && ['confident', 'celebrate'].includes(pose) ? 1 : 0;
      }
    }
  });
}

export function presentEyes(body: Object3D, replacement: boolean) {
  body.traverse(object => {
    if (object.name === 'face_eyes') object.visible = !replacement;
  });
}

/** Base underwear stays visible until a garment covers that part of the body. */
export function presentUnderwear(body: Object3D, slots: Set<string>) {
  const full = slots.has('outfit') || slots.has('dress');
  const top = full || slots.has('tops') || slots.has('shirts');
  const bottom = full || slots.has('trousers') || slots.has('skirts');
  const bra = body.getObjectByName('starter_bra'), briefs = body.getObjectByName('starter_briefs');
  if (bra) bra.visible = !top;
  if (briefs) briefs.visible = !bottom;
}
