// Clip triangle geometry at garment boundaries, interpolating UVs/normals.
// Selecting whole body triangles leaves jagged clothing hems on low-poly bodies.
export function clipMesh(mesh, planes) {
  const position = [], normal = [], uv = [], sourceVertices = [];
  const mix = (a, b, t) => ({
    p: a.p.map((v, i) => v + (b.p[i] - v) * t),
    n: a.n.map((v, i) => v + (b.n[i] - v) * t),
    uv: a.uv.map((v, i) => v + (b.uv[i] - v) * t), source: a.source,
  });
  for (let start = 0; start < mesh.position.length / 3; start += 3) {
    let polygon = [0, 1, 2].map(j => {
      const i = start + j;
      return {p: Array.from(mesh.position.slice(i * 3, i * 3 + 3)),
        n: Array.from(mesh.normal.slice(i * 3, i * 3 + 3)),
        uv: Array.from(mesh.uv.slice(i * 2, i * 2 + 2)), source: mesh.sourceVertices[i]};
    });
    for (const plane of planes) {
      const next = [];
      for (let i = 0; i < polygon.length; i++) {
        const a = polygon[i], b = polygon[(i + 1) % polygon.length], da = plane(a.p), db = plane(b.p);
        if (da >= 0) next.push(a);
        if ((da >= 0) !== (db >= 0)) next.push(mix(a, b, da / (da - db)));
      }
      polygon = next;
    }
    for (let i = 1; i < polygon.length - 1; i++) for (const v of [polygon[0], polygon[i], polygon[i + 1]]) {
      const length = Math.hypot(...v.n) || 1;
      position.push(...v.p); normal.push(...v.n.map(n => n / length)); uv.push(...v.uv); sourceVertices.push(v.source);
    }
  }
  return {position: new Float32Array(position), normal: new Float32Array(normal), uv: new Float32Array(uv), sourceVertices};
}

export function joinMeshes(parts) {
  return Object.fromEntries(['position', 'normal', 'uv', 'sourceVertices'].map(key => {
    const data = parts.flatMap(part => Array.from(part[key]));
    return [key, key === 'sourceVertices' ? data : new Float32Array(data)];
  }));
}
