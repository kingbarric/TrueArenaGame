import {defineConfig} from 'vite';
export default defineConfig({publicDir:false,build:{lib:{entry:'src/huud-lounge.ts',name:'HuudLounge',formats:['iife'],fileName:()=> 'lounge.js'},outDir:'dist/lounge',emptyOutDir:true,assetsInlineLimit:0}});
