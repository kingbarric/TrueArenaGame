# Wardrobe fit repairs — 13 October 2026

Catalogue version 31 keeps the same six characters and wardrobe item IDs.

## Repairs

- Supplemented incomplete author coverage masks for every delivered clothing mesh. Horizontal garment intersections add only fully enclosed body faces; original masks remain. The same masks are copied to each character sharing the body topology. Head and foot boundaries are preserved, and bottom masks retain exposed waist skin.
- Black cocktail dresses now cover the thighs during walking and the neckline/bust-side skin that previously appeared through the cloth.
- Female clothing receives a modest bind-space bridge beneath the bust, capped at 8 mm to preserve textures, openings and garment shape. This is geometric shaping, not cloth simulation.
- Trouser centre-seam vertices fade to pelvis weights, preventing opposite thighs from pulling coincident crotch vertices apart during a stride. Outer leg weights remain intact.
- Untucked male hems fade smoothly into the torso fit. A cached horizontal triangle index keeps fitting independent of the full trouser triangle count.
- Floor-length skirts/trains conceal feet and selected shoes rather than allowing them to show through the cloth. Switching to a shorter outfit restores them. Shoe selection and scoring remain unchanged.
- Local preview includes all six characters and four outfit sets per body: everyday/dress, separates, suit/long dress and relaxed/cut-out.

## Verification and scope

The factorized audit covers all 239 unique delivered models on their compatible avatars: 858 avatar/model fits. Every model is checked through idle, four fashion poses and 25 gait samples for finite, bounded geometry and shared rig compatibility. All 36,972 catalogue top/bottom pairs (including colour variants) exercise mask unions and skin restoration. All 260 distinct male shirt/trouser fit pairs are evaluated; a separate final seam pass uses the latest fitting code.

This does **not** mean all 36,972 pairs received visual inspection or exhaustive triangle collision tests. Geometry reused by colour aliases is inspected once; accessories are checked on compatible characters independently, rather than enumerating the enormous full cartesian product of hair, face, colour, shoes and accessory selections. Face controls, shoe height, garment layering and accessory bindings also have dedicated existing tests.

Visual review covered four outfit sets per character (24 looks), front/back views and sampled walking frames. Regression tests check the corrected black dress on all four women through all poses and 49 gait samples, centre-seam weights and floor-length footwear concealment. All 81 renderer tests and the renderer build pass. The recorded audit summary is `docs/fixtures/slay-wardrobe-fit-audit.json`.

## Rebuild and repeat

After authoring/converting bodies and garments, before publishing:

```sh
npm --prefix slay-renderer run assets:repair-coverage
npm --prefix slay-renderer run fits:audit
npm --prefix slay-renderer run build
npm --prefix slay-renderer test
```

The coverage repair is additive and repeatable. If changing its inference policy, regenerate clean authored body masks before applying it, so superseded inferred faces are not retained. Publish the generated immutable art to Cloudflare R2 before pushing a backend manifest that references it. Main deploys to test; production remains on release.

## Character entry and hoodie correction (catalogue 32)

Non-career studio entry now opens the shared full character picker before styling. Freestyle allows the theme's eligible bodies; competition entry allows avatars of the player's joined body. The initial patch retained the old one-character policy; catalogue 33 supersedes it with selection before every career event.

The source Hoodie Dress was ankle-length. Its skirt is clipped at 0.73 m into a mini-dress, preserving interpolated UVs, normals and normalized skin weights. Its indexed leg masks are trimmed using the canonical female topology and copied to the compatible variants. The updated thumbnail reflects the short hem. Run `node slay-renderer/scripts/crop-hoodie-dress.mjs` after conversion/coverage repair and before rebuilding delivery assets.

Verification: 82 renderer tests, 19 character/career/wardrobe tests and clean analysis of the three changed screens. The asset and feed test files passed a focused 21-test rerun after a stale generated test bundle and a countdown failure in the busy full-suite run. The full initial run had 394 passes and two failures; it was not recorded as an all-pass run.

## Installed renderer and saved career correction (catalogue 33)

Saved career and Daily Slay events now open the shared character picker. The authenticated `/slay/career/character` endpoint changes the active star without clearing XP, scores, stars, wardrobe or progress. The old start endpoint retains its duplicate-start protection.

Delivery quantization stores its decode transform in inverse bind matrices. Spatial garment fitting previously edited normalized compressed coordinates as metres. The renderer now restores the common bind-space transform into float vertices and corrects inverse binds before fitting, draping and footwear checks. Source-only preview tests could not detect this. New tests compare fitted, rebound compressed garments with their source preview and check exposed legs on every short/casual dress and colour variant across four women.

Loopback responses are marked no-store and the renderer URL has a new revision to avoid retaining an older page across app upgrades. Verification: 85 renderer tests, ten character/career Flutter tests, clean static analysis, nine backend catalogue/scoring unit tests and one career switching integration test on disposable local PostgreSQL/Redis. Simulator visual inspection covered Hoodie, Easy Day and Sunny Day dresses. Midi dresses and gowns retain their designed lengths pending any requested design change.

Female separates now fit the lower top inside the selected trouser/skirt waistband, using the authored metre-space surface after delivery decoding. The reproduced Everyday Tee / Ribbon Shorts back overlap has a regression test on four female characters, five poses and 25 gait samples.
