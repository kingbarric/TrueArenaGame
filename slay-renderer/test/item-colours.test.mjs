import {test} from 'node:test';
import assert from 'node:assert/strict';
import {Group,Mesh,BoxGeometry,MeshStandardMaterial,Texture,Color} from 'three';
import {applyItemColour} from '../src/item-colours.ts';

test('wardrobe dye preserves texture, changes colour without recompiling, and resets',()=>{
 const map=new Texture(),mat=new MeshStandardMaterial({map}),root=new Group();root.add(new Mesh(new BoxGeometry(),mat));
 const palette={red:'#a53541',blue:'#48879a'};
 applyItemColour(root,'red',palette);
 const shader={uniforms:{},fragmentShader:'#include <map_fragment>\n#include <alphatest_fragment>'};
 mat.onBeforeCompile(shader,{});
 assert.equal(shader.uniforms.slayDyeEnabled.value,1);
 assert.ok(shader.uniforms.slayDyeTint.value.equals(new Color(palette.red)));
 assert.ok(shader.fragmentShader.includes('float fabric'));
 assert.ok(shader.fragmentShader.includes('#include <alphatest_fragment>'),'transparent shoe cutouts remain intact');
 const version=mat.version;
 applyItemColour(root,'blue',palette);
 assert.equal(mat.version,version);
 assert.ok(shader.uniforms.slayDyeTint.value.equals(new Color(palette.blue)));
 assert.equal(mat.map,map);
 applyItemColour(root,undefined,palette);
 assert.equal(shader.uniforms.slayDyeEnabled.value,0);
 assert.equal(mat.map,map);
 assert.throws(()=>applyItemColour(root,'unknown',palette),/Unknown wardrobe colour/);
});
