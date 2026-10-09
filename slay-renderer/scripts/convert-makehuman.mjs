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
import {rigFor, skinWeights, poses, poseQuaternion} from './starter-rig.mjs';
import {deletedVertices, proxyCoverage, coveredTriangles} from './makehuman-coverage.mjs';

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

function parseObj(path, offset = [0, 0, 0], sockIsland) {
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
  if (sockIsland) {
    // The supplied models include separate socks. Remove the sock UV island,
    // preserving the shoe collar and its complete toe/heel/side geometry.
    for (let i = faces.length - 1; i >= 0; i--) {
      if (faces[i].every(([, uv]) => sockIsland(uvs[uv - 1]))) faces.splice(i, 1);
    }
  }
  const position = [], normal = [], uv = [], sourceVertices = [];
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
      sourceVertices.push(vertexIndex - 1);
      position.push(...transform(positions[vertexIndex - 1]));
      const direction = smooth.get(vertexIndex) ?? fallback;
      const length = Math.hypot(...direction) || 1;
      normal.push(...(normalIndex ? normals[normalIndex - 1] : direction.map(value => value / length)));
      uv.push(...(uvIndex ? uvs[uvIndex - 1] : [0, 0]));
    }
  }
  return {position: new Float32Array(position), normal: new Float32Array(normal), uv: new Float32Array(uv), sourceVertices};
}

function fittedShoe(mesh, body) {
  const avatar = parseObj(resolve(source, bodySources[body].obj));
  const bounds = positions => [0, 1, 2].map(axis => [Math.min(...positions.map(p => p[axis])), Math.max(...positions.map(p => p[axis]))]);
  const foot = [];
  for (let i = 0; i < avatar.position.length; i += 3) {
    const p = Array.from(avatar.position.slice(i, i + 3));
    if (p[0] > 0 && p[1] < .115) foot.push(p);
  }
  const right = [];
  for (let i = 0; i < mesh.position.length; i += 3) if (mesh.position[i] > 0) right.push(Array.from(mesh.position.slice(i, i + 3)));
  const from = bounds(right), target = bounds(foot);
  target[0] = [target[0][0] - .012, target[0][1] + .012];
  target[1] = [.001, Math.max(.115, target[1][1] + .012)];
  target[2] = [target[2][0] - .012, target[2][1] + .015];
  const factors = target.map((range, axis) => (range[1] - range[0]) / (from[axis][1] - from[axis][0]));
  const position = new Float32Array(mesh.position.length), normal = new Float32Array(mesh.normal.length);
  for (let i = 0; i < position.length; i += 3) {
    const sign = mesh.position[i] >= 0 ? 1 : -1;
    for (let axis = 0; axis < 3; axis++) {
      const value = axis === 0 ? Math.abs(mesh.position[i]) : mesh.position[i + axis];
      position[i + axis] = (target[axis][0] + (value - from[axis][0]) * factors[axis]) * (axis === 0 ? sign : 1);
      normal[i + axis] = mesh.normal[i + axis] / factors[axis];
    }
    const length = Math.hypot(...normal.slice(i, i + 3));
    for (let axis = 0; axis < 3; axis++) normal[i + axis] /= length || 1;
  }
  return {...mesh, position, normal};
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
  const position = [], normal = [], uv = [], sourceVertices = [];
  for (let offset = 0; offset < mesh.position.length; offset += 9) {
    const centre = [0, 1, 2].map(axis => (mesh.position[offset + axis] + mesh.position[offset + 3 + axis] + mesh.position[offset + 6 + axis]) / 3);
    if (!accepts(centre)) continue;
    position.push(...mesh.position.slice(offset, offset + 9));
    normal.push(...mesh.normal.slice(offset, offset + 9));
    const uvOffset = offset / 3 * 2; uv.push(...mesh.uv.slice(uvOffset, uvOffset + 6));
    sourceVertices.push(...mesh.sourceVertices.slice(offset / 3, offset / 3 + 3));
  }
  return {position: new Float32Array(position), normal: new Float32Array(normal), uv: new Float32Array(uv), sourceVertices};
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
  const {bones, worldPositions} = rigFor(body);
  const headOffset = body === 'male' ? 1.4382 * scale : 0;
  const isShoes = id.startsWith('shoe-');
  const sockIsland = isShoes ? (uv => id === 'shoe-0' ? uv[0] > .83 && uv[1] < .30 : uv[0] > .76 && uv[1] > .76) : null;
  const mesh = parseObj(resolve(source, obj), [0, isHair ? headOffset : 0, 0], sockIsland);
  const headHeight = body === 'male' ? 1.65 : 1.51;
  const neckHeight = body === 'male' ? 1.57 : 1.43;
  const feet = position => position[1] <= .085 || (position[2] > .08 && position[1] <= .12);
  const viewChunks = [], views = [], accessors = [];
  const add = (data, componentType, type, count, target) => {
    const buffer = Buffer.from(data.buffer, data.byteOffset, data.byteLength), offset = viewChunks.reduce((sum, value) => sum + align(value.length), 0);
    views.push({buffer: 0, byteOffset: offset, byteLength: buffer.length, ...(target ? {target} : {})}); viewChunks.push(buffer);
    accessors.push({bufferView: views.length - 1, componentType, count, type}); return accessors.length - 1;
  };
  const regions = isAvatar ? [
    ['region_head', selectTriangles(mesh, p => p[1] > neckHeight)],
    ['region_arms', selectTriangles(mesh, p => p[1] <= neckHeight && p[1] > .88 && Math.abs(p[0]) > .25)],
    ['region_upper_legs', selectTriangles(mesh, p => p[1] <= .88 && p[1] > .38)],
    ['region_legs', selectTriangles(mesh, p => p[1] <= .38 && !feet(p))],
    ['region_feet', selectTriangles(mesh, feet)],
    ['region_torso', selectTriangles(mesh, p => p[1] > .88 && p[1] <= neckHeight && Math.abs(p[0]) <= .25)],
  ].filter(([, region]) => region.position.length) : isShoes
    ? ['female', 'male'].map(fit => [id + '-fit-' + fit, fittedShoe(mesh, fit), fit]) : [[id, mesh]];
  if (isAvatar) {
    // The eyes source uses a floor origin; the body/brows use a centred
    // MakeHuman origin. Male garments fit the taller male_generic body.
    const eyeOffset = body === 'male' ? -7.65 : -8.98;
    const browOffset = body === 'male' ? .71 : -.62;
    regions.push(['face_eyes', parseObj(resolve(source, 'eyes/high-poly/high-poly.obj'), [0, eyeOffset * scale, -.20 * scale])]);
    regions.push(['face_brows', parseObj(resolve(source, 'eyebrows/eyebrow001/eyebrow001.obj'), [0, browOffset * scale, 0])]);
  }
  const meshes = [], nodes = [];
  const coverage = isAvatar && body === 'female' ? Object.fromEntries(Object.entries(assets)
    .filter(([, [fit, path]]) => fit === body && path.startsWith('clothes/') && !path.includes('shoes'))
    .map(([item, [, path]]) => {
      const folder = resolve(source, dirname(path));
      const clothes = readdirSync(folder).find(file => file.endsWith('.mhclo'));
      const weights = proxyCoverage(readFileSync(resolve(source, 'proxymeshes/female1605/female1605.proxy'), 'utf8'),
        deletedVertices(readFileSync(resolve(folder, clothes), 'utf8')));
      return [item, weights];
    })) : {};
  for (const [name, rawRegion, fitBody] of regions) {
    const region = indexed(rawRegion);
    const positions = add(region.position, 5126, 'VEC3', region.position.length / 3, 34962);
    accessors[positions].min = [0, 1, 2].map(axis => Math.min(...Array.from(region.position).filter((_, index) => index % 3 === axis)));
    accessors[positions].max = [0, 1, 2].map(axis => Math.max(...Array.from(region.position).filter((_, index) => index % 3 === axis)));
    const normals = add(region.normal, 5126, 'VEC3', region.normal.length / 3, 34962);
    const uvs = add(region.uv, 5126, 'VEC2', region.uv.length / 2, 34962);
    const joints = new Uint16Array(region.position.length / 3 * 4), jointWeights = new Float32Array(region.position.length / 3 * 4);
    for (let vertex = 0; vertex < region.position.length / 3; vertex++) {
      const skin = skinWeights(region.position.slice(vertex * 3, vertex * 3 + 3), {body, headHeight, hair: isHair || name.startsWith('face_'), shoes: isShoes, skirt: !isAvatar && /dress|flapper|kimono/.test(obj)});
      joints.set(skin.joints, vertex * 4); jointWeights.set(skin.weights, vertex * 4);
    }
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
    const masks = name.startsWith('region_') ? Object.fromEntries(Object.entries(coverage)
      .map(([item, weights]) => [item, coveredTriangles(rawRegion.sourceVertices, weights)])) : {};
    nodes.push({name, mesh: meshes.length - 1, skin: 0,
      ...((fitBody || Object.keys(masks).length) ? {extras: {...(fitBody ? {slayBody: fitBody} : {}),
        ...(Object.keys(masks).length ? {slayCoverage: masks} : {})}} : {})});
  }
  const inverse = new Float32Array(worldPositions.flatMap(mat4Translation)); const inverseAccessor = add(inverse, 5126, 'MAT4', bones.length);
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
  const animations = isAvatar ? Object.keys(poses).map(name => {
    const input = add(new Float32Array([0, 1.5, 3]), 5126, 'SCALAR', 3);
    accessors[input].min = [0]; accessors[input].max = [3];
    const samplers = [], channels = [];
    // Key every joint, including identity, so switching poses cannot retain
    // an elbow/hip from the previous stance.
    bones.forEach(([bone], index) => {
      const output = add(new Float32Array([0, 1, 0].flatMap(breath => poseQuaternion(name, bone, breath))), 5126, 'VEC4', 3);
      samplers.push({input, output, interpolation: 'LINEAR'});
      channels.push({sampler: samplers.length - 1, target: {node: firstBone + index, path: 'rotation'}});
    });
    return {name, samplers, channels};
  }) : [];
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
