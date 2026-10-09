/*
 * Converts the selected CC0 MakeHuman OBJ sources into self-contained GLBs.
 *
 * The MakeHuman sources do not include a game-runtime skeleton. This converter
 * provides one shared lightweight fashion rig, conservative auto weights and
 * five short pose clips. It is deliberately a starter-art pipeline: validate
 * and visually review each result before enabling it in a production catalog.
 */
import {mkdirSync, readFileSync, writeFileSync, readdirSync, copyFileSync} from 'node:fs';
import {dirname, resolve} from 'node:path';
import {execFileSync} from 'node:child_process';

const root = resolve(new URL('..', import.meta.url).pathname);
const source = process.argv[2] ? resolve(process.argv[2]) : resolve(root, 'source_assets/makehuman/starter');
const output = process.argv[3] ? resolve(process.argv[3]) : resolve(root, '../app/assets/slay_renderer/assets');
const scale = 1.8 / 16.044; // Female height is 1.8 m; the matching male body is taller.
const bodySources = {
  female: {obj: 'proxymeshes/female1605/female1605.obj', texture: 'skins/young_african_female/young_darkskinned_female_diffuse.png'},
  male: {obj: 'proxymeshes/male_generic/male_generic.obj', texture: 'skins/young_african_male/young_darkskinned_male_diffuse.png'},
};
const assets = {
  'female-essential': ['female', 'clothes/aethelraed_flapper_dress/flapper_dress_1.obj', 'clothes/aethelraed_flapper_dress/flapper_dress_green.png'],
  'female-executive': ['female', 'clothes/female_elegantsuit01/female_elegantsuit01.obj', 'clothes/female_elegantsuit01/female_elegantsuit01_diffuse.png'],
  'female-redcarpet': ['female', 'clothes/toigo_halter_dress_with_fluted_skirt/dress_long_fluted_skirt.obj', 'clothes/toigo_halter_dress_with_fluted_skirt/DressCloth2UV.png'],
  'female-romantic': ['female', 'clothes/toigo_halter_dress_knee_length/dress_knee_halter.obj', 'clothes/toigo_halter_dress_knee_length/DressCloth3UV.png'],
  'female-night': ['female', 'clothes/toigo_halter_dress_midi/dress_midi_halter.obj', 'clothes/toigo_halter_dress_midi/DressClothUV.png'],
  'female-dinner': ['female', 'clothes/mindfront_kimono/f_kimono.obj', 'clothes/mindfront_kimono/F_Kimono_COL.png'],
  'female-business': ['female', 'clothes/toigo_female_double-breasted_suit/fem_suit_double_breasted.obj', 'clothes/toigo_female_double-breasted_suit/DB-suit-Fem.png'],
  'male-essential': ['male', 'clothes/male_casualsuit01/male_casualsuit01.obj', 'clothes/male_casualsuit01/male_casualsuit01_diffuse.png'],
  'male-executive': ['male', 'clothes/male_elegantsuit01/male_elegantsuit01.obj', 'clothes/male_elegantsuit01/male_elegantsuit01_diffuse.png'],
  'male-redcarpet': ['male', 'clothes/toigo_male_double-breasted_suit/suit_double_breasted.obj', 'clothes/toigo_male_double-breasted_suit/DB-suit.png'],
  'male-business': ['male', 'clothes/toigo_male_suit_tie_and_jacket/jacket_tie_pants.obj', 'clothes/toigo_male_suit_tie_and_jacket/Suit-tie-Jacket-diff.png'],
  'female-hair-0': ['female', 'hair/afro01/afro01.obj', 'hair/afro01/afro_diffuse.png'],
  'female-hair-1': ['female', 'hair/braid01/braid01.obj', 'hair/braid01/braid01_diffuse.png'],
  'female-hair-2': ['female', 'hair/short01/short01.obj', 'hair/short01/short01_diffuse.png'],
  'male-hair-0': ['male', 'hair/afro01/afro01.obj', 'hair/afro01/afro_diffuse.png'],
  'male-hair-1': ['male', 'hair/short01/short01.obj', 'hair/short01/short01_diffuse.png'],
  'male-hair-2': ['male', 'hair/braid01/braid01.obj', 'hair/braid01/braid01_diffuse.png'],
  'shoe-0': ['unisex', 'clothes/shoes01/shoes01.obj', 'clothes/shoes01/shoes01_diffuse.png'],
  'shoe-1': ['unisex', 'clothes/shoes02/shoes02.obj', 'clothes/shoes02/shoes02_diffuse.png'],
};

function parseObj(path, offset = [0, 0, 0]) {
  const positions = [], uvs = [], normals = [], faces = [];
  for (const line of readFileSync(path, 'utf8').split(/\r?\n/)) {
    const parts = line.trim().split(/\s+/);
    if (parts[0] === 'v') positions.push(parts.slice(1, 4).map(Number));
    if (parts[0] === 'vt') uvs.push([Number(parts[1]), 1 - Number(parts[2])]);
    if (parts[0] === 'vn') normals.push(parts.slice(1, 4).map(Number));
    if (parts[0] === 'f') {
      const indexes = parts.slice(1).map(value => value.split('/').map(index => Number(index) || 0));
      for (let i = 1; i < indexes.length - 1; i++) faces.push([indexes[0], indexes[i], indexes[i + 1]]);
    }
  }
  const position = [], normal = [], uv = [];
  // Every garment shares the source body's origin. Grounding each garment
  // individually moves hair to the feet and makes clothing miss its body.
  const transform = value => [value[0] * scale + offset[0], (value[1] + 8.184) * scale + offset[1], value[2] * scale + offset[2]];
  const faceNormal = triangle => {
    const a = transform(positions[triangle[0][0] - 1]), b = transform(positions[triangle[1][0] - 1]), c = transform(positions[triangle[2][0] - 1]);
    const u = b.map((value, index) => value - a[index]), v = c.map((value, index) => value - a[index]);
    const cross = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];
    const length = Math.hypot(...cross) || 1; return cross.map(value => value / length);
  };
  const smooth = new Map();
  for (const triangle of faces) {
    const direction = faceNormal(triangle);
    for (const [vertex] of triangle) {
      const accumulated = smooth.get(vertex) ?? [0, 0, 0];
      smooth.set(vertex, accumulated.map((value, axis) => value + direction[axis]));
    }
  }
  for (const triangle of faces) {
    const fallback = faceNormal(triangle);
    for (const [vertexIndex, uvIndex, normalIndex] of triangle) {
      position.push(...transform(positions[vertexIndex - 1]));
      const direction = smooth.get(vertexIndex) ?? fallback;
      const length = Math.hypot(...direction) || 1;
      normal.push(...(normalIndex ? normals[normalIndex - 1] : direction.map(value => value / length)));
      uv.push(...(uvIndex ? uvs[uvIndex - 1] : [0, 0]));
    }
  }
  return {position: new Float32Array(position), normal: new Float32Array(normal), uv: new Float32Array(uv)};
}

const bones = [
  ['Root', -1, [0, 0, 0]], ['Hips', 0, [0, .72, 0]], ['Spine', 1, [0, .22, 0]], ['Chest', 2, [0, .24, 0]], ['Neck', 3, [0, .22, 0]], ['Head', 4, [0, .18, 0]],
  ['LeftUpperArm', 3, [.30, .14, 0]], ['LeftLowerArm', 6, [.33, 0, 0]], ['LeftHand', 7, [.25, 0, 0]],
  ['RightUpperArm', 3, [-.30, .14, 0]], ['RightLowerArm', 9, [-.33, 0, 0]], ['RightHand', 10, [-.25, 0, 0]],
  ['LeftUpperLeg', 1, [.13, -.11, 0]], ['LeftLowerLeg', 12, [0, -.40, 0]], ['LeftFoot', 13, [0, -.32, .10]],
  ['RightUpperLeg', 1, [-.13, -.11, 0]], ['RightLowerLeg', 15, [0, -.40, 0]], ['RightFoot', 16, [0, -.32, .10]],
];
function worldPositions() {
  return bones.map(([, parent, local], index) => parent < 0 ? local : local.map((value, axis) => value + worldPositions.cache[parent][axis]));
}
worldPositions.cache = [];
for (const bone of bones) worldPositions.cache.push(bone[1] < 0 ? bone[2] : bone[2].map((value, axis) => value + worldPositions.cache[bone[1]][axis]));
function weights(position, hair) {
  let primary = 2;
  if (hair || position[1] > 1.43) primary = 5;
  else if (position[1] < .70) {
    const left = position[0] >= 0;
    primary = left ? (position[1] < .18 ? 14 : position[1] < .48 ? 13 : 12) : (position[1] < .18 ? 17 : position[1] < .48 ? 16 : 15);
  } else if (Math.abs(position[0]) > .28) {
    const left = position[0] >= 0; primary = left ? (Math.abs(position[0]) > .78 ? 8 : Math.abs(position[0]) > .52 ? 7 : 6) : (Math.abs(position[0]) > .78 ? 11 : Math.abs(position[0]) > .52 ? 10 : 9);
  } else if (position[1] > 1.15) primary = 4; else if (position[1] > .95) primary = 3;
  return [primary, 0, 0, 0];
}
function mat4Translation([x, y, z]) { return [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -x, -y, -z, 1]; }
function align(length) { return Math.ceil(length / 4) * 4; }
function indexed(mesh) {
  const vertices = new Map(), position = [], normal = [], uv = [], indices = [];
  for (let vertex = 0; vertex < mesh.position.length / 3; vertex++) {
    const p = mesh.position.slice(vertex * 3, vertex * 3 + 3);
    const n = mesh.normal.slice(vertex * 3, vertex * 3 + 3);
    const t = mesh.uv.slice(vertex * 2, vertex * 2 + 2);
    const key = [...p, ...n, ...t].join(',');
    let index = vertices.get(key);
    if (index === undefined) {
      index = vertices.size; vertices.set(key, index);
      position.push(...p); normal.push(...n); uv.push(...t);
    }
    indices.push(index);
  }
  return {position: new Float32Array(position), normal: new Float32Array(normal), uv: new Float32Array(uv), indices: new Uint32Array(indices)};
}
function selectTriangles(mesh, accepts) {
  const position = [], normal = [], uv = [];
  for (let offset = 0; offset < mesh.position.length; offset += 9) {
    const centre = [0, 1, 2].map(axis => (mesh.position[offset + axis] + mesh.position[offset + 3 + axis] + mesh.position[offset + 6 + axis]) / 3);
    if (!accepts(centre)) continue;
    position.push(...mesh.position.slice(offset, offset + 9));
    normal.push(...mesh.normal.slice(offset, offset + 9));
    const uvOffset = offset / 3 * 2; uv.push(...mesh.uv.slice(uvOffset, uvOffset + 6));
  }
  return {position: new Float32Array(position), normal: new Float32Array(normal), uv: new Float32Array(uv)};
}
function encodeGlb(document, chunks) {
  const json = Buffer.from(JSON.stringify(document));
  const paddedJson = Buffer.concat([json, Buffer.alloc(align(json.length) - json.length, 0x20)]);
  const binary = Buffer.concat(chunks.map(chunk => Buffer.concat([chunk, Buffer.alloc(align(chunk.length) - chunk.length)])));
  const header = Buffer.alloc(20); header.writeUInt32LE(0x46546c67, 0); header.writeUInt32LE(2, 4); header.writeUInt32LE(28 + paddedJson.length + binary.length, 8); header.writeUInt32LE(paddedJson.length, 12); header.writeUInt32LE(0x4e4f534a, 16);
  const binHeader = Buffer.alloc(8); binHeader.writeUInt32LE(binary.length, 0); binHeader.writeUInt32LE(0x004e4942, 4);
  return Buffer.concat([header, paddedJson, binHeader, binary]);
}
function convert({id, body, obj, texture, isAvatar}) {
  const isHair = id.includes('hair');
  const headOffset = body === 'male' ? 1.4382 * scale : 0;
  const mesh = parseObj(resolve(source, obj), [0, isHair ? headOffset : 0, 0]);
  const viewChunks = [], views = [], accessors = [];
  const add = (data, componentType, type, count, target) => {
    const buffer = Buffer.from(data.buffer, data.byteOffset, data.byteLength), offset = viewChunks.reduce((sum, value) => sum + align(value.length), 0);
    views.push({buffer: 0, byteOffset: offset, byteLength: buffer.length, ...(target ? {target} : {})}); viewChunks.push(buffer);
    accessors.push({bufferView: views.length - 1, componentType, count, type}); return accessors.length - 1;
  };
  const regions = isAvatar ? [
    ['region_head', selectTriangles(mesh, position => position[1] > 1.43)],
    ['region_arms', selectTriangles(mesh, position => position[1] <= 1.43 && position[1] > .68 && Math.abs(position[0]) > .28)],
    ['region_upper_legs', selectTriangles(mesh, position => position[1] <= .68 && position[1] > .38)],
    ['region_legs', selectTriangles(mesh, position => position[1] <= .38)],
    ['region_torso', selectTriangles(mesh, position => position[1] > .68 && position[1] <= 1.43 && Math.abs(position[0]) <= .28)],
  ].filter(([, region]) => region.position.length) : [[id, mesh]];
  if (isAvatar) {
    // The eyes source uses a floor origin; the body/brows use a centred
    // MakeHuman origin. Male garments fit the taller male_generic body.
    const eyeOffset = body === 'male' ? -7.65 : -8.98;
    const browOffset = body === 'male' ? .71 : -.62;
    regions.push(['face_eyes', parseObj(resolve(source, 'eyes/high-poly/high-poly.obj'), [0, eyeOffset * scale, -.20 * scale])]);
    regions.push(['face_brows', parseObj(resolve(source, 'eyebrows/eyebrow001/eyebrow001.obj'), [0, browOffset * scale, 0])]);
  }
  const meshes = [], nodes = [];
  for (const [name, rawRegion] of regions) {
    const region = indexed(rawRegion);
    const positions = add(region.position, 5126, 'VEC3', region.position.length / 3, 34962);
    accessors[positions].min = [0, 1, 2].map(axis => Math.min(...Array.from(region.position).filter((_, index) => index % 3 === axis)));
    accessors[positions].max = [0, 1, 2].map(axis => Math.max(...Array.from(region.position).filter((_, index) => index % 3 === axis)));
    const normals = add(region.normal, 5126, 'VEC3', region.normal.length / 3, 34962);
    const uvs = add(region.uv, 5126, 'VEC2', region.uv.length / 2, 34962);
    const joints = new Uint16Array(region.position.length / 3 * 4), jointWeights = new Float32Array(region.position.length / 3 * 4);
    for (let vertex = 0; vertex < region.position.length / 3; vertex++) { joints.set(weights(region.position.slice(vertex * 3, vertex * 3 + 3), isHair), vertex * 4); jointWeights[vertex * 4] = 1; }
    const jointAccessor = add(joints, 5123, 'VEC4', joints.length / 4, 34962), weightAccessor = add(jointWeights, 5126, 'VEC4', jointWeights.length / 4, 34962);
    const indexAccessor = add(region.indices, 5125, 'SCALAR', region.indices.length, 34963);
    const primitive = {attributes: {POSITION: positions, NORMAL: normals, TEXCOORD_0: uvs, JOINTS_0: jointAccessor, WEIGHTS_0: weightAccessor}, indices: indexAccessor, material: name === 'face_eyes' ? 1 : name === 'face_brows' ? 2 : 0};
    if (isAvatar && name === 'region_head') {
      primitive.targets = ['face_classic', 'face_soft', 'face_angular', 'expression_smile'].map(name => {
        const delta = new Float32Array(region.position.length);
        for (let vertex = 0; vertex < region.position.length; vertex += 3) {
          const [x, y, z] = region.position.slice(vertex, vertex + 3);
          if (name === 'face_soft') delta[vertex] = x * .04;
          if (name === 'face_angular' && y < 1.66) delta[vertex] = x * -.06;
          if (name === 'expression_smile' && z > .08 && y > 1.58 && y < 1.67) delta[vertex + 1] = Math.min(.008, Math.abs(x) * .12);
        }
        const accessor = add(delta, 5126, 'VEC3', region.position.length / 3, 34962);
        accessors[accessor].min = [0, 1, 2].map(axis => Math.min(...Array.from(delta).filter((_, index) => index % 3 === axis)));
        accessors[accessor].max = [0, 1, 2].map(axis => Math.max(...Array.from(delta).filter((_, index) => index % 3 === axis)));
        return {POSITION: accessor};
      });
    }
    meshes.push({name, primitives: [primitive], ...(isAvatar && name === 'region_head' ? {extras: {targetNames: ['face_classic', 'face_soft', 'face_angular', 'expression_smile']}} : {})});
    nodes.push({name, mesh: meshes.length - 1, skin: 0});
  }
  const inverse = new Float32Array(worldPositions.cache.flatMap(mat4Translation)); const inverseAccessor = add(inverse, 5126, 'MAT4', bones.length);
  const textures = isAvatar ? [texture, 'eyes/materials/brown_eye.png', 'eyebrows/eyebrow001/eyebrow001.png'] : [texture];
  const images = textures.map(texture => {
    // Cache mobile-sized textures without altering the downloaded sources.
    const texturePath = resolve(source, texture);
    const optimisedPath = resolve(source, '.mobile-textures', texture);
    mkdirSync(dirname(optimisedPath), {recursive: true});
    if (process.platform === 'darwin') {
      execFileSync('sips', ['--resampleHeightWidthMax', '1024', texturePath, '--out', optimisedPath], {stdio: 'ignore'});
    } else copyFileSync(texturePath, optimisedPath);
    const image = readFileSync(optimisedPath);
    const byteOffset = viewChunks.reduce((sum, value) => sum + align(value.length), 0);
    views.push({buffer: 0, byteOffset, byteLength: image.length}); viewChunks.push(image);
    return {bufferView: views.length - 1, mimeType: 'image/png'};
  });
  const firstBone = nodes.length;
  bones.forEach(([name, parent, translation], index) => nodes.push({name, translation, ...(parent >= 0 ? {} : {children: []})}));
  bones.forEach(([, parent], index) => { if (parent >= 0) (nodes[firstBone + parent].children ??= []).push(firstBone + index); });
  const rotations = {idle: [0, 0, 0, 1], signature: [0, .08, 0, Math.sqrt(1 - .08 ** 2)], confident: [0, -.06, 0, Math.sqrt(1 - .06 ** 2)], editorial: [0, .14, 0, Math.sqrt(1 - .14 ** 2)], celebrate: [0, -.1, 0, Math.sqrt(1 - .1 ** 2)]};
  const animations = Object.entries(rotations).map(([name, rotation]) => {
    const input = add(new Float32Array([0, 1]), 5126, 'SCALAR', 2);
    accessors[input].min = [0]; accessors[input].max = [1];
    const output = add(new Float32Array([...rotation, ...rotation]), 5126, 'VEC4', 2);
    const bone = 0;
    return {name, samplers: [{input, output, interpolation: 'LINEAR'}], channels: [{sampler: 0, target: {node: firstBone + bone, path: 'rotation'}}]};
  });
  const materials = images.map((_, index) => ({name: id + '-material-' + index, doubleSided: !isAvatar || index > 0, ...((isHair || index === 2) ? {alphaMode: 'MASK', alphaCutoff: .35} : {}), pbrMetallicRoughness: {baseColorTexture: {index}, metallicFactor: 0, roughnessFactor: index === 1 ? .35 : .85}}));
  const document = {asset: {version: '2.0', generator: 'SlayHuud MakeHuman starter converter'}, scene: 0, scenes: [{nodes: [...meshes.keys(), firstBone]}], nodes, meshes, skins: [{name: 'slay-shared-rig-v1', inverseBindMatrices: inverseAccessor, joints: bones.map((_, index) => firstBone + index), skeleton: firstBone}], materials, textures: images.map((_, source) => ({source})), images, buffers: [{byteLength: viewChunks.reduce((sum, value) => sum + align(value.length), 0)}], bufferViews: views, accessors, animations};
  writeFileSync(resolve(output, id + '.glb'), encodeGlb(document, viewChunks));
  const sourceFolder = resolve(source, dirname(obj));
  const thumbnail = readdirSync(sourceFolder).find(file => file.endsWith('.thumb'));
  if (thumbnail) copyFileSync(resolve(sourceFolder, thumbnail), resolve(output, id + '.png'));
  return {id, triangles: mesh.position.length / 9, bytes: readFileSync(resolve(output, id + '.glb')).length};
}

mkdirSync(output, {recursive: true});
const report = [];
for (const [body, entry] of Object.entries(bodySources)) report.push(convert({id: body, body, ...entry, isAvatar: true}));
for (const [id, [body, obj, texture]] of Object.entries(assets)) report.push(convert({id, body, obj, texture, isAvatar: false}));
writeFileSync(resolve(output, 'makehuman-starter-report.json'), JSON.stringify({source: 'MakeHuman Community CC0 asset packs', generatedAt: new Date().toISOString(), assets: report}, null, 2) + '\n');
console.log(JSON.stringify(report, null, 2));
