import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {expansion} from './wardrobe-expansion.mjs';
import {classicClothing} from './classic-clothing.mjs';
import {stageWardrobe} from './stage-wardrobe.mjs';

// Career colour variants reuse a base garment's model, dyed at runtime.
const variants=new Map(stageWardrobe.filter(item=>item.base).map(item=>[item.id,item]));

const clothing=new Set(['outfit','dress','tops','shirts','trousers','skirts']);
const groups={Casual:['casual','streetwear','summer'],Corporate:['corporate','business'],
  'Date Night':['romantic'],Party:['party','night'],Formal:['formal','elegant','luxury'],
  Traditional:['traditional','african','bridal','royal']};
export function primaryStyle(item) {
  const tags=item.styleTags??[];
  for(const group of ['Traditional','Corporate']) if(tags.some(tag=>groups[group].includes(tag)))return group;
  for(const tag of tags) for(const [group,matches] of Object.entries(groups)) if(matches.includes(tag))return group;
  return 'Casual';
}
export function wardrobePresentation(catalog,sources={...classicClothing,...expansion}) {
  const result={},families=new Map();
  for(const item of catalog.items) {
    const variant=variants.get(item.id);
    // Dyed shoes and accessories still need their dye and shared mask.
    if(variant&&!clothing.has(item.category)){result[item.id]={category:item.category,styleGroup:primaryStyle(item),maskOf:variant.base,dye:variant.dye};continue;}
    if(!clothing.has(item.category)||!item.assetUrl)continue;
    const source=variant?[...variant.asset,variant.dye]:sources[item.id];
    // Different cuts, textures or material colours remain distinct garments.
    // Category/name/tags do not turn the same exported garment into a new one.
    const key=source?JSON.stringify([source[0],source[1],source[2],
      Object.entries(source[3]??{}).sort(([a],[b])=>a.localeCompare(b)),source[4]??null])
      : JSON.stringify([item.body,item.assetUrl]);
    const category=item.category==='outfit' && item.body==='female' && /dress|flapper/.test(source?.[1]??'')?'dress':item.category;
    result[item.id]={category,styleGroup:primaryStyle(item),
      ...(variant?{maskOf:variant.base,dye:variant.dye}:{})};
    const family=families.get(key)??[];family.push(item);families.set(key,family);
  }
  for(const family of families.values()) {
    family.sort((a,b)=>Number(b.isDefault)-Number(a.isDefault)||(a.coinCost??0)-(b.coinCost??0));
    const canonical=family[0];
    for(const item of family.slice(1))result[item.id]={...result[canonical.id],duplicateOf:canonical.id};
  }
  return result;
}
if(process.argv[1] && resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const path=new URL('../../backend/ta-api/src/main/resources/slay/catalog.json',import.meta.url);
  const catalog=JSON.parse(readFileSync(path));catalog.wardrobePresentation=wardrobePresentation(catalog);
  writeFileSync(path,JSON.stringify(catalog,null,2)+'\n');
  console.log(`Wardrobe: ${Object.values(catalog.wardrobePresentation).filter(item=>item.duplicateOf).length} identical clothing aliases merged.`);
}
