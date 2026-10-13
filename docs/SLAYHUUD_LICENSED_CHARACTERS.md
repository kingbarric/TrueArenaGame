# MakeHuman character replacements

Ella (`ella`) now uses Indian Mom's curvy shape. Elisabeth (`beverly`) uses the slim Elisabeth preset; the saved ID stays stable. Chloe (`girl02`) remains the Girl02 preset and now receives the same smoothing of body-region and UV-seam normals. Michael is removed; Alexander (`male`) and Ethan (`indian-male`) remain available. Ethan already uses the requested Indian Male source, verified against the current downloaded preset.

The two new sources reconstruct complete adult bodies in MakeHuman. `.mhm` files are authoring presets, not exported standalone meshes. SlayHuud adapts their shape deltas onto its existing complete MakeHuman body: head, torso, arms, hands, legs and feet. The exact shared topology, skin weights, clothing coverage and five animation clips remain intact. The skins referenced by the female presets are restored and include tint references; hair, skin colours, eyes, face controls and wardrobe selection stay interchangeable. Uniform stature and limited vertical offsets retain compatibility with the shared rig; feet retain their footwear envelope. This is an adaptation, not an unchanged export of either author's scene.

Elisabeth includes twelve CC0 custom targets. Her Nefertiti head morph is intentionally omitted because the source description specifies CC-BY-NC-SA. The remainder of her preset is retained. All source and dependency attribution is in `SLAYHUUD_ASSET_CREDITS.md` and `slay-renderer/scripts/models/elisabeth-dependencies.json`.

The discarded RenderHub/CGTrader conversions and original purchased archives remain private under ignored `slay-renderer/source_assets`; they are absent from the active catalogue and new delivery manifest. No source archive is shipped in the app.

## Rebuild

Use MakeHuman's official `v1.2.0` base and target data, with `makehuman` as the root containing `lib` and `data`. The local authoring checkout is ignored. From the project root:

```sh
blender -b --python slay-renderer/scripts/convert-model-variants.py -- slay-renderer/source_assets/makehuman/authoring/makehuman app/assets/slay_renderer/assets ella beverly girl02
node slay-renderer/scripts/apply-character-skins.mjs
node slay-renderer/scripts/fit-preview-underwear.mjs ella beverly girl02
node slay-renderer/scripts/repair-wardrobe-coverage.mjs
node slay-renderer/scripts/crop-hoodie-dress.mjs
blender -b --python slay-renderer/scripts/render-character-portraits.py
```

From `slay-renderer`:

```sh
npm run build
npm test
npm run dev -- --port 5173
```

The preview at `http://127.0.0.1:5173/character-preview.html` lists Ella (curvy), Elisabeth (slim), Chloe, Ethan and Alexander. Female models show fitted bras and briefs with long hair. Ella uses shaped strapless cups with a lower support band; Elisabeth and Chloe retain bandeau bras. The catwalk lowers the arms beside the torso with restrained opposite swings. The underwear is cut from each finished body, with interpolated skin weights and surface clearance, so the original warped waistband and unsupported straps do not expose skin. Skin selection, poses, rotation and catwalk use the actual game renderer. Fresh cache versions prevent showing a previous conversion.

The fixture app uses `lib/slayhuud_preview.dart` with `SLAY_ASSET_BASE=http://localhost:8932/`, served locally from `website/slay-assets`. It does not sign in or write to production. Builds verify compressed geometry against each source, including triangle order and masks. Tests cover the complete rig, topology, wardrobe fits and poses; these do not replace visual review of every garment combination or physical-device profiling.

The old patterned dress remains replaced by the Little Black Dress under its existing saved IDs `female-essential` and `female-dress-collection-9`.

Wardrobe coverage, drape and seam repairs are documented in `SLAYHUUD_WARDROBE_FIT_REVIEW.md`.
