import {test} from 'node:test';
import assert from 'node:assert/strict';
import {existsSync, readFileSync} from 'node:fs';
import {stageWardrobe, PER_CATEGORY} from '../scripts/stage-wardrobe.mjs';

const read = path => JSON.parse(readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8'));
const catalog = read('backend/ta-api/src/main/resources/slay/catalog.json');
const career = read('backend/ta-api/src/main/resources/slay/career.json');
const asset = path => new URL(`../../app/assets/slay_renderer/${path}`, import.meta.url);

test('every stage has its own wardrobe: no piece is opened or rewarded by two stages', () => {
  const owner = new Map();
  for (const chapter of career.chapters) for (const body of ['female', 'male']) {
    const ids = [...chapter.collection[body], ...chapter.rewards[body].four, ...chapter.rewards[body].five];
    for (const id of ids) {
      assert.ok(!owner.has(id) || owner.get(id) === chapter.chapter, `${id} is in stages ${owner.get(id)} and ${chapter.chapter}`);
      owner.set(id, chapter.chapter);
    }
  }
  for (const item of stageWardrobe) assert.equal(owner.get(item.id), item.stage, `${item.id} belongs to stage ${item.stage}`);
  assert.equal(new Set(stageWardrobe.map(item => item.id)).size, stageWardrobe.length);
});

test('each stage offers ten pieces per main category for both bodies', () => {
  const filled = {female: ['dress', 'tops', 'trousers', 'skirts', 'shoes'], male: ['shirts', 'trousers', 'shoes']};
  for (let stage = 0; stage < 5; stage++) for (const [body, categories] of Object.entries(filled)) {
    for (const category of [...categories, ...(body === 'male' && stage >= 3 ? ['outfit'] : [])]) {
      const count = stageWardrobe.filter(i => i.stage === stage && i.body === body && i.category === category).length;
      assert.equal(count, PER_CATEGORY, `stage ${stage} ${body} ${category}`);
    }
  }
});

test('downloaded pieces ship a model, thumbnail and credit; variants dye a real base', () => {
  const items = new Map(catalog.items.map(item => [item.id, item]));
  for (const item of stageWardrobe) {
    const entry = items.get(item.id);
    assert.ok(entry, `${item.id} missing from the catalogue`);
    assert.ok(existsSync(asset(entry.assetUrl)), `${entry.assetUrl} missing`);
    assert.ok(existsSync(asset(entry.thumbnailUrl)), `${entry.thumbnailUrl} missing`);
    assert.match(item.credit, /^.+ · (CC0|CC BY( [34]\.0)?)$/, item.id);
    if (item.base) {
      const presentation = catalog.wardrobePresentation[item.id];
      assert.equal(presentation.maskOf, item.base);
      assert.match(presentation.dye, /^#[0-9a-f]{6}$/);
      assert.ok(items.get(item.base) && !stageWardrobe.find(i => i.id === item.base).base, `${item.id} dyes ${item.base}`);
    }
  }
});
