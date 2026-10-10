import * as T from 'three';

/** Styling happens in a stage's dressing room; the catwalk and photo happen at its venue. */
export type SceneMode = 'room' | 'venue';

type Spec = {sky: string; build: (kit: Kit) => void};

/** Small builder for low-poly props. Repeated props are instanced to keep draw calls down. */
class Kit {
  readonly group = new T.Group();
  readonly flashes: T.MeshStandardMaterial[] = [];
  private materials = new Map<string, T.MeshStandardMaterial>();
  mat(color: string, {metal = 0, glow = 0, opacity = 1} = {}) {
    const key = [color, metal, glow, opacity].join('|');
    let material = this.materials.get(key);
    if (!material) {
      material = new T.MeshStandardMaterial({color, metalness: metal, roughness: metal ? .4 : .8,
        emissive: glow ? color : '#000000', emissiveIntensity: glow, transparent: opacity < 1, opacity});
      this.materials.set(key, material);
    }
    return material;
  }
  add(geometry: T.BufferGeometry, material: T.Material, x: number, y: number, z: number, turn = 0) {
    const mesh = new T.Mesh(geometry, material); mesh.position.set(x, y, z); mesh.rotation.y = turn; this.group.add(mesh); return mesh;
  }
  box(w: number, h: number, d: number, material: T.Material, x: number, y: number, z: number, turn = 0) {
    return this.add(new T.BoxGeometry(w, h, d), material, x, y, z, turn);
  }
  many(geometry: T.BufferGeometry, material: T.Material, points: [number, number, number][]) {
    const mesh = new T.InstancedMesh(geometry, material, points.length), m = new T.Matrix4();
    points.forEach(([x, y, z], i) => mesh.setMatrixAt(i, m.makeTranslation(x, y, z)));
    mesh.instanceMatrix.needsUpdate = true; this.group.add(mesh); return mesh;
  }
  /** Warm vanity/dressing-room bulbs framing a mirror. */
  bulbMirror(x: number, z: number, width: number, height: number, frame: T.Material, glass: string, bulb: string) {
    this.box(width, height, .06, frame, x, 1.75, z);
    this.box(width - .09, height - .09, .03, this.mat(glass, {metal: .3}), x, 1.75, z + .04);
    const points: [number, number, number][] = [];
    for (let y = 1.75 - height / 2 + .15; y < 1.75 + height / 2; y += .3) points.push([x - width / 2 - .06, y, z + .05], [x + width / 2 + .06, y, z + .05]);
    for (let dx = -width / 2 + .1; dx < width / 2; dx += .22) points.push([x + dx, 1.75 + height / 2 + .07, z + .05]);
    this.many(new T.SphereGeometry(.055, 8, 6), this.mat(bulb, {glow: .9}), points);
  }
  /** A clothes rail with hanging garments. */
  rail(x: number, z: number, colours: string[], metal: T.Material) {
    const width = colours.length * .32 + .2;
    for (const dx of [-width / 2, width / 2]) this.add(new T.CylinderGeometry(.02, .02, 1.9, 8), metal, x + dx, .95, z);
    const bar = this.add(new T.CylinderGeometry(.018, .018, width, 8), metal, x, 1.9, z); bar.rotation.z = Math.PI / 2;
    colours.forEach((colour, i) => this.box(.27, .78, .08, this.mat(colour), x - width / 2 + .26 + i * .32, 1.45, z + .02));
  }
  floor(colour: string, width = 9) { this.box(width, .09, 2.2, this.mat(colour), 0, -.09, -4.2); }
  wall(colour: string, width = 9, height = 4.2) { this.box(width, height, .08, this.mat(colour), 0, height / 2 - .2, -4.5); }
  windows(x: number, width: number, top: number, z: number, glow: string) {
    const points: [number, number, number][] = [];
    for (let y = .7; y < top - .3; y += .55) for (let dx = -width / 2 + .25; dx < width / 2 - .1; dx += .42) points.push([x + dx, y, z]);
    this.many(new T.BoxGeometry(.22, .3, .02), this.mat(glow, {glow: .7}), points);
  }
}

/** Codex's original starter dressing room: wardrobe, vanity lights and flowers. */
function bedroomVanity(k: Kit) {
  const cream = k.mat('#e5d6c8'), rose = k.mat('#c99798'), gold = k.mat('#bf9351', {metal: .55}), wood = k.mat('#9b7264');
  k.box(8, 4, .08, cream, 0, 1.7, -4.4);
  k.box(8, .09, 2, k.mat('#e4dbd0'), 0, -.09, -4.1);
  for (const x of [-3.4, -1.25, 1.25, 3.4]) k.box(.025, 3.5, .035, gold, x, 1.7, -4.34);
  k.box(1.55, .11, .65, wood, -2.1, .14, -3.8);
  k.box(1.55, .11, .65, wood, -2.1, 2.45, -3.8);
  for (const x of [-2.85, -1.35]) k.box(.10, 2.3, .65, wood, x, 1.3, -3.8);
  const rail = k.add(new T.CylinderGeometry(.022, .022, 1.35, 8), gold, -2.1, 2.17, -3.72); rail.rotation.z = Math.PI / 2;
  for (const [i, color] of ['#b95972', '#718d80', '#e8bd68', '#677494'].entries()) {
    const x = -2.61 + i * .34;
    k.box(.29, .62, .07, k.mat(color), x, 1.58, -3.65);
    const hanger = k.add(new T.TorusGeometry(.12, .008, 5, 12, Math.PI), gold, x, 1.96, -3.65); hanger.rotation.z = Math.PI;
  }
  k.box(.9, 1.55, .08, gold, 2.1, 1.75, -4.05);
  k.box(.81, 1.46, .04, k.mat('#c7c4bc', {metal: .3}), 2.1, 1.75, -3.99);
  const bulbs: [number, number, number][] = [];
  for (const x of [1.57, 2.63]) for (const y of [1.22, 1.65, 2.08, 2.51]) bulbs.push([x, y, -3.97]);
  k.many(new T.SphereGeometry(.065, 8, 6), new T.MeshStandardMaterial({color: '#fff0cc', emissive: '#ffd199', emissiveIntensity: .8}), bulbs);
  k.box(1.28, .09, .55, wood, 2.1, .85, -3.8);
  // A fashion mood board and fairy lights frame the styling portrait.
  k.box(1.5, .9, .04, k.mat('#f4ece2'), 0, 2.75, -4.33);
  ['#e3a2b2', '#718d80', '#e8bd68', '#677494', '#b95972', '#c9b8e6'].forEach((colour, i) => k.box(.36, .3, .02, k.mat(colour), -.48 + (i % 3) * .48, 2.92 - Math.floor(i / 3) * .36, -4.3));
  const fairy: [number, number, number][] = [];
  for (let i = 0; i <= 16; i++) {const t = i / 16; fairy.push([-1.9 + 3.8 * t, 3.35 - Math.sin(Math.PI * t) * .22, -4.25]);}
  k.many(new T.SphereGeometry(.045, 8, 6), k.mat('#ffe3b0', {glow: 1}), fairy);
  k.add(new T.CylinderGeometry(.19, .13, .43, 12), rose, -1.48, .24, -3.43);
  const green = k.mat('#648a69'), petal = k.mat('#e3a2b2'), centre = k.mat('#e7bf6c');
  for (let i = 0; i < 5; i++) {
    const x = -1.48 + Math.sin(i * 2.4) * .16, y = .75 + (i % 3) * .11, z = -3.43 + Math.cos(i * 2.4) * .12;
    k.add(new T.CylinderGeometry(.01, .01, y - .42, 5), green, x, (y + .42) / 2, z);
    k.many(new T.SphereGeometry(.064, 6, 4), petal, [0, 1, 2, 3, 4].map(j => {const a = j * Math.PI * 2 / 5; return [x + Math.cos(a) * .074, y + Math.sin(a) * .074, z] as [number, number, number];}));
    k.add(new T.SphereGeometry(.035, 6, 4), centre, x, y, z + .035);
  }
}

/** Seamless paper, softboxes and a ring light: the first shoot at home. */
function homePhotoWall(k: Kit) {
  k.floor('#e3d3e6'); k.wall('#e6d6e8');
  const stand = k.mat('#2b2b2e', {metal: .5}), soft = k.mat('#fff6e8', {glow: .9});
  for (const [x, turn] of [[-1.25, .35], [1.25, -.35]] as const) {
    k.add(new T.CylinderGeometry(.02, .03, 2, 8), stand, x, 1, -3.6);
    k.box(.7, .9, .18, soft, x, 2.45, -3.6, turn);
  }
  k.add(new T.TorusGeometry(.62, .05, 8, 40), k.mat('#ffffff', {glow: 1.2}), 0, 1.85, -4.3);
  k.add(new T.CylinderGeometry(.22, .17, .5, 12), k.mat('#c3b6a6'), 1.5, .25, -3.5);
  k.many(new T.SphereGeometry(.2, 8, 6), k.mat('#5f8a63'), [[1.45, .75, -3.5], [1.62, .95, -3.52], [1.38, 1.1, -3.48], [1.55, 1.28, -3.5]]);
}

/** Boutique fitting room: curtains, rails, folded stacks and a tall mirror. */
function boutiqueFittingRoom(k: Kit) {
  k.floor('#c9a983'); k.wall('#e7d3bd');
  for (let i = 0; i < 14; i++) k.box(.22, 3.2, .08, k.mat(i % 2 ? '#2f6f6a' : '#2a625e'), -1.43 + i * .22, 1.5, -4.3 + (i % 2) * .06);
  const brass = k.mat('#c49a52', {metal: .6});
  const top = k.add(new T.CylinderGeometry(.02, .02, 2.6, 8), brass, 0, 3.15, -4.1); top.rotation.z = Math.PI / 2;
  ['#c0563f', '#f0e2c6', '#d8a13e', '#7a3b2e', '#efe9df', '#c0563f', '#d8a13e'].forEach((colour, i) => k.box(.3, .6, .06, k.mat(colour), -1.1 + i * .37, 2.8, -4.05));
  k.rail(1.9, -3.9, ['#c0563f', '#f0e2c6', '#2f6f6a', '#d8a13e', '#7a3b2e', '#efe9df'], brass);
  k.box(.7, 2.1, .06, brass, -1.6, 1.25, -4.1);
  k.box(.62, 2.0, .03, k.mat('#cfd3d0', {metal: .35}), -1.6, 1.25, -4.05);
  for (let shelf = 0; shelf < 3; shelf++) {
    k.box(1.1, .05, .4, k.mat('#8b6a4d'), 3.4, .7 + shelf * .65, -4.2);
    for (let i = 0; i < 3; i++) k.box(.28, .12, .3, k.mat(['#c0563f', '#2f6f6a', '#efe9df'][(i + shelf) % 3]), 3.05 + i * .34, .79 + shelf * .65, -4.2);
  }
  for (const x of [-.8, .8, 2.6]) {
    k.add(new T.CylinderGeometry(.008, .008, .7, 6), brass, x, 3.25, -3.7);
    k.add(new T.SphereGeometry(.11, 10, 8), k.mat('#ffe2a8', {glow: .9}), x, 2.85, -3.7);
  }
}

/** A city street: facades with lit windows, lamps and a crosswalk. */
function cityStreet(k: Kit) {
  k.floor('#3c3c40', 11);
  k.many(new T.BoxGeometry(.32, .02, 1.6), k.mat('#f1f1ec'), [-1.6, -.9, -.2, .5, 1.2, 1.9].map(x => [x, -.035, -4.1] as [number, number, number]));
  const facades: [number, number, string][] = [[-4.4, 3.6, '#c97b5a'], [-2.6, 4.6, '#efe2c8'], [-.7, 3.2, '#5d8f8a'], [1.1, 4.2, '#d9b45f'], [2.9, 3.8, '#b7564a'], [4.6, 4.9, '#e6dccb']];
  for (const [x, height, colour] of facades) {
    k.box(1.8, height, .9, k.mat(colour), x, height / 2 - .1, -5.6);
    k.windows(x, 1.8, height, -5.14, '#ffe6a8');
  }
  const pole = k.mat('#2f3236', {metal: .5});
  for (const x of [-2.5, 2.5]) {
    k.add(new T.CylinderGeometry(.04, .05, 2.8, 8), pole, x, 1.3, -3.4);
    k.add(new T.SphereGeometry(.16, 10, 8), k.mat('#fff2c4', {glow: 1}), x, 2.75, -3.4);
  }
  k.box(1.6, .8, .06, k.mat('#e8486b', {glow: .6}), -1.6, 3.4, -5.1);
}

/** Club green room: dark velvet, neon rings and a bulb mirror. */
function clubGreenRoom(k: Kit) {
  k.floor('#1c1420'); k.wall('#2a1830');
  k.add(new T.TorusGeometry(.55, .04, 8, 40), k.mat('#ff4fa3', {glow: 1.4}), -.25, 2.75, -4.4);
  k.add(new T.TorusGeometry(.32, .035, 8, 32), k.mat('#3fe0ff', {glow: 1.4}), .55, 2.45, -4.4);
  k.box(2.6, .04, .04, k.mat('#c86bff', {glow: 1.2}), 0, 3.45, -4.4);
  k.bulbMirror(1.9, -4.35, 1.1, 1.3, k.mat('#1a1a1a', {metal: .4}), '#9b98a8', '#fff0cc');
  const velvet = k.mat('#6b2050');
  k.box(1.8, .42, .7, velvet, -2.3, .21, -3.9); k.box(1.8, .6, .18, velvet, -2.3, .6, -4.2);
  k.box(.7, .5, .45, k.mat('#2b2b2e', {metal: .4}), .3, .25, -3.9);
  k.many(new T.CylinderGeometry(.04, .05, .3, 8), k.mat('#3fb37a', {glow: .25}), [[.15, .65, -3.9], [.3, .65, -3.85], [.45, .65, -3.92]]);
}

/** A rooftop at night: skyline, string lights, glass rail and moon. */
function rooftopNight(k: Kit) {
  k.floor('#3b3029', 11);
  const skyline: [number, number][] = [[-5, 3.2], [-3.8, 4.8], [-2.4, 2.6], [-1.2, 5.6], [.2, 3.4], [1.5, 4.4], [2.8, 2.9], [4.1, 5.2], [5.3, 3.6]];
  for (const [x, height] of skyline) {
    k.box(1.1, height, .8, k.mat('#1d2340'), x, height / 2 - .1, -7);
    k.windows(x, 1.1, height, -6.58, '#ffd27a');
  }
  k.box(9, .9, .05, k.mat('#a8c6d8', {opacity: .25}), 0, .35, -3.15);
  const pole = k.mat('#2a2a2e', {metal: .5});
  for (const x of [-3.6, 3.6]) k.add(new T.CylinderGeometry(.035, .04, 2.6, 8), pole, x, 1.2, -3.5);
  const bulbs: [number, number, number][] = [];
  for (let i = 0; i <= 24; i++) {const t = i / 24, x = -3.6 + 7.2 * t; bulbs.push([x, 3.25 - Math.sin(Math.PI * t) * .5, -3.5]);}
  k.many(new T.SphereGeometry(.07, 8, 6), k.mat('#ffd9a0', {glow: 1.3}), bulbs);
  k.add(new T.SphereGeometry(.35, 16, 12), k.mat('#f4f0de', {glow: .9}), 1.2, 3.9, -8);
}

/** Hotel suite vanity: panelled cream walls, arched mirror and a crystal chandelier. */
function hotelSuiteVanity(k: Kit) {
  k.floor('#e8e2d8'); k.wall('#efe4d3');
  const gold = k.mat('#c49a52', {metal: .7});
  for (const x of [-3, -1.6, 1.6, 3]) {k.box(.03, 2.4, .03, gold, x - .5, 1.6, -4.44); k.box(.03, 2.4, .03, gold, x + .5, 1.6, -4.44); k.box(1.03, .03, .03, gold, x, .4, -4.44); k.box(1.03, .03, .03, gold, x, 2.8, -4.44);}
  k.box(1.3, 1.8, .06, gold, 0, 1.6, -4.3);
  k.box(1.2, 1.72, .03, k.mat('#d6d8d6', {metal: .35}), 0, 1.6, -4.25);
  k.add(new T.CylinderGeometry(.65, .65, .06, 24, 1, false, 0, Math.PI), gold, 0, 2.5, -4.3).rotation.set(Math.PI / 2, 0, Math.PI / 2);
  k.box(1.4, .08, .55, k.mat('#f7f2ea'), 2.2, .82, -3.9);
  for (const dx of [-.62, .62]) k.add(new T.CylinderGeometry(.025, .02, .8, 8), gold, 2.2 + dx, .4, -3.9);
  chandelier(k, 0, 3.35, -3.8, gold);
  k.add(new T.CylinderGeometry(.12, .09, .3, 12), k.mat('#f7f2ea'), -2.8, .15, -3.6);
  k.many(new T.SphereGeometry(.07, 8, 6), k.mat('#fdf6f0'), [[-2.85, .45, -3.6], [-2.72, .52, -3.62], [-2.8, .6, -3.55]]);
}

function chandelier(k: Kit, x: number, y: number, z: number, gold: T.Material) {
  k.add(new T.TorusGeometry(.42, .02, 6, 32), gold, x, y, z).rotation.x = Math.PI / 2;
  k.add(new T.CylinderGeometry(.01, .01, .9, 6), gold, x, y + .45, z);
  const crystals: [number, number, number][] = [];
  for (let i = 0; i < 14; i++) {const a = i * Math.PI * 2 / 14; crystals.push([x + Math.cos(a) * .42, y - .12 - (i % 2) * .08, z + Math.sin(a) * .42]);}
  k.many(new T.SphereGeometry(.04, 6, 4), k.mat('#fff4d6', {glow: 1}), crystals);
}

/** A hotel ballroom: columns, drapes and chandeliers. */
function hotelBallroom(k: Kit) {
  k.floor('#e8e2d8', 11); k.wall('#4a1d27', 11, 4.6);
  k.box(1.2, .02, 2.1, k.mat('#a8854c'), 0, -.04, -4.2);
  const column = k.mat('#e9dfcf'), gold = k.mat('#c49a52', {metal: .7});
  for (const x of [-3.4, -1.15, 1.15, 3.4]) {
    k.add(new T.CylinderGeometry(.2, .22, 3.6, 16), column, x, 1.7, -4.1);
    k.box(.55, .12, .55, gold, x, 3.55, -4.1);
  }
  const drape = k.mat('#7a1f2e');
  for (const x of [-2.5, 2.5]) k.box(1.2, 3.5, .1, drape, x, 1.75, -4.4);
  for (const x of [-2.5, 0, 2.5]) chandelier(k, x, 3.6, -3.7, gold);
}

/** Backstage at fashion week: bulb mirrors in a row and garment rails. */
function backstageMirrors(k: Kit) {
  k.floor('#26262a'); k.wall('#1e1e22');
  const frame = k.mat('#0f0f10', {metal: .4});
  for (const x of [-2.6, 0, 2.6]) k.bulbMirror(x, -4.35, 1.0, 1.25, frame, '#9a9aa2', '#fff1d0');
  for (const x of [-2.6, 0, 2.6]) k.box(1.5, .06, .5, k.mat('#f2f2f2'), x, .82, -4.05);
  k.rail(-3.6, -3.7, ['#111111', '#f5f5f5', '#111111', '#c9a46a'], k.mat('#bbbbbb', {metal: .6}));
  k.rail(3.6, -3.7, ['#f5f5f5', '#111111', '#7b1e2c', '#111111'], k.mat('#bbbbbb', {metal: .6}));
}

/** Fashion week runway: light wall, front rows and photographers' flashes. */
function fashionWeekRunway(k: Kit) {
  k.floor('#111114', 11);
  k.box(1.2, .05, 2.1, k.mat('#f2f2f2', {metal: .2}), 0, -.06, -4.2);
  const panels: [number, number, number][] = [];
  for (let x = -4; x <= 4; x += .8) for (let y = .4; y < 4; y += .8) panels.push([x, y, -5]);
  k.many(new T.BoxGeometry(.7, .7, .04), k.mat('#f4ead8', {glow: .55}), panels);
  const seat = k.mat('#1c1c22'), head = k.mat('#2e2a2a');
  const bodies: [number, number, number][] = [], heads: [number, number, number][] = [];
  for (const side of [-1, 1]) for (let row = 0; row < 2; row++) for (let i = 0; i < 6; i++) {
    const x = side * (.95 + i * .48), z = -3.3 - row * .55, y = .45 + row * .25;
    bodies.push([x, y, z]); heads.push([x, y + .42, z]);
  }
  k.many(new T.BoxGeometry(.36, .7, .3), seat, bodies);
  k.many(new T.SphereGeometry(.12, 8, 6), head, heads);
  for (let group = 0; group < 3; group++) {
    const flash = new T.MeshStandardMaterial({color: '#ffffff', emissive: '#ffffff', emissiveIntensity: 0});
    k.flashes.push(flash);
    const points: [number, number, number][] = [];
    for (let i = group; i < 12; i += 3) points.push([(i % 2 ? 1 : -1) * (.95 + (i % 6) * .4), 1.25 + (i % 3) * .2, -3.25 - (i % 2) * .5]);
    k.many(new T.SphereGeometry(.06, 6, 4), flash, points);
  }
  const truss = k.mat('#3a3a40', {metal: .6});
  k.box(8.5, .1, .1, truss, 0, 3.9, -3.4);
  k.many(new T.CylinderGeometry(.08, .12, .22, 10), k.mat('#fff6e0', {glow: 1}), [-3, -1.5, 0, 1.5, 3].map(x => [x, 3.75, -3.4] as [number, number, number]));
}

/** Each stage's dressing room ("room") and event venue, keyed by the look's background. */
const SCENES: Record<string, Record<SceneMode, Spec>> = {
  studio: {room: {sky: '#eee9e2', build: bedroomVanity}, venue: {sky: '#e8ddd0', build: homePhotoWall}},
  lagos: {room: {sky: '#eadcc8', build: boutiqueFittingRoom}, venue: {sky: '#9fc6e0', build: cityStreet}},
  sunset: {room: {sky: '#1b1020', build: clubGreenRoom}, venue: {sky: '#141b33', build: rooftopNight}},
  royal: {room: {sky: '#efe6d8', build: hotelSuiteVanity}, venue: {sky: '#2b1218', build: hotelBallroom}},
  runway: {room: {sky: '#18181c', build: backstageMirrors}, venue: {sky: '#0b0b10', build: fashionWeekRunway}},
};
export const SCENE_KEYS = Object.keys(SCENES);

/**
 * Distant scenery follows the viewing side, keeping every prop behind the
 * avatar even while the player rotates to inspect an outfit. Scenes are built
 * on first use and kept; only the active one is visible.
 */
export class StudioBackdrop {
  readonly root = new T.Group();
  private scenes = new Map<string, Kit>();
  private active?: Kit;
  sky?: T.Color;
  constructor() {
    this.root.name = 'studio-backdrop';
    this.show('studio', 'room');
  }
  private show(background: string, mode: SceneMode) {
    const spec = SCENES[background]?.[mode];
    if (!spec) {this.root.visible = false; return;}
    const key = background + ':' + mode;
    let kit = this.scenes.get(key);
    if (!kit) {kit = new Kit(); spec.build(kit); kit.group.name = key; this.scenes.set(key, kit); this.root.add(kit.group);}
    if (this.active !== kit) {
      if (this.active) this.active.group.visible = false;
      kit.group.visible = true; this.active = kit; this.sky = new T.Color(spec.sky);
    }
    this.root.visible = true;
  }
  update(camera: T.Camera, background: string, mode: SceneMode = 'room', scene?: T.Scene) {
    this.show(background, mode);
    this.root.rotation.y = Math.atan2(camera.position.x, camera.position.z);
    if (scene && this.root.visible && this.sky) scene.background = this.sky;
    // Photographers' flashes fire at random while the venue is on screen.
    for (const flash of this.active?.flashes ?? []) flash.emissiveIntensity = Math.random() < .04 ? 4 : flash.emissiveIntensity * .8;
  }
  dispose() {
    this.root.traverse(o => {
      if (o instanceof T.Mesh) {o.geometry.dispose(); const materials = Array.isArray(o.material) ? o.material : [o.material]; for (const material of materials) material.dispose();}
    });
  }
}
