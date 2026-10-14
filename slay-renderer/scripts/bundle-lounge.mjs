import {readFileSync,writeFileSync} from 'node:fs';
const script=readFileSync('dist/lounge/lounge.js','utf8'),html=readFileSync('huud-lounge.html','utf8').replace('<script type="module" src="/src/huud-lounge.ts"></script>',()=>'<script>'+script.replaceAll('</script','<\\/script')+'</script>');
writeFileSync('../app/assets/slay_renderer/huud-lounge.html',html);

writeFileSync('../app/assets/slay_renderer/huud-avatars.json',readFileSync('../backend/ta-api/src/main/resources/slay/huud-avatars.json'));
