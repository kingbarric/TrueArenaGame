// Career stage wardrobes. Every piece belongs to exactly one stage, so each
// stage has its own set. Curated MakeHuman garments (stage-wardrobe-bases.mjs)
// come first; each category is then filled to ten with colour variants in the
// stage's palette: catalogue entries that reuse a garment model from the same or
// a neighbouring stage and are dyed at runtime. In each category the last three are 4★/5★ career rewards.
import {bases} from './stage-wardrobe-bases.mjs';

export const STAGES = ['Starter Studio', 'City Style', 'Nightlife', 'Luxury Events', 'Fashion Week'];
const STAGE_TAGS = [['casual', 'streetwear'], ['corporate', 'elegant', 'formal'], ['evening', 'party'],
  ['elegant', 'formal', 'luxury'], ['evening', 'formal', 'luxury']];
const PRICES = [40, 60, 90, 130, 180];
export const PER_CATEGORY = 10;

/** [name, sRGB hex, colour tag] per stage. */
export const PALETTES = [
  [['Bubblegum', '#ff8fb8', 'pink'], ['Sky', '#6cc4ff', 'blue'], ['Lime', '#9be15d', 'green'], ['Sunshine', '#ffd23f', 'yellow'],
    ['Tangerine', '#ff9a3c', 'orange'], ['Denim', '#4a6fa5', 'blue'], ['Lilac', '#b49cff', 'purple'], ['Mint', '#7ce0c3', 'green'], ['Cherry', '#e23d5b', 'red'], ['Cloud', '#f2f2f7', 'white']],
  [['Navy', '#23395d', 'navy'], ['Camel', '#c19a6b', 'brown'], ['Charcoal', '#4a4a4f', 'grey'], ['Ivory', '#efe6d2', 'white'],
    ['Burgundy', '#7a1f34', 'red'], ['Olive', '#6b7043', 'green'], ['Powder Blue', '#9db8d9', 'blue'], ['Taupe', '#8b7d6b', 'brown'], ['Slate', '#5b6878', 'grey'], ['Blush', '#e6b8b0', 'pink']],
  [['Neon Pink', '#ff2e93', 'pink'], ['Electric Blue', '#2e5bff', 'blue'], ['Violet', '#7a2eff', 'purple'], ['Silver', '#c9ccd6', 'grey'],
    ['Hot Red', '#e0182d', 'red'], ['Emerald Glow', '#00a86b', 'green'], ['Disco Gold', '#d4af37', 'gold'], ['Midnight', '#1b1f3b', 'navy'], ['Ultraviolet', '#5d1aa8', 'purple'], ['Glitter Black', '#151515', 'black']],
  [['Champagne', '#e8d3a2', 'gold'], ['Burgundy Velvet', '#6d1a2c', 'red'], ['Emerald', '#046a4f', 'green'], ['Sapphire', '#0f3d8a', 'blue'],
    ['Ruby', '#9b111e', 'red'], ['Pearl', '#f3efe6', 'white'], ['Royal Purple', '#5a2a82', 'purple'], ['Onyx', '#2a2420', 'black'], ['Rose Gold', '#b76e79', 'pink'], ['Midnight Navy', '#14213d', 'navy']],
  [['Ivory', '#f6f1e7', 'white'], ['Chrome', '#d9dde3', 'grey'], ['Fuchsia', '#d6249f', 'pink'], ['Cobalt', '#0047ab', 'blue'],
    ['Saffron', '#f4c430', 'yellow'], ['Jet', '#121212', 'black'], ['Coral', '#ff6f61', 'orange'], ['Teal', '#008080', 'green'], ['Lavender', '#b57edc', 'purple'], ['Scarlet', '#c8102e', 'red']],
];

/** Categories each stage fills to ten, per avatar body. */
const FILLED = {
  female: Array(5).fill(['dress', 'tops', 'trousers', 'skirts', 'shoes']),
  male: [['shirts', 'trousers', 'shoes'], ['shirts', 'trousers', 'shoes'], ['shirts', 'trousers', 'shoes'],
    ['outfit', 'shirts', 'trousers', 'shoes'], ['outfit', 'shirts', 'trousers', 'shoes']],
};

const slug = text => text.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
const asItem = ([stage, body, category, name, tags, colours, folder, obj, texture, credit, options]) => ({
  id: `${body}-s${stage}-${slug(name)}`, stage, body, category, name, tags, colours, credit,
  price: PRICES[stage], base: null,
  asset: [body, `clothes/${folder}/${obj}`, `clothes/${folder}/${texture}`, options],
});

function build() {
  const own = bases.map(asItem);
  const items = [];
  for (const body of ['female', 'male']) {
    for (let stage = 0; stage < STAGES.length; stage++) {
      const categories = new Set([...FILLED[body][stage],
        ...own.filter(i => i.body === body && i.stage === stage).map(i => i.category)]);
      for (const category of categories) {
        const mine = own.filter(i => i.body === body && i.stage === stage && i.category === category);
        // Variant shapes: this stage's garments first, then neighbouring stages'.
        const shapes = [...mine, ...own
          .filter(i => i.body === body && i.category === category && i.stage !== stage && Math.abs(i.stage - stage) <= 2)
          // Summer pieces (shorts, cut-offs) stay out of the luxury stages.
          .filter(i => stage < 3 || !i.tags.includes('summer'))
          .sort((a, b) => Math.abs(a.stage - stage) - Math.abs(b.stage - stage))];
        const list = [...mine];
        const target = FILLED[body][stage].includes(category) ? PER_CATEGORY : mine.length;
        for (let k = 0; list.length < target && shapes.length; k++) {
          const shape = shapes[k % shapes.length];
          const [colourName, hex, colourTag] = PALETTES[stage][k % PALETTES[stage].length];
          const name = `${colourName} ${shape.name}`;
          list.push({
            id: `${body}-s${stage}-${slug(name)}`, stage, body, category, name,
            tags: [...STAGE_TAGS[stage]], colours: [colourTag], credit: shape.credit, price: PRICES[stage], base: shape.id,
            dye: hex, asset: shape.asset,
          });
        }
        list.forEach((item, index) => {
          item.reward = list.length >= PER_CATEGORY && index >= list.length - 3
            ? (index === list.length - 1 ? 'five' : 'four') : null;
          items.push(item);
        });
      }
    }
  }
  return items;
}

export const stageWardrobe = build();
