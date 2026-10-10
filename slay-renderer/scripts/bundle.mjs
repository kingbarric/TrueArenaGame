import {readFileSync,mkdirSync,writeFileSync,cpSync} from 'node:fs';
import {publishAssets} from './publish-assets.mjs';
const out='../app/assets/slay_renderer';mkdirSync(out,{recursive:true});
const script=readFileSync('dist/stage.js','utf8');
const html=readFileSync('index.html','utf8').replace('<script type="module" src="/src/main.ts"></script>',()=>'<script>'+script.replaceAll('</script','<\\/script')+'</script>');
writeFileSync(out+'/index.html',html);
const catalog=JSON.parse(readFileSync('../backend/ta-api/src/main/resources/slay/catalog.json','utf8'));
// Art is delivered from playhuud.com except the bundled starter pack; see publish-assets.mjs.
const assets=await publishAssets(catalog);
writeFileSync('../backend/ta-api/src/main/resources/slay/asset-manifest.json',JSON.stringify(assets,null,1)+'\n');
writeFileSync(out+'/catalog.json',JSON.stringify({...catalog,assets}));
const credits=readFileSync('../docs/SLAYHUUD_ASSET_CREDITS.md','utf8').replace(/^#{1,6} /gm,'');
writeFileSync(out+'/credits.txt',credits);
mkdirSync(out+'/basis',{recursive:true});cpSync('node_modules/three/examples/jsm/libs/basis',out+'/basis',{recursive:true});
