// MakeHuman clothing authors specify the hm08 body vertices hidden by fabric.
// Transfer those masks through the low-poly proxy's barycentric references.
// This preserves designed necklines/open backs instead of hiding whole limbs.
export function deletedVertices(text) {
  const section = text.split(/^delete_verts\s*$/m)[1];
  if (!section) return new Set();
  const result = new Set();
  for (const line of section.split(/\r?\n/)) {
    if (/^\s*#/.test(line) || !line.trim()) continue;
    if (!/^[\d\s-]+$/.test(line)) break;
    const tokens = line.trim().split(/\s+/);
    for (let i = 0; i < tokens.length; i++) {
      const start = Number(tokens[i]);
      const end = tokens[i + 1] === '-' ? Number(tokens[i += 2]) : start;
      for (let vertex = start; vertex <= end; vertex++) result.add(vertex);
    }
  }
  return result;
}

export function proxyCoverage(proxy, deleted) {
  const section = proxy.split(/^verts\s+0\s*$/m)[1];
  if (!section) throw Error('Missing MakeHuman proxy vertex references');
  const weights = [];
  for (const line of section.split(/\r?\n/)) {
    if (!line.trim() || /^\s*#/.test(line)) continue;
    const values = line.trim().split(/\s+/).map(Number);
    if (values.some(Number.isNaN)) break;
    weights.push(values.length === 1 ? Number(deleted.has(values[0]))
      : values.slice(0, 3).reduce((sum, vertex, i) => sum + (deleted.has(vertex) ? values[i + 3] : 0), 0));
  }
  return weights;
}

export function coveredTriangles(sourceVertices, weights) {
  const triangles = [];
  for (let offset = 0; offset < sourceVertices.length; offset += 3) {
    // Retain boundary faces unless every corner belongs under this garment.
    // The mesh is low-poly: removing a partially exposed face makes a hole.
    if (sourceVertices.slice(offset, offset + 3).every(vertex => weights[vertex] >= .5)) triangles.push(offset / 3);
  }
  return triangles;
}
