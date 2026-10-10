import {BufferGeometry, Float32BufferAttribute, Mesh, MeshBasicMaterial, DoubleSide, Raycaster, Vector3} from 'three';

/** Fit downloaded bottoms to the male abdomen before assigning rig weights.
 * Preserve hems, pockets and leg silhouettes; lift only the upper hip band. */
export function fitMaleBottom(mesh, body) {
  const top = Math.max(...Array.from(mesh.position).filter((_, i) => i % 3 === 1));
  const lift = Math.max(0, 1.16 - top);
  // Long source triangles otherwise bridge across the curved hips and cut
  // through the body despite their corner vertices fitting correctly.
  const refined = {position: [], normal: [], uv: [], sourceVertices: []};
  const middle = (a, b) => ({p: a.p.map((v, i) => (v + b.p[i]) / 2),
    n: a.n.map((v, i) => (v + b.n[i]) / 2), uv: a.uv.map((v, i) => (v + b.uv[i]) / 2), source: a.source});
  const emit = (a, b, c, depth) => {
    const points = [a, b, c];
    const long = points.some((v, i) => Math.hypot(...v.p.map((x, j) => x - points[(i + 1) % 3].p[j])) > .04);
    if (depth < 5 && long && Math.max(...points.map(v => v.p[1])) > .86 && Math.min(...points.map(v => v.p[1])) < 1.25) {
      const ab = middle(a, b), bc = middle(b, c), ca = middle(c, a);
      emit(a, ab, ca, depth + 1); emit(ab, b, bc, depth + 1);
      emit(ca, bc, c, depth + 1); emit(ab, bc, ca, depth + 1); return;
    }
    for (const v of points) {refined.position.push(...v.p); refined.normal.push(...v.n); refined.uv.push(...v.uv); refined.sourceVertices.push(v.source);}
  };
  for (let i = 0; i < mesh.position.length / 3; i += 3) emit(...[0, 1, 2].map(j => ({
    p: Array.from(mesh.position.slice((i + j) * 3, (i + j + 1) * 3)),
    n: Array.from(mesh.normal.slice((i + j) * 3, (i + j + 1) * 3)),
    uv: Array.from(mesh.uv.slice((i + j) * 2, (i + j + 1) * 2)), source: mesh.sourceVertices[i + j],
  })), 0);
  mesh = {...refined, position: new Float32Array(refined.position), normal: new Float32Array(refined.normal), uv: new Float32Array(refined.uv)};
  const geometry = new BufferGeometry();
  const trunk = [];
  for (let i = 0; i < body.position.length; i += 9) {
    const p = Array.from(body.position.slice(i, i + 9));
    if ([0, 3, 6].every(j => Math.abs(p[j]) < .34 && p[j + 1] > .78 && p[j + 1] < 1.38)) trunk.push(...p);
  }
  geometry.setAttribute('position', new Float32BufferAttribute(trunk, 3));
  const material = new MeshBasicMaterial({side: DoubleSide});
  const surface = new Mesh(geometry, material); surface.updateMatrixWorld(true);
  const ray = new Raycaster(), centre = new Vector3(), direction = new Vector3();
  for (let i = 0; i < mesh.position.length; i += 3) {
    let y = mesh.position[i + 1];
    const t = Math.max(0, Math.min(1, (y - .86) / (top - .86)));
    y += lift * t * t * (3 - 2 * t);
    mesh.position[i + 1] = y;
    if (y < .88) continue;
    const x = mesh.position[i], z = mesh.position[i + 2] - .025;
    const radius = Math.hypot(x, z); if (radius < .001) continue;
    centre.set(0, y, .025); direction.set(x / radius, 0, z / radius);
    ray.set(centre, direction);
    const hit = ray.intersectObject(surface, false)[0];
    if (!hit) continue;
    const fitted = Math.max(radius, hit.distance + .030);
    mesh.position[i] = direction.x * fitted;
    mesh.position[i + 2] = .025 + direction.z * fitted;
  }
  // Smooth shared positions across UV seams after the fit changes the surface.
  const normals = new Map();
  const key = i => [0, 1, 2].map(j => mesh.position[i + j].toFixed(6)).join(',');
  for (let i = 0; i < mesh.position.length; i += 9) {
    const a = new Vector3().fromArray(mesh.position, i), b = new Vector3().fromArray(mesh.position, i + 3), c = new Vector3().fromArray(mesh.position, i + 6);
    const n = b.sub(a).cross(c.sub(a));
    for (const j of [i, i + 3, i + 6]) {const k = key(j); if (!normals.has(k)) normals.set(k, new Vector3()); normals.get(k).add(n);}
  }
  for (let i = 0; i < mesh.position.length; i += 3) normals.get(key(i)).normalize().toArray(mesh.normal, i);
  geometry.dispose(); material.dispose();
  return mesh;
}
