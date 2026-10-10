// Sources are downloaded MakeHuman packs; see docs/SLAYHUUD_ASSET_CREDITS.md.
import {femaleWardrobe} from './female-wardrobe.mjs';
import {femaleShoes} from './female-shoes.mjs';
import {femaleBeauty} from './female-beauty.mjs';
import {hairExpansion} from './hair-expansion.mjs';
export const expansion = {
  ...femaleShoes,
  'female-date-cutout': ['female', 'clothes/toigo_cut_out_dress/dress_cut_outs.obj', 'clothes/toigo_cut_out_dress/cutOutDress.png'],
  'female-date-keyhole': ['female', 'clothes/toigo_keyhole_neck_dress/dress_keyhole_neck.obj', 'clothes/toigo_keyhole_neck_dress/ZebraD.png'],
  'female-date-strapless': ['female', 'clothes/toigo_strapless_ruffle_top_dress/dress_strapless_ruffle_top.obj', 'clothes/toigo_strapless_ruffle_top_dress/SkirtRuffleTop.png'],
  'male-dinner-suit': ['male', 'clothes/toigo_suit_with_dinner_jacket/suit_dinner_jacket.obj', 'clothes/toigo_suit_with_dinner_jacket/SuitDinnerJacket.png'],
  'male-bowtie-suit': ['male', 'clothes/toigo_suit_with_jacket_and_bowtie/jacket_bowtie_pants.obj', 'clothes/toigo_suit_with_jacket_and_bowtie/SuitBowtie-diff2.png'],
  'male-tailored-suit': ['male', 'clothes/toigo_male_suit_3/suit3.obj', 'clothes/toigo_male_suit_3/NewSuit3.png'],
  'male-tee-relaxed': ['male', 'clothes/elvs_crude_t-shirt_male/crude_male_shirt.obj', 'clothes/elvs_crude_t-shirt_male/crude_male_tex.png'],
  'male-tee-tucked': ['male', 'clothes/toigo_basic_tucked_t-shirt/t_shirt_basic_tucked.obj', 'clothes/toigo_basic_tucked_t-shirt/T-shirt_basic.png'],
  'male-tee-polo': ['male', 'clothes/namuhekam_male_polo_shirt/Polo_t-shirt.obj', 'clothes/namuhekam_male_polo_shirt/Polo_Base_Color.png'],
  'male-trousers-cargo': ['male', 'clothes/cortu_cargo_pants/cargo_pants.obj', 'clothes/cortu_cargo_pants/cargo_pants_diff.png', {bottom: true}],
  'male-trousers-harem': ['male', 'clothes/toigo_harem_pants/pants_harem.obj', 'clothes/toigo_harem_pants/HaremPants.png', {bottom: true}],
  'male-trousers-denim-shorts': ['male', 'clothes/cortu_jeans_shorts/jean_shorts.obj', 'clothes/cortu_jeans_shorts/jean_shorts_diff.png', {bottom: true}],
  'female-trousers-cargo': ['female', 'clothes/cortu_cargo_pants/cargo_pants.obj', 'clothes/cortu_cargo_pants/cargo_pants_diff.png', {bottom: true}],
  'female-trousers-harem': ['female', 'clothes/toigo_harem_pants/pants_harem.obj', 'clothes/toigo_harem_pants/HaremPants.png', {bottom: true}],
  'female-trousers-denim-shorts': ['female', 'clothes/cortu_jeans_shorts/jean_shorts.obj', 'clothes/cortu_jeans_shorts/jean_shorts_diff.png', {bottom: true}],
  'female-trousers-tailored': ['female', 'clothes/toigo_wool_pants/pants_wool.obj', 'clothes/toigo_wool_pants/Pants_wool.png', {bottom: true}],
  'female-top-camisole': ['female', 'clothes/toigo_camisole_top/camisole_top.obj', 'clothes/toigo_camisole_top/CamisoleTop.png'],
  'female-top-keyhole': ['female', 'clothes/toigo_keyhole_tank_top/tank_keyhole_neck.obj', 'clothes/toigo_keyhole_tank_top/Giraffe.png'],
  'female-top-tee': ['female', 'clothes/joepal_crude_t-shirt_female/crudefemaletshirt.obj', 'clothes/joepal_crude_t-shirt_female/CrudeFemaleTshirtDiffuse.png'],
  'male-trousers-classic': ['male', 'clothes/toigo_wool_pants/pants_wool.obj', 'clothes/toigo_wool_pants/Pants_wool.png', {bottom: true}],
  'female-earrings-hoops': ['female', 'clothes/ews_hoop_earrings/hoop_earrings.obj', 'clothes/ews_hoop_earrings/metal.jpg', {earrings: true}],
  'female-earrings-pearls': ['female', 'clothes/toigo_pearl_earrings/pearl_earrings.obj', 'clothes/toigo_pearl_earrings/Earring.png', {earrings: true}],
  'female-earrings-lightning': ['female', 'clothes/culturalibre_heroine_lightning_earrings/heroine_lightning_earrings.obj', 'clothes/culturalibre_heroine_lightning_earrings/lightning.png', {earrings: true}],
  'female-bag-handbag': ['female', 'clothes/punkduck_handbag01/handbag.obj', 'clothes/punkduck_handbag01/handbag.png', {bag: 'hand'}],
  'female-bag-sling': ['female', 'clothes/elvs_sling_purse1/slingpurse_elv1b.obj', 'clothes/elvs_sling_purse1/pursetex8.png', {bag: 'sling'}],
  'female-bag-tote': ['female', 'clothes/punkduck_shopping_bag01/shoppingbag.obj', 'clothes/punkduck_shopping_bag01/shoppingbag.png', {bag: 'hand'}],
};
for (const body of ['female', 'male']) for (const [name, texture] of [['hazel', 'brownlight'], ['green', 'green'], ['blue', 'deepblue']]) {
  expansion[`${body}-eyes-${name}`] = [body, 'eyes/high-poly/high-poly.obj', `eyes/materials/${texture}_eye.png`, {eyes: true}];
}
for (const [name, colour] of [['ruby', [.55, .015, .06, 1]], ['rose', [.68, .14, .25, 1]], ['plum', [.26, .025, .12, 1]]]) {
  expansion['female-lipstick-' + name] = ['female', 'proxymeshes/female1605/female1605.obj', null, {lips: true, colour}];
}

for (const item of femaleWardrobe) expansion[item.id] = item.asset;
for (const item of femaleBeauty) expansion[item.id] = item.asset;
for (const item of hairExpansion) expansion[item.id] = item.asset;
