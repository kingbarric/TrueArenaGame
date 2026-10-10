import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {wardrobePresentation} from '../scripts/group-wardrobe.mjs';
const catalog=JSON.parse(readFileSync(new URL('../../backend/ta-api/src/main/resources/slay/catalog.json',import.meta.url)));
test('bundled grouping matches source identities and keeps valid aliases for saved looks',()=>{
 const expected=wardrobePresentation(catalog);
 assert.deepEqual(catalog.wardrobePresentation,expected);
 const items=new Map(catalog.items.map(item=>[item.id,item]));
 let aliases=0;
 for(const [id,entry] of Object.entries(expected)) {
  assert.ok(items.has(id));assert.ok(entry.category && entry.styleGroup && entry.styleGroup!=='All');
  if(!entry.duplicateOf)continue;
  aliases++;const canonical=items.get(entry.duplicateOf);
  assert.ok(canonical && !expected[canonical.id].duplicateOf);
  assert.equal(entry.category,expected[canonical.id].category);
  assert.equal(entry.styleGroup,expected[canonical.id].styleGroup);
  assert.ok(canonical.isDefault || canonical.coinCost<=items.get(id).coinCost,'prefer the accessible equivalent');
 }
 assert.equal(aliases,7);
 assert.equal(expected['female-essential'].category,'dress');
 assert.equal(expected['female-dress-collection-9'].duplicateOf,'female-essential');
 assert.ok(!expected['female-tops-collection-1'].duplicateOf,'cropped tee is a different cut');
});
