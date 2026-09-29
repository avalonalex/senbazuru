// Attach Haskell's corner normals using the GLB's material references. A
// graphics index is not a material id, and front/back primitives can visit
// the same graphics corners in different orders. No positions are changed.
//
// The visible scene clips triangles where other paper covers them, so one of
// its corners can lie part-way along a triangle. Its references are then that
// triangle's own corners, with weights summing to one, and its direction is
// the same blend of theirs. An unclipped corner is the case of one weight 1
// and keeps its corner's direction exactly.
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
        !Array.isArray(refs) || refs.length < 1 ||
        !refs.every(ref => Array.isArray(ref) && ref.length === 2 && Number.isInteger(ref[0]) &&
          Number.isFinite(ref[1]) && ref[1] >= 0) ||
        !Array.isArray(vertices) || vertices.length !== 3 || !Array.isArray(normals) || normals.length !== 3)
      throw new Error('Paper lighting does not match the GLB.');
    if (Math.abs(refs.reduce((sum, ref) => sum + ref[1], 0) - 1) > 1e-6)
      throw new Error('Paper lighting needs corner weights that sum to one.');
    const directions = refs.map(([vertex]) => normals[vertices.indexOf(vertex)]);
    if (!directions.every(normal => Array.isArray(normal) && normal.length === 3 && normal.every(Number.isFinite) &&
        Math.abs(Math.hypot(...normal) - 1) <= 1e-6))
      throw new Error('Paper lighting has a missing or invalid corner direction.');
    let direction = directions[0];
    if (refs.length > 1) {
      const blend = [0, 1, 2].map(axis => refs.reduce((sum, ref, k) => sum + ref[1] * directions[k][axis], 0));
      const length = Math.hypot(...blend);
      // Opposite directions cannot meet inside one triangle's smooth panel.
      if (!(length > 1e-6)) throw new Error('Paper lighting blends corner directions to nothing.');
      direction = blend.map(value => value / length);
    }
    for (let axis = 0; axis < 3; axis++) {
      const value = Math.fround(sign * direction[axis]);
      if (assigned.has(graphics) && result[3 * graphics + axis] !== value)
        throw new Error('A graphics corner crosses a sharp lighting boundary.');
      result[3 * graphics + axis] = value;
    }
    assigned.add(graphics);
  }
  return result;
}
