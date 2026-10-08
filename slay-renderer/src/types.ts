export type Look = {body:'male'|'female';skinTone:string;facePreset:string;items:Record<string,string>;pose:string;background:string};
export type Item = {id:string;category:string;assetUrl:string|null;hidesRegions:string[];attachmentBone:string|null;placeholder:string;colourTags:string[]};
export type Catalog = {avatars:{body:string;assetUrl:string|null;rigVersion:string}[];items:Item[];developmentAssets:boolean};
export type Message = {v:1;id:string;type:string;payload:Record<string,unknown>};
declare global {interface Window {slayReceive:(message:Message)=>Promise<void>;flutter_inappwebview?:{callHandler:(name:string,message:unknown)=>Promise<unknown>};SlayBridge?:{postMessage:(message:string)=>void}}}
