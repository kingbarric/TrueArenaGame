import {defineConfig} from 'vite';
export default defineConfig({build:{lib:{entry:'src/huud-lounge.ts',name:'HuudLounge',formats:['iife'],fileName:()=> 'lounge.js'},outDir:'dist/lounge',emptyOutDir:true,assetsInlineLimit:0}});
