import assert from 'node:assert/strict';
import { primitiveNormals } from './paper-lighting.mjs';

// Graphics slots deliberately differ from material ids and triangle order.
const weights = [[[12,1]],[[10,1]],[[11,1]]];
const lighting = {vertices:[[10,11,12]],normals:[[[1,0,0],[0,1,0],[0,0,1]]]};
const front = primitiveNormals(weights,[0],[1,2,0],lighting,false);
assert.deepEqual([...front],[0,0,1,1,0,0,0,1,0]);
const back = primitiveNormals(weights,[0],[1,0,2],lighting,true);
assert.deepEqual([...back],[...front].map(n=>-n));
assert.deepEqual(weights,[[[12,1]],[[10,1]],[[11,1]]]);
assert.throws(()=>primitiveNormals([[[99,1]],...weights.slice(1)],[0],[1,2,0],lighting,false),/corner direction/);
assert.throws(()=>primitiveNormals(weights,[0],[1,2],lighting,false),/triangular/);
assert.throws(()=>primitiveNormals(weights,[9],[1,2,0],lighting,false),/does not match/);
// A corner the visible scene clipped half-way between corners 12 and 10
// blends their directions; references outside its own triangle, weights that
// do not sum to one and negative weights are refused.
const clipped = primitiveNormals([[[12,.5],[10,.5]],...weights.slice(1)],[0],[1,2,0],lighting,false);
assert.deepEqual([...clipped.slice(0,3)],[Math.SQRT1_2,0,Math.SQRT1_2].map(Math.fround));
assert.deepEqual([...clipped.slice(3)],[...front.slice(3)]);
assert.throws(()=>primitiveNormals([[[99,.5],[10,.5]],...weights.slice(1)],[0],[1,2,0],lighting,false),/corner direction/);
assert.throws(()=>primitiveNormals([[[12,.5],[10,.4]],...weights.slice(1)],[0],[1,2,0],lighting,false),/sum to one/);
assert.throws(()=>primitiveNormals([[[12,1.5],[10,-.5]],...weights.slice(1)],[0],[1,2,0],lighting,false),/does not match/);
// A weight a hair below zero, as the exporter may write for a corner cut a
// hair outside its triangle, still blends; directions that cancel do not.
const hair = primitiveNormals([[[12,.5+3e-9],[10,.5],[11,-3e-9]],...weights.slice(1)],[0],[1,2,0],lighting,false);
assert.ok([...hair.slice(0,3)].every((n,axis)=>Math.abs(n-[Math.SQRT1_2,0,Math.SQRT1_2][axis])<1e-6));
const opposite = {vertices:[[10,11,12]],normals:[[[1,0,0],[0,1,0],[-1,0,0]]]};
assert.throws(()=>primitiveNormals([[[12,.5],[10,.5]],...weights.slice(1)],[0],[1,2,0],opposite,false),/to nothing/);
const crease = {vertices:[[10,11,12],[10,11,12]],normals:[lighting.normals[0],[[0,0,1],[0,0,1],[0,0,1]]]};
assert.throws(()=>primitiveNormals(weights,[0,1],[1,2,0,1,2,0],crease,false),/sharp lighting boundary/);
console.log('Paper lighting preserves material identity, primitive winding, clipped corners and sharp boundaries.');
