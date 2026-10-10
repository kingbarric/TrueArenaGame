import {Color, Mesh, MeshStandardMaterial, Object3D} from 'three';

// Tint only wardrobe materials. Keep texture detail through luminance rather
// than multiplying a red dye by a blue texture and turning the garment black.
export function applyItemColour(root: Object3D, colour: string | undefined,
  palette: Record<string, string>) {
  if (colour && !Object.hasOwn(palette, colour)) throw Error('Unknown wardrobe colour');
  root.traverse(object => {
    if (!(object instanceof Mesh)) return;
    for (const material of Array.isArray(object.material) ? object.material : [object.material]) {
      if (!(material instanceof MeshStandardMaterial)) continue;
      let uniforms = material.userData.slayDye as {enabled: {value: number}; tint: {value: Color}} | undefined;
      if (!uniforms && !colour) continue;
      if (!uniforms) {
        uniforms = {enabled: {value: 0}, tint: {value: new Color()}};
        material.userData.slayDye = uniforms;
        const dye = uniforms;
        material.onBeforeCompile = shader => {
          shader.uniforms.slayDyeEnabled = dye.enabled;
          shader.uniforms.slayDyeTint = dye.tint;
          shader.fragmentShader = 'uniform float slayDyeEnabled;\nuniform vec3 slayDyeTint;\n' + shader.fragmentShader;
          shader.fragmentShader = shader.fragmentShader.replace('#include <map_fragment>',
            `#include <map_fragment>
             if (slayDyeEnabled > 0.5) {
               float fabric = dot(diffuseColor.rgb, vec3(0.2126, 0.7152, 0.0722));
               diffuseColor.rgb = slayDyeTint * clamp(0.35 + fabric * 0.65, 0.35, 1.0);
             }`);
        };
        material.customProgramCacheKey = () => 'slay-wardrobe-dye-v1';
        material.needsUpdate = true;
      }
      uniforms.enabled.value = colour ? 1 : 0;
      if (colour) uniforms.tint.value.set(palette[colour]);
    }
  });
}
