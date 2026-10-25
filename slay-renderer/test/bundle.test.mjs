import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
test('Flutter HTML embeds the entire renderer without replacement-string interpolation', () => {
 const script=readFileSync(new URL('../dist/stage.js',import.meta.url),'utf8').replaceAll('</script','<\\/script');
 const html=readFileSync(new URL('../../app/assets/slay_renderer/index.html',import.meta.url),'utf8');
 assert.ok(html.includes('<script>'+script+'</script>'));
 assert.equal(html.split('<script>').length,2);
});
