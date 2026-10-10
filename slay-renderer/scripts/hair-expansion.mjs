// Distinct source silhouettes, not colour aliases. Existing IDs/prices remain
// intact; see bundled credits for CC0 and attributed CC-BY hair sources.
const system = (body, id, name, source, cost, colours = ['brown']) => ({
  id: `${body}-hair-${id}`, name, body, cost, colours,
  asset: [body, `hair/${source}/${source}.obj`, `hair/${source}/${source}_diffuse.png`],
});
const community = (body, id, name, folder, mesh, texture, cost, colours = ['brown']) => ({
  id: `${body}-hair-${id}`, name, body, cost, colours,
  asset: [body, `hair/${folder}/${mesh}.obj`, `hair/${folder}/${texture}`],
});
const cornrows = (body, cost) => community(body, 'cornrows', 'Beaded Cornrows',
  'elvs_braided_rows', 'cornrowsofelv5', 'mh_cornrowstex1.png', cost, ['burgundy']);
const bun = (body, cost) => community(body, 'braided-bun', 'Braided Top Knot',
  'elvs_reverse_french_braid_bun', 'rev_fr_braidbun1', 'braid01_diffuse_grapewash.png', cost, ['black', 'purple']);
export const hairExpansion = [
  system('female', 'pixie', 'Textured Pixie', 'short02', 0),
  community('female', 'fringe-bob', 'Blunt Fringe Bob', 'toigo_blunt_bob_with_bangs', 'bob_blunt_bangs', 'AuburnHair.png', 0, ['auburn']),
  bun('female', 60),
  community('female', 'curls', 'Tousled Curls', 'elvs_inverted_curly_bob', 'elvs_inverted_curlybob1', 'elvs_inverted_curlybob1.png', 100),
  cornrows('female', 80),
  community('female', 'vintage-updo', 'Vintage Updo', 'elvs_50s_updo', 'elv_50supdo1', 'patsytex1.png', 0),
  system('male', 'textured', 'Textured Crop', 'short02', 0),
  system('male', 'side-sweep', 'Side Sweep', 'short03', 0),
  system('male', 'slick-back', 'Slick Back', 'short04', 0, ['black']),
  community('male', 'messy', 'Messy Shag', 'cortu_short_messy_hair', 'short_messy', 'short_messy_diff.png', 40),
  community('male', 'layered', 'Layered Fringe', 'culturalibre_hair_05', 'hair_05', 'hair_05.png', 60),
  community('male', 'spiked', 'Spiked Quiff', 'elvs_maxwell_hair', 'maxwell_hair_mh', 'maxhairtex6.png', 80, ['black', 'red']),
  community('male', 'pompadour', 'Swept Pompadour', 'elvs_grump_hair', 'elvs_grumphair', 'elvs_grumphair.png', 100),
  cornrows('male', 80),
  bun('male', 120),
];
