// Writes the career stage wardrobe (stage-wardrobe.mjs) into the catalogue and
// the career chapters: each stage's pieces open with that stage, its last three
// per category become 4★/5★ rewards. Idempotent; part of `npm run build`.
import {readFileSync, writeFileSync} from 'node:fs';
import {stageWardrobe} from './stage-wardrobe.mjs';

const catalogPath = new URL('../../backend/ta-api/src/main/resources/slay/catalog.json', import.meta.url);
const careerPath = new URL('../../backend/ta-api/src/main/resources/slay/career.json', import.meta.url);
const isStageItem = id => /^(female|male)-s[0-4]-/.test(id);

const catalog = JSON.parse(readFileSync(catalogPath, 'utf8'));
const before = JSON.stringify(catalog.items);
catalog.items = catalog.items.filter(item => !isStageItem(item.id)).concat(stageWardrobe.map(item => ({
  id: item.id,
  name: item.name,
  category: item.category,
  body: item.body,
  styleTags: item.tags,
  colourTags: item.colours,
  cultureTags: [],
  eventTags: item.tags,
  rarity: item.reward === 'five' ? 'epic' : item.reward === 'four' ? 'rare' : 'common',
  assetUrl: `assets/${item.base ?? item.id}.glb`,
  thumbnailUrl: `assets/${item.base ?? item.id}.png`,
  hidesRegions: [],
  attachmentBone: null,
  isDefault: false,
  coinCost: item.price,
  unlockWins: 0,
  placeholder: item.category,
})));
if (JSON.stringify(catalog.items) !== before) catalog.version += 1;
writeFileSync(catalogPath, JSON.stringify(catalog, null, 2) + '\n');

const career = JSON.parse(readFileSync(careerPath, 'utf8'));
for (const chapter of career.chapters) {
  for (const body of ['female', 'male']) {
    const mine = stageWardrobe.filter(item => item.stage === chapter.chapter && item.body === body);
    chapter.collection[body] = chapter.collection[body].filter(id => !isStageItem(id))
      .concat(mine.filter(item => !item.reward).map(item => item.id));
    for (const pool of ['four', 'five']) {
      chapter.rewards[body][pool] = chapter.rewards[body][pool].filter(id => !isStageItem(id))
        .concat(mine.filter(item => item.reward === pool).map(item => item.id));
    }
  }
}
writeFileSync(careerPath, JSON.stringify(career, null, 1) + '\n');
console.log(`Stage wardrobe: ${stageWardrobe.length} pieces across ${career.chapters.length} stages (catalogue v${catalog.version}).`);
