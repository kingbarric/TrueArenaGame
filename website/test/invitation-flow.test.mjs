import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import test from 'node:test';
const html = readFileSync(new URL('../../backend/ta-api/src/main/resources/invitations/page.html', import.meta.url), 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
function page({kind='championships', code='ABCD2345', device='android', ios='', android='', clipboardFails=false, base='', url=''}={}) {
  const elements = new Map();
  for (const id of ['invite','install','status','code','open','copy','name','description','art']) elements.set(id, {hidden: id === 'install', textContent:'', href:''});
  elements.get('invite').dataset = {kind, code, ios, android, base, url};
  const copied = [], navigated = [], fetched = [];
  const context = {document: {getElementById: id => elements.get(id)},
    location:{pathname:`/${kind}/${code}`,assign:url=>navigated.push(url)},
    navigator:{userAgent: device==='ios'?'iPhone':device==='android'?'Android':'Desktop',platform:'',maxTouchPoints:0,
      clipboard:{writeText:async value=>{if(clipboardFails)throw Error('denied');copied.push(value);}}},
    URL, URLSearchParams, fetch:async url=>{fetched.push(url);return {ok:true,json:async()=>({ios,android})};}};
  vm.runInNewContext(script, context);
  return {elements,copied,navigated,fetched};
}
test('both invitation types open their exact app destination', () => {
  for(const [kind,code] of [['huud','ABC234'],['championships','ABCD2345']]) {
    const p=page({kind,code});
    assert.equal(p.elements.get('open').href,`playhuud:///${kind}/${code}`);
  }
});
test('unpublished listings show review status and offer no fake install link', () => {
  const p=page();
  assert.equal(p.elements.get('install').hidden,true);
  assert.match(p.elements.get('status').textContent,/in review/);
});
test('Google Play receives the exact invitation as an encoded install referrer', async () => {
  const p=page({android:'https://play.google.com/store/apps/details?id=app.truearena.truearena'});
  await p.elements.get('install').onclick();
  const url=new URL(p.navigated[0]);
  assert.equal(url.hostname,'play.google.com');
  assert.equal(new URLSearchParams(url.searchParams.get('referrer')).get('invitation'),'https://playhuud.com/championships/ABCD2345');
  assert.equal(p.copied[0],'https://playhuud.com/championships/ABCD2345');
});
test('iPhone copies the Huud invitation before opening its actual App Store listing',async()=>{
  const p=page({kind:'huud',code:'ABC234',device:'ios',ios:'https://apps.apple.com/app/id123456789'});
  await p.elements.get('install').onclick();
  assert.equal(p.copied[0],'https://playhuud.com/huud/ABC234');
  assert.equal(p.navigated[0],'https://apps.apple.com/app/id123456789');
});
test('clipboard refusal keeps installation available with the reopen-link instruction',async()=>{
  const p=page({device:'ios',ios:'https://apps.apple.com/app/id123456789',clipboardFails:true});
  await p.elements.get('install').onclick();
  assert.equal(p.navigated.length,1);
  assert.match(p.elements.get('status').textContent,/return to this page/);
});
test('malformed invitation codes cannot start an installation handoff',async()=>{
  const p=page({code:'../../other',android:'https://play.google.com/store/apps/details?id=app.truearena.truearena'});
  await p.elements.get('install').onclick();
  assert.equal(p.navigated.length,0);
});
test('both native platforms advertise Huud and championship paths',()=>{
  const association=JSON.parse(readFileSync(new URL('../.well-known/apple-app-site-association',import.meta.url),'utf8'));
  const paths=association.applinks.details[0].components.map(x=>x['/']);
  assert.deepEqual(paths,['/huud/*','/championships/*']);
  const manifest=readFileSync(new URL('../../app/android/app/src/main/AndroidManifest.xml',import.meta.url),'utf8');
  assert.match(manifest,/pathPrefix="\/huud\/"/);
  assert.match(manifest,/pathPrefix="\/championships\/"/);
});

test('desktop visitors see the device instruction when stores are published',()=>{
  const p=page({device:'desktop',ios:'https://apps.apple.com/app/id123456789'});
  assert.match(p.elements.get('status').textContent,/iPhone or Android/);
  assert.doesNotMatch(p.elements.get('status').textContent,/in review/);
});
test('static fallbacks and dynamic metadata pages keep the same invitation script',()=>{
  for(const kind of ['huud','championships']) {
    const page=readFileSync(new URL(`../${kind}/index.html`,import.meta.url),'utf8');
    assert.equal(page.match(/<script>([\s\S]*?)<\/script>/)[1],script);
  }
});

test('test deployment preserves its invitation and API prefix',async()=>{
  const base='https://test.example/test';
  const p=page({base,url:base+'/championships/ABCD2345',android:'https://play.google.com/store/apps/details?id=app.truearena.truearena'});
  await p.elements.get('install').onclick();
  assert.equal(p.copied[0],base+'/championships/ABCD2345');
  assert.equal(p.fetched[0],base+'/api/v1/invitations/stores');
  assert.equal(new URLSearchParams(new URL(p.navigated[0]).searchParams.get('referrer')).get('invitation'),p.copied[0]);
});
