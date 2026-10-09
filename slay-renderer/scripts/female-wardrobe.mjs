// Distinct downloaded silhouettes plus named fabric/colour variations.
// Prices are earned PlayHuud coins; four choices in each set start free.
const clothes = 'clothes/';
const sources = {
  shift: ['toigo_shift_dress/dress_shift.obj', 'toigo_shift_dress/ShiftDress.png'],
  sundress: ['toigo_camisole_dress_with_full_skirt/dress_camisole_full_skirt.obj', 'toigo_camisole_dress_with_full_skirt/CamisoleDressUV.png'],
  tiers: ['toigo_dress_with_tiered_skirt/dresstierskirt.obj', 'toigo_dress_with_tiered_skirt/DressTierSkirt.png'],
  ruffle: ['toigo_bodice_dress_with_lace_ruffle_skirt/dress_bodice_ruffle_skirt.obj', 'toigo_bodice_dress_with_lace_ruffle_skirt/SkirtLaceRuffle.png'],
  flapper: ['aethelraed_flapper_dress/flapper_dress_1.obj', 'aethelraed_flapper_dress/flapper_dress_green.png'],
  mini: ['frankyaye_mini_skirt_01/mini_skirt_01.obj', 'frankyaye_mini_skirt_01/mini_skirt_01_diffuse.png'],
  wrap: ['frankyaye_mini_skirt_02/mini_skirt_02.obj', 'frankyaye_mini_skirt_02/mini_skirt_01_diffuse.png'],
  leather: ['toigo_tiered_mini_skirt/tier_skirt_mini.obj', 'toigo_tiered_mini_skirt/SkirtMini-blackLeather.png'],
  midi: ['toigo_tiered_skirt/tier_skirt.obj', 'toigo_tiered_skirt/ShadesTex-PINK.png'],
  lace: ['toigo_skirt_with_lace_ruffle/skirt_full_lace_ruffle.obj', 'toigo_skirt_with_lace_ruffle/LaceRuffleSkirt.png'],
  maxi: ['toigo_long_full_skirt/skirt_full_long.obj', 'toigo_long_full_skirt/skirtFullLong.png'],
  tee: ['joepal_crude_t-shirt_female/crudefemaletshirt.obj', 'joepal_crude_t-shirt_female/CrudeFemaleTshirtDiffuse.png'],
  cami: ['toigo_camisole_top/camisole_top.obj', 'toigo_camisole_top/CamisoleTop.png'],
  tank: ['toigo_keyhole_tank_top/tank_keyhole_neck.obj', 'toigo_keyhole_tank_top/Giraffe.png'],
  halter: ['toigo_turtleneck_halter_top/turtleneck_halter.obj', 'toigo_turtleneck_halter_top/ShadesTex-PINK.png'],
  tube: ['skalldyrssuppe_tube_top_funky_colors/tube_top.obj', 'skalldyrssuppe_tube_top_funky_colors/tube_top_diff.png'],
  bodice: ['toigo_bodice-style_top/bodice_style_top.obj', 'toigo_bodice-style_top/Bodice.png'],
  cargo: ['cortu_cargo_pants/cargo_pants.obj', 'cortu_cargo_pants/cargo_pants_diff.png'],
  harem: ['toigo_harem_pants/pants_harem.obj', 'toigo_harem_pants/HaremPants.png'],
  denim: ['cortu_jeans_shorts/jean_shorts.obj', 'cortu_jeans_shorts/jean_shorts_diff.png'],
  tailored: ['toigo_wool_pants/pants_wool.obj', 'toigo_wool_pants/Pants_wool.png'],
};
const warm = [1,.80,.72,1], cool=[.70,.85,1,1], olive=[.68,.78,.48,1], muted=[.62,.62,.68,1];
const sets = {
  dress: [
    ['shift','Weekend Shift',['casual'],['black']],
    ['sundress','Sunny Day Dress',['casual','summer','romantic'],['purple']],
    ['tiers','Tiered Day Dress',['casual','party'],['white','pink']],
    ['ruffle','Ruffle Mini Dress',['casual','romantic','party'],['pink']],
    ['shift','Office Shift',['corporate','casual'],['grey'],{tint:muted}],
    ['sundress','Sunset Sundress',['casual','summer','romantic'],['orange'],{tint:warm}],
    ['tiers','Cool Tiered Dress',['casual','party'],['blue'],{tint:cool}],
    ['ruffle','Blush Ruffle Dress',['casual','romantic','party'],['pink'],{tint:warm}],
    ['flapper','Everyday Flapper',['casual'],['green']],
    ['shift','Olive Weekend Dress',['casual','corporate'],['green'],{tint:olive}],
  ],
  skirts: [
    ['mini','Plaid Mini',['casual','streetwear'],['red','black']],
    ['wrap','Side-split Mini',['casual','party'],['red','black']],
    ['leather','Tiered Leather Mini',['casual','party'],['black']],
    ['midi','Pink Tiered Skirt',['casual','romantic'],['pink']],
    ['lace','Lace Ruffle Skirt',['party','romantic'],['white']],
    ['maxi','Flowing Maxi Skirt',['casual','summer'],['purple']],
    ['mini','Warm Plaid Mini',['casual','streetwear'],['brown'],{tint:warm}],
    ['wrap','Charcoal Split Mini',['casual','party'],['grey'],{tint:muted}],
    ['midi','Cool Tiered Skirt',['casual','romantic'],['purple'],{tint:cool}],
    ['maxi','Sunset Maxi Skirt',['casual','summer'],['orange'],{tint:warm}],
  ],
  tops: [
    ['tee','Cropped Everyday Tee',['casual','streetwear'],['white'],{crop:1.18}],
    ['cami','Weekend Camisole',['casual','romantic'],['pink']],
    ['tank','Printed Tank',['casual','summer'],['brown']],
    ['tube','Colour Pop Tube Top',['casual','party'],['purple']],
    ['halter','Halter Crop Top',['casual','party','romantic'],['pink']],
    ['bodice','Bodice Top',['romantic','party'],['black']],
    ['tee','Cool Crop Tee',['casual','streetwear'],['blue'],{crop:1.18,tint:cool}],
    ['cami','Evening Camisole',['romantic','elegant'],['orange'],{tint:warm}],
    ['tank','Muted Printed Tank',['casual','corporate'],['grey'],{tint:muted}],
    ['tube','Warm Colour Pop Top',['casual','party'],['orange'],{tint:warm}],
  ],
  trousers: [
    ['cargo','Weekend Cargo Pants',['casual','streetwear'],['grey']],
    ['harem','Relaxed Lounge Pants',['casual'],['black']],
    ['denim','Weekend Denim Shorts',['casual','summer'],['blue']],
    ['tailored','Office Wool Trousers',['corporate','formal'],['grey']],
    ['cargo','Olive Cargo Pants',['casual','streetwear'],['green'],{tint:olive}],
    ['harem','Warm Lounge Pants',['casual','party'],['brown'],{tint:warm}],
    ['denim','Warm Denim Shorts',['casual','summer'],['brown'],{tint:warm}],
    ['tailored','Evening Trousers',['corporate','formal'],['blue'],{tint:cool}],
    ['cargo','Charcoal Cargo Pants',['casual','streetwear'],['grey'],{tint:muted}],
    ['harem','Cool Lounge Pants',['casual'],['blue'],{tint:cool}],
  ],
};
export const femaleWardrobe = Object.entries(sets).flatMap(([category, rows]) => rows.map(([source,name,tags,colours,options={}],index) => {
  const [obj,texture]=sources[source];
  return {id:`female-${category}-collection-${index+1}`, name, category, tags, colours,
    asset:['female', clothes+obj, clothes+texture, {...options,...(category==='trousers'?{bottom:true}:{})}],
    price:index<4?0:[40,60,80,100,120,150][index-4]};
}));
