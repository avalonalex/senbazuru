// Attach Haskell's corner normals using the GLB's material references. A
// graphics index is not a material id, and front/back primitives can visit
// the same graphics corners in different orders. No positions are changed.
export function primitiveNormals(weights, faces, indices, lighting, underside) {
  if (!Array.isArray(weights) || !Array.isArray(faces) || indices.length !== faces.length * 3)
    throw new Error('Paper lighting needs complete triangular material references.');
  const result = new Float32Array(weights.length * 3);
  const assigned = new Set();
  const sign = underside ? -1 : 1;
  for (let i = 0; i < indices.length; i++) {
    const graphics = indices[i];
    const face = faces[Math.floor(i / 3)];
    const refs = weights[graphics];
    const vertices = lighting.vertices?.[face];
    const normals = lighting.normals?.[face];
    if (!Number.isInteger(graphics) || graphics < 0 || !Number.isInteger(face) || face < 0 ||
        !Array.isArray(refs) || refs.length !== 1 || !Array.isArray(refs[0]) ||
        refs[0].length !== 2 || !Number.isInteger(refs[0][0]) || refs[0][1] !== 1 ||
        !Array.isArray(vertices) || vertices.length !== 3 || !Array.isArray(normals) || normals.length !== 3)
      throw new Error('Paper lighting does not match the complete-sheet GLB.');
    const corner = vertices.indexOf(refs[0][0]);
    const normal = normals[corner];
    if (!Array.isArray(normal) || normal.length !== 3 || !normal.every(Number.isFinite) ||
        Math.abs(Math.hypot(...normal) - 1) > 1e-6)
      throw new Error('Paper lighting has a missing or invalid corner direction.');
    for (let axis = 0; axis < 3; axis++) {
      const value = Math.fround(sign * normal[axis]);
      if (assigned.has(graphics) && result[3 * graphics + axis] !== value)
        throw new Error('A graphics corner crosses a sharp lighting boundary.');
      result[3 * graphics + axis] = value;
    }
    assigned.add(graphics);
  }
  return result;
}
