/*
 * Converts the selected licensed MakeHuman OBJ sources into self-contained GLBs.
 *
 * The MakeHuman sources do not include a game-runtime skeleton. This converter
 * provides one shared lightweight fashion rig, conservative auto weights and
 * five short pose clips. It is deliberately a starter-art pipeline: validate
 * and visually review each result before enabling it in a production catalog.
 */
import {mkdirSync, readFileSync, writeFileSync, readdirSync, copyFileSync} from 'node:fs';
import {dirname, resolve} from 'node:path';
import {execFileSync} from 'node:child_process';
import {TorusGeometry} from 'three';
import {rigFor, skinWeights, poses, poseQuaternion} from './starter-rig.mjs';
import {deletedVertices, proxyCoverage, coveredTriangles} from './makehuman-coverage.mjs';
import {expansion} from './wardrobe-expansion.mjs';
import {classicClothing} from './classic-clothing.mjs';
import {hairFits} from './hair-fits.mjs';
import {clipMesh, joinMeshes} from './clip-mesh.mjs';
import {fitMaleBottom} from './male-bottom-fit.mjs';

const root = resolve(new URL('..', import.meta.url).pathname);
const source = process.argv[2] ? resolve(process.argv[2]) : resolve(root, 'source_assets/makehuman/starter');
const output = process.argv[3] ? resolve(process.argv[3]) : resolve(root, '../app/assets/slay_renderer/assets');
const scale = 1.8 / 16.044; // Female height is 1.8 m; the matching male body is taller.
const bodySources = {
  female: {obj: 'proxymeshes/female1605/female1605.obj', texture: 'skins/young_african_female/young_darkskinned_female_diffuse.png'},
  male: {obj: 'proxymeshes/male_generic/male_generic.obj', texture: 'skins/young_african_male/young_darkskinned_male_diffuse.png'},
};
const assets = {
  ...expansion,
  ...classicClothing,
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

function fittedShoe(mesh, body, options = {}) {
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
  target[1] = [.001, options.ankleBoot ? .26 : options.height ?? Math.max(.115, target[1][1] + .012)];
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
function fittedEyes(mesh, body) {
  if (body !== 'male') return mesh;
  // The generic male has wider, higher, deeper-set sockets than female1605.
  // Copying the female placement left every iris behind the face surface.
  for (let i = 0; i < mesh.position.length; i += 3) {
    mesh.position[i] *= 1.15;
    mesh.position[i + 1] += .010;
    mesh.position[i + 2] += .015;
    mesh.normal[i] /= 1.15;
    const length = Math.hypot(...mesh.normal.slice(i,i+3)) || 1;
    for (let axis=0;axis<3;axis++) mesh.normal[i+axis] /= length;
  }
  return mesh;
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
function convert({id, body, obj, texture, isAvatar, options = {}}) {
  const isHair = id.includes('hair');
  const {bones, worldPositions} = rigFor(body);
  const headOffset = body === 'male' ? 1.4382 * scale : 0;
  const isShoes = id.startsWith('shoe-') || options.shoe;
  const sockIsland = id === 'shoe-0' || id === 'shoe-1' ? (uv => id === 'shoe-0' ? uv[0] > .83 && uv[1] < .30 : uv[0] > .76 && uv[1] > .76) : null;
  const eyeOffset = body === 'male' ? -7.65 : -8.98;
  let mesh = parseObj(resolve(source, obj), [0, isHair ? headOffset : options.eyes ? eyeOffset * scale : 0, options.eyes ? -.20 * scale : 0], sockIsland);
  if (options.eyes) mesh = fittedEyes(mesh, body);
  if (isHair && hairFits[id]) for (let i = 1; i < mesh.position.length; i += 3) mesh.position[i] += hairFits[id];
  if (options.noseRing) {
    // Small nostril hoop fitted to female1605, rather than a floating facial
    // accessory. Bake world-space geometry before assigning the shared rig.
    const hoop = new TorusGeometry(.0045, .0008, 8, 32);
    hoop.rotateY(.30); hoop.translate(.014, 1.643, .163);
    const triangles = hoop.toNonIndexed();
    mesh = {position: triangles.attributes.position.array,
      normal: triangles.attributes.normal.array, uv: triangles.attributes.uv.array,
      sourceVertices: Array.from({length: triangles.attributes.position.count}, (_, i) => i)};
    triangles.dispose(); hoop.dispose();
  }
  if (options.crop) mesh = clipMesh(mesh, [p => p[1] - options.crop]);
  if (options.upperCrop) mesh = clipMesh(mesh, [p => options.upperCrop - p[1]]);
  if (body === 'male' && options.bottom)
    mesh = fitMaleBottom(mesh, parseObj(resolve(source, bodySources.male.obj)));
  if (options.tubeTop) {
    // This source was authored on a shorter, narrower body. Fit the bust band
    // to female1605 before calculating weights; otherwise it sits inside the
    // abdomen while the studio hides the starter bra.
    for (let i=0;i<mesh.position.length;i+=3) {
      mesh.position[i] *= 1.25;
      mesh.position[i+1] += .30;
      const z=mesh.position[i+2];
      mesh.position[i+2] = z * 1.4 + .022 - .06 * Math.max(0, Math.min(1, 1-z/.1));
      mesh.normal[i] /= 1.25; mesh.normal[i+2] /= 1.4;
      const length=Math.hypot(...mesh.normal.slice(i,i+3)) || 1;
      for (let axis=0;axis<3;axis++) mesh.normal[i+axis] /= length;
    }
  }
  if (id === 'male-tee-polo') {
    // This community shirt was authored on a shorter shoulder line.
    // Lift its collar/shoulders, leaving its hem at the fitted waist.
    for (let i = 1; i < mesh.position.length; i += 3)
      mesh.position[i] += .055 * Math.max(0, Math.min(1, (mesh.position[i] - 1.35) / .22));
  }
  if (options.lips) {
    // Follow the lip folds of the source mesh, including the Cupid's bow,
    // rather than placing a floating primitive in front of the mouth.
    mesh = selectTriangles(mesh, p => p[1] > 1.603 && p[1] < 1.626 && Math.abs(p[0]) < .030 && p[2] > .146);
    // Clip the contour instead of keeping whole neighbouring skin triangles,
    // which produced angular corners and coloured the chin below the lips.
    mesh = clipMesh(mesh, [
      p => .027 - Math.abs(p[0]),
      p => p[1] - (1.6055 + .0065 * (Math.abs(p[0]) / .027) ** 2),
      p => (1.624 - .012 * (Math.abs(p[0]) / .027) ** 2 -
        .003 * Math.exp(-((p[0] / .004) ** 2))) - p[1],
      p => p[2] - .146,
    ]);
    for (let i = 0; i < mesh.position.length; i++) mesh.position[i] += mesh.normal[i] * .0007;
  }
  if (options.earrings) {
    // Centre each downloaded earring at the fitted female earlobe.
    const points = [];
    for (let i = 0; i < mesh.position.length; i += 3) if (mesh.position[i] > 0) points.push(Array.from(mesh.position.slice(i, i + 3)));
    const ranges = [0, 1, 2].map(axis => [Math.min(...points.map(p => p[axis])), Math.max(...points.map(p => p[axis]))]);
    const factor = id.endsWith('hoops') ? .60 : id.endsWith('pearls') ? 1.5 : 1.2;
    for (let i = 0; i < mesh.position.length; i += 3) {
      const side = mesh.position[i] >= 0 ? 1 : -1;
      const x = (Math.abs(mesh.position[i]) - (ranges[0][0] + ranges[0][1]) / 2) * factor;
      const z = (mesh.position[i + 2] - (ranges[2][0] + ranges[2][1]) / 2) * factor;
      mesh.position[i] = side * (.087 + (id.endsWith('hoops') ? z : x));
      mesh.position[i + 1] = 1.643 + (mesh.position[i + 1] - ranges[1][1]) * factor;
      mesh.position[i + 2] = .060 + (id.endsWith('hoops') ? -x : z);
      if (id.endsWith('hoops')) {
        const nx = mesh.normal[i]; mesh.normal[i] = side * mesh.normal[i + 2]; mesh.normal[i + 2] = -side * nx;
      }
    }
  }
  if (options.bag === 'hand') {
    const ranges = [0, 1, 2].map(axis => [Math.min(...Array.from(mesh.position).filter((_, i) => i % 3 === axis)), Math.max(...Array.from(mesh.position).filter((_, i) => i % 3 === axis))]);
    // Keep the handle at the right hand; use a rigid hand weight so it follows
    // a bent elbow rather than staying behind at the original hip.
    const target = [-.52, .99, .30], height = .32;
    const factor = height / (ranges[1][1] - ranges[1][0]);
    for (let i = 0; i < mesh.position.length; i += 3) for (let axis = 0; axis < 3; axis++) {
      const centre = axis === 1 ? ranges[axis][1] : (ranges[axis][0] + ranges[axis][1]) / 2;
      mesh.position[i + axis] = target[axis] + (mesh.position[i + axis] - centre) * factor;
    }
  }
  if (options.bag === 'hand') {
    // Source bags face sideways; turn their broad face towards the camera.
    for (let i = 0; i < mesh.position.length; i += 3) {
      const x = mesh.position[i] + .52, z = mesh.position[i + 2] - .30;
      mesh.position[i] = -.52 + z; mesh.position[i + 2] = .30 - x;
      const nx = mesh.normal[i]; mesh.normal[i] = mesh.normal[i + 2]; mesh.normal[i + 2] = -nx;
    }
  }
  const headHeight = body === 'male' ? 1.65 : 1.51;
  const neckHeight = body === 'male' ? 1.57 : 1.43;
  const feet = position => position[1] <= .085 || (position[2] > .08 && position[1] <= .12);
  const arms = p => p[1] <= neckHeight && Math.abs(p[0]) > .25 &&
    (p[1] > .88 || (Math.abs(p[0]) > .44 && p[1] > .70));
  const viewChunks = [], views = [], accessors = [];
  const add = (data, componentType, type, count, target) => {
    const buffer = Buffer.from(data.buffer, data.byteOffset, data.byteLength), offset = viewChunks.reduce((sum, value) => sum + align(value.length), 0);
    views.push({buffer: 0, byteOffset: offset, byteLength: buffer.length, ...(target ? {target} : {})}); viewChunks.push(buffer);
    accessors.push({bufferView: views.length - 1, componentType, count, type}); return accessors.length - 1;
  };
  const regions = isAvatar ? [
    ['region_head', selectTriangles(mesh, p => p[1] > neckHeight)],
    ['region_arms', selectTriangles(mesh, arms)],
    ['region_upper_legs', selectTriangles(mesh, p => p[1] <= .88 && p[1] > .38 && !arms(p))],
    ['region_legs', selectTriangles(mesh, p => p[1] <= .38 && !feet(p))],
    ['region_feet', selectTriangles(mesh, feet)],
    ['region_torso', selectTriangles(mesh, p => p[1] > .88 && p[1] <= neckHeight && Math.abs(p[0]) <= .25)],
  ].filter(([, region]) => region.position.length) : isShoes
    ? (body === 'unisex' ? ['female', 'male'] : [body]).map(fit => [id + '-fit-' + fit, fittedShoe(mesh, fit, options), fit]) : [[id, mesh]];
  if (isAvatar) {
    // The eyes source uses a floor origin; the body/brows use a centred
    // MakeHuman origin. Male garments fit the taller male_generic body.
    const eyeOffset = body === 'male' ? -7.65 : -8.98;
    const browOffset = body === 'male' ? .71 : -.62;
    const underwear = (name, boxes) => {
      const fitted = joinMeshes(boxes.map(([low, high, left, right]) => clipMesh(mesh, [
        p => p[1] - low, p => high - p[1], p => p[0] - left, p => right - p[0],
      ])));
      for (let i = 0; i < fitted.position.length; i++) fitted.position[i] += fitted.normal[i] * .002;
      regions.push([name, fitted]);
    };
    underwear('starter_briefs', [[body === 'male' ? .77 : .83, body === 'male' ? 1.075 : .995, -.25, .25]]);
    if (body === 'female') underwear('starter_bra', [
      [1.245, 1.385, -.18, .18], [1.385, 1.465, .105, .14], [1.385, 1.465, -.14, -.105],
    ]);
    regions.push(['face_eyes', fittedEyes(parseObj(resolve(source, 'eyes/high-poly/high-poly.obj'), [0, eyeOffset * scale, -.20 * scale]), body)]);
    regions.push(['face_brows', parseObj(resolve(source, 'eyebrows/eyebrow001/eyebrow001.obj'), [0, browOffset * scale, 0])]);
  }
  const meshes = [], nodes = [];
  const bottomBounds = isAvatar ? Object.fromEntries(Object.entries(assets)
    .filter(([, [fit, , , options]]) => fit === body && options?.bottom)
    .map(([item, [, path]]) => {
      let cloth = parseObj(resolve(source, path));
      if (body === 'male') cloth = fitMaleBottom(cloth, parseObj(resolve(source, bodySources.male.obj)));
      const heights = Array.from(cloth.position).filter((_, i) => i % 3 === 1);
      // The front waistband dips below the highest side seam. A max-height
      // body mask erased the abdomen above that dip and left a hollow gap.
      return [item, [Math.min(...heights), body === 'male' ? Math.min(1.10, Math.max(...heights)) : Math.max(...heights)]];
    })) : {};
  const coverage = isAvatar && body === 'female' ? Object.fromEntries(Object.entries(assets)
    .filter(([, [fit, path, , options]]) => fit === body && path.startsWith('clothes/') && !path.includes('shoes') && !options?.shoe && !options?.earrings && !options?.bag)
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
      const skin = options.bag === 'hand' ? {joints: [11, 0, 0, 0], weights: [1, 0, 0, 0]}
        : skinWeights(region.position.slice(vertex * 3, vertex * 3 + 3), {body, headHeight, hair: isHair || name.startsWith('face_') || options.eyes || options.lips || options.earrings || options.noseRing, shoes: isShoes, ankleBoot: options.ankleBoot, skirt: !isAvatar && /dress|flapper|kimono|skirt/.test(obj)});
      joints.set(skin.joints, vertex * 4); jointWeights.set(skin.weights, vertex * 4);
    }
    const jointAccessor = add(joints, 5123, 'VEC4', joints.length / 4, 34962), weightAccessor = add(jointWeights, 5126, 'VEC4', jointWeights.length / 4, 34962);
    const indexAccessor = add(region.indices, 5125, 'SCALAR', region.indices.length, 34963);
    const primitive = {attributes: {POSITION: positions, NORMAL: normals, TEXCOORD_0: uvs, JOINTS_0: jointAccessor, WEIGHTS_0: weightAccessor}, indices: indexAccessor, material: name.startsWith('starter_') ? 3 : name === 'face_eyes' ? 1 : name === 'face_brows' ? 2 : 0};
    if ((isAvatar && name === 'region_head') || options.lips || options.noseRing) {
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
    meshes.push({name, primitives: [primitive], ...(((isAvatar && name === 'region_head') || options.lips || options.noseRing) ? {extras: {targetNames: ['face_classic', 'face_soft', 'face_angular', 'expression_smile']}} : {})});
    const masks = name.startsWith('region_') ? Object.fromEntries(Object.entries(coverage)
      .map(([item, weights]) => [item, coveredTriangles(rawRegion.sourceVertices, weights).filter(triangle => {
        const crop = assets[item][3]?.crop;
        return !crop || [0,3,6].every(v => rawRegion.position[triangle * 9 + v + 1] >= crop - .006);
      })])) : {};
    if (name === 'region_torso') for (const [item, asset] of Object.entries(assets)) {
      if (asset[0] !== body || !asset[3]?.tubeTop) continue;
      // The source has no authored delete_verts. Mask only fully covered
      // chest-band faces, retaining the bare shoulders and midriff.
      for (let i=0;i<rawRegion.position.length;i+=9)
        if ([0,3,6].every(v => rawRegion.position[i+v+1] > 1.245 &&
            rawRegion.position[i+v+1] < 1.405 && Math.abs(rawRegion.position[i+v]) < .165))
          masks[item].push(i/9);
    }
    if (name.startsWith('region_')) for (const [item, [hem, waist]] of Object.entries(bottomBounds)) {
      masks[item] ??= [];
      // Mask complete triangles inside trousers, preserving bare ankles and
      // the thighs below shorts, including on the male body without a proxy.
      for (let i = 0; i < rawRegion.position.length; i += 9) {
        if ([0, 3, 6].every(v => rawRegion.position[i + v + 1] > hem + .012 &&
          rawRegion.position[i + v + 1] < waist + .008 && Math.abs(rawRegion.position[i + v]) < .34)) masks[item].push(i / 9);
      }
    }
    nodes.push({name, mesh: meshes.length - 1, skin: 0,
      ...((fitBody || Object.keys(masks).length) ? {extras: {...(fitBody ? {slayBody: fitBody} : {}),
        ...(Object.keys(masks).length ? {slayCoverage: masks} : {})}} : {})});
  }
  const inverse = new Float32Array(worldPositions.flatMap(mat4Translation)); const inverseAccessor = add(inverse, 5126, 'MAT4', bones.length);
  const textures = isAvatar ? [texture, 'eyes/materials/brown_eye.png', 'eyebrows/eyebrow001/eyebrow001.png'] : texture ? [texture] : [];
  const images = textures.map(texture => {
    // Cache mobile-sized textures without altering the downloaded sources.
    const texturePath = resolve(source, texture);
    const optimisedPath = resolve(source, '.mobile-textures', texture.replace(/\.[^.]+$/, '.png'));
    mkdirSync(dirname(optimisedPath), {recursive: true});
    if (process.platform === 'darwin') {
      const size = options.eyes || options.earrings ? '256' : options.bag || id in expansion ? '512' : '1024';
      execFileSync('sips', [...(texture.endsWith('.png') ? [] : ['-s', 'format', 'png']), '--resampleHeightWidthMax', size, texturePath, '--out', optimisedPath], {stdio: 'ignore'});
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
  const materials = images.map((_, index) => ({name: id + '-material-' + index, doubleSided: !isAvatar || index > 0, ...((isHair || options.alpha || index === 2 || options.eyes || (isAvatar && index === 1)) ? {alphaMode: 'MASK', alphaCutoff: .35} : {}), pbrMetallicRoughness: {baseColorTexture: {index}, ...(options.tint ? {baseColorFactor: options.tint} : {}), metallicFactor: options.earrings ? .65 : 0, roughnessFactor: options.eyes || index === 1 ? .35 : .85}}));
  if (isAvatar) materials.push({name: body + '-base-underwear', doubleSided: true, pbrMetallicRoughness: {baseColorFactor: [.07, .055, .09, 1], metallicFactor: 0, roughnessFactor: .9}});
  if (!texture) materials.push({name: id + (options.noseRing ? '-gold' : '-lip-colour'), doubleSided: false, pbrMetallicRoughness: {baseColorFactor: options.colour, metallicFactor: options.noseRing ? .85 : 0, roughnessFactor: options.noseRing ? .25 : .38}});
  const document = {asset: {version: '2.0', generator: 'SlayHuud MakeHuman starter converter'}, scene: 0, scenes: [{nodes: [...meshes.keys(), firstBone]}], nodes, meshes, skins: [{name: 'slay-shared-rig-v1', inverseBindMatrices: inverseAccessor, joints: bones.map((_, index) => firstBone + index), skeleton: firstBone}], materials, textures: images.map((_, source) => ({source})), images, buffers: [{byteLength: viewChunks.reduce((sum, value) => sum + align(value.length), 0)}], bufferViews: views, accessors, animations};
  writeFileSync(resolve(output, id + '.glb'), encodeGlb(document, viewChunks));
  const sourceFolder = resolve(source, dirname(obj));
  const thumbnail = readdirSync(sourceFolder).find(file => file.endsWith('.thumb'));
  if (thumbnail) copyFileSync(resolve(sourceFolder, thumbnail), resolve(output, id + '.png'));
  return {id, triangles: meshes.reduce((sum, mesh) => sum + mesh.primitives.reduce((n, primitive) => n + accessors[primitive.indices].count / 3, 0), 0), bytes: readFileSync(resolve(output, id + '.glb')).length};
}

mkdirSync(output, {recursive: true});
const report = [];
const selected = process.argv.find(arg => arg.startsWith('--only='))?.slice(7).split(',');
for (const [body, entry] of Object.entries(bodySources).filter(([id]) => !selected || selected.includes(id))) report.push(convert({id: body, body, ...entry, isAvatar: true}));
for (const [id, [body, obj, texture, options]] of Object.entries(assets).filter(([id]) => !selected || selected.includes(id))) report.push(convert({id, body, obj, texture, options, isAvatar: false}));
if (!selected) writeFileSync(resolve(output, 'makehuman-starter-report.json'), JSON.stringify({source: 'MakeHuman Community CC0 and attributed CC-BY asset packs; see credits.txt', generatedAt: new Date().toISOString(), assets: report}, null, 2) + '\n');
console.log(JSON.stringify(report, null, 2));
