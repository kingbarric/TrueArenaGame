export type Look = {body:'male'|'female';avatarId?:string;skinTone:string;facePreset:string;items:Record<string,string>;itemColours?:Record<string,string>;pose:string;background:string};
export type Item = {id:string;category:string;assetUrl:string|null;hidesRegions:string[];attachmentBone:string|null;placeholder:string;colourTags:string[]};
export type Catalog = {version:number;avatars:{id?:string;name?:string;body:string;assetUrl:string|null;rigVersion:string;fitUrl?:string;thumbnailUrl?:string}[];items:Item[];itemColourPalette?:Record<string,string>;developmentAssets:boolean};
export type Message = {v:1;id:string;type:string;payload:Record<string,unknown>};
declare global {interface Window {slayReceive:(message:Message)=>Promise<void>;flutter_inappwebview?:{callHandler:(name:string,message:unknown)=>Promise<unknown>};SlayBridge?:{postMessage:(message:string)=>void}}}
