import { defineConfig } from 'vite';
export default defineConfig({ build: { lib: {entry:'src/main.ts',name:'SlayStage',formats:['iife'],fileName:()=> 'stage.js'},outDir:'dist',emptyOutDir:true,assetsInlineLimit:0 } });
