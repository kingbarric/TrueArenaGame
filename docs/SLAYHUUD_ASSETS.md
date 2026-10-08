# SlayHuud: 3D asset delivery guide

The engine and wardrobe catalogue are ready to receive production artwork. Supply a coherent shared rig for each avatar body. Separate purchased garments made for unrelated characters will not automatically fit.

## First delivery: enough to replace the mannequins

- `female.glb`, `male.glb`: fully rigged base avatars, clothed in a neutral modest base layer.
- Five complete looks for each body: filenames match the existing catalogue IDs, such as `female-essential.glb`, `female-executive.glb`, `female-owambe.glb`, `female-premiere.glb`, `female-date.glb` and their male equivalents.
- Matching hair and shoes; start with `female-hair-0.glb`, `male-hair-0.glb`, `shoe-0.glb`.
- Accessories including `accessory-0.glb` (check the catalogue's category before modelling).
- Portrait wardrobe thumbnails: `<item-id>.webp`.

The complete list of IDs/categories/tags lives in `backend/ta-api/src/main/resources/slay/catalog.json`. This manifest is shared with Flutter and the standalone renderer. Its current catalogue is 74 items; the initial delivery can be smaller while `developmentAssets` remains enabled. Missing production items must be completed or removed from the enabled catalogue before switching that flag off.

## Rig, scale and coordinates

Export GLB 2.0 with Y up, metres, feet at Y=0, height approximately 1.8 m, centred at X=Z=0 and facing +Z. Apply root transforms before export. The camera assumes this scale; do not export centimetres or an extra rotated/scaled scene root.

Clothing must have the same skeleton bone names, compatible bind poses and inverse bind matrices as the body it fits. The renderer binds garments to the avatar's live bones while preserving garment inverse bind matrices. Deliver skin weights and vertex deformation ready to use; the engine does not generate or repair garment weights.

`rigVersion` identifies each base rig. Freeze it for a content batch. Bone names alone are insufficient to prove fitting: test bend/pose deformation visually. Unisex accessories can use rigid meshes. For rigged clothing on different body proportions, use separate male/female catalogue entries and models even if their colours/name are shared.

## Body masking and attachments

Name separate body mesh regions `region_torso`, `region_arms`, `region_legs`, `region_head`, etc. Item `hidesRegions` names those suffixes. The renderer hides covered skin to prevent clipping and restores it when clothes change. Every matching body mesh in a region should be under that named group. Do not name outfit meshes `region_*`.

Use `attachmentBone` for a rigid attachment, such as an earring on a named head bone or a bag on a hand. The GLB transform is local to that bone. Skinned garments normally leave this field null and bind to the shared skeleton.

## Materials, face, makeup and poses

Use glTF PBR materials; textures/materials belong inside the GLB wherever practical. The renderer changes skin colour on `region_*` skin meshes, so their material should support tinting and should not be shared with hair/clothes. Model skin and eye/mouth detail to look good at the face camera distance.

Face morph names: `face_classic`, `face_soft`, `face_angular`. Expression morph: `expression_smile` (applied for confident/celebrate looks). Facial expressions can also be baked into pose clips.

Makeup uses a supplied facial overlay GLB in the `makeup` category. Align it to the matching face/rig, supply alpha textures and prevent depth fighting. The renderer treats it as a garment/attachment; no procedural photorealistic makeup is generated from an icon or a name. Verify every supported face morph and skin tone. If face geometry changes between presets, the overlay must carry compatible deformation.

Put these named animation clips in each base avatar GLB: `idle`, `signature`, `confident`, `editorial`, `celebrate`. The current renderer reads clips from the base GLB, not separate animation files. Poses should remain within the platform/camera framing. Cloth simulation is not performed; export convincing garment geometry, weights and baked motion.

## Export and performance budgets

Preferred: compressed GLB with Meshopt geometry and KTX2/Basis textures. The Meshopt decoder and KTX2 transcoders are already bundled. Draco-compressed meshes require adding a decoder first.

Initial targets, to be refined on real devices: base avatar below ~40k triangles, ordinary outfit below ~20k, accessory below ~5k; 1k/2k textures for most items; avatar GLB around 3–5 MB and ordinary garments below ~2 MB. These are content targets, not guarantees of device performance. The current hard loader limit is 32 MB per GLB and the persistent GLB cache is 32 MB total.

Avoid hidden duplicate bodies inside clothing, unnecessary material slots, large transparent layers and 4k maps on small accessories. Export previews from front, side and back. Use consistent lighting in thumbnails so the wardrobe feels like one collection.

## Validation and wiring

From `slay-renderer`, run:

```sh
node scripts/validate-assets.mjs /absolute/path/to/delivery
```

It checks GLB headers, size, named avatar skeletons, matching garment bone names, attachment bones, required clips and thumbnails, and reports missing catalogue files. It does not certify art quality, skin weights, bone bind poses or visual fit; those need inspection in the studio.

Populate each avatar's `assetUrl` and each item's `assetUrl`/`thumbnailUrl` with versioned HTTPS URLs. The loader also supports assets bundled on the same origin, but their files must actually be added to the Flutter asset bundle. Cross-origin asset servers need appropriate CORS headers for the loopback WebView origin and screenshot export. Prefer self-contained GLBs so caching does not depend on unversioned external textures.

Increase `version` when changing the enabled catalogue. Run `npm run build` to refresh the Flutter bundle. Keep `developmentAssets=true` until all enabled models work; set it false after the art/fit/device review. Missing production assets then fail explicitly instead of substituting a mannequin.

No additional Blender/Unity runtime is needed in the app. Blender or another DCC tool is used to author/export assets; Three.js handles them at runtime.
