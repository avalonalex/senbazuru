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
assert.throws(()=>primitiveNormals([[[12,.5],[10,.5]],...weights.slice(1)],[0],[1,2,0],lighting,false),/does not match/);
const crease = {vertices:[[10,11,12],[10,11,12]],normals:[lighting.normals[0],[[0,0,1],[0,0,1],[0,0,1]]]};
assert.throws(()=>primitiveNormals(weights,[0,1],[1,2,0,1,2,0],crease,false),/sharp lighting boundary/);
console.log('Paper lighting preserves material identity, primitive winding and sharp boundaries.');
