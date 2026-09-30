// Run with node study/fold-material/check-paper-screen.mjs.
// How a page reads a screen: the headline is the verdict's own, and a part
// not measured, null, is neither a pass nor a fail.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
const source=await readFile(new URL('./paper-screen.js',import.meta.url),'utf8');
// A plain script's `const` is no property of the global object, so ask for
// it by name. It runs in this realm, so its arrays compare equal to ours.
const paperScreen=vm.runInThisContext(source+'\npaperScreen');
const limits={pixelsPerSheet:600,strainScreen:0.01,strictStrainScreen:0.001,floorLimitPixels:1,falseCreaseThresholdDegrees:45};
const screen=(verdict,more={})=>({squash:0.002,stretch:0,floor3dPixels:0,floor3dPixelsAtScreen:0,floorPairs:null,crossingPairCount:0,deepestReachPixels:null,falseCreaseJoins:0,falseCreaseTurningSheetDegrees:0,falseCreaseJoinsFiner:null,falseCreaseTurningFinerSheetDegrees:null,verdict:{strain:true,strictStrain:false,floor:true,falseCreases:null,passes:null,...verdict},...more});
const headline=verdict=>paperScreen.headline(screen(verdict));
assert.equal(headline({falseCreases:true,passes:true}),'Passes');
assert.equal(headline({}),'Not measured: false creases one level finer');
// A failure outranks a part not measured, and the part not measured is not
// listed among the failures.
assert.equal(headline({strain:false,passes:false}),'Fails: strain');
assert.equal(headline({floor:false,falseCreases:false,passes:false}),'Fails: floor, false creases');
assert.equal(paperScreen.headline({}),'—'); // no verdict reads as neither
const rows=paperScreen.rows([
  {title:'Solved',screen:screen({}),picture:{pictureFloorPixels:0.25,pictureFloorPixelsAtScreen:null}},
  {title:'Placed',screen:screen({strain:false,passes:false},{stretch:0.2,floor3dPixels:12.3456,floorPairs:[3,10],crossingPairCount:4,deepestReachPixels:0,falseCreaseJoins:2,falseCreaseTurningSheetDegrees:7.5,falseCreaseJoinsFiner:0,falseCreaseTurningFinerSheetDegrees:0})}
],limits);
assert.deepEqual(rows.map(r=>r.length),[3,3,3,3,3,3,3,3]);
assert.deepEqual(rows[0],['Paper screen','Solved','Placed']);
assert.deepEqual(rows[1].slice(1),['Not measured: false creases one level finer','Fails: strain']);
assert.deepEqual(rows[2],['Largest stretch / squash · within 0.1%','0% / 0.200% · no','20.0% / 0.200% · no']);
// A pose drawn in no picture has no picture floor, and a floor over some of
// the pairs says how many.
assert.deepEqual(rows[3].slice(1),['0 px · 0.250 px','12.3 px · — (over 3 of 10 pairs: the sheet is not convex)']);
assert.deepEqual(rows[4],['Floor at 1% strain, 3D · this picture','0 px · —','0 px · —']);
assert.deepEqual(rows[5].slice(1),['0','4 · 0 px']);
assert.deepEqual(rows[6],['False creases: joins past 45° · turning, sheet sides × degrees','0 · 0','2 · 7.50']);
// Zero is a measurement: no join past the threshold one level finer, and a
// pair that crosses by no depth at all.
assert.deepEqual(rows[7].slice(1),['— (not made again)','0 · 0']);
// The labels and the caption take the thresholds they are given.
const other={pixelsPerSheet:500,strainScreen:0.02,strictStrainScreen:0.002,floorLimitPixels:2,falseCreaseThresholdDegrees:30};
const labels=paperScreen.rows([],other).map(r=>r[0]);
assert.deepEqual([labels[2],labels[4],labels[6]],['Largest stretch / squash · within 0.2%','Floor at 2% strain, 3D · this picture','False creases: joins past 30° · turning, sheet sides × degrees']);
const caption=paperScreen.caption(other);
for(const words of ['at 500 px to the sheet\'s side','no more than 2% strain','at most 2 px at that strain','no join bent past 30°','within 0.2% is reported'])assert.ok(caption.includes(words),words);
console.log('paper-screen.js: every check passed');
