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
// A solved pose that screens as paper up to its finer level, which it was
// not made again to measure: 0.12% stretch and 0.2% squash, within the 1%
// screen but not 0.1%, and a floor of half a pixel that the 1% screen
// forgives.
const screen=(verdict,more={})=>({squash:0.002,stretch:0.0012,floor3dPixels:0.5,floor3dPixelsAtScreen:0,floorPairs:null,crossingPairCount:0,deepestReachPixels:null,falseCreaseJoins:0,falseCreaseTurningSheetDegrees:0,falseCreaseJoinsFiner:null,falseCreaseTurningFinerSheetDegrees:null,coreLengthSheets:null,centreMidlineFoldDegrees:null,centreDiagonalFoldDegrees:null,verdict:{strain:true,strictStrain:false,floor:true,falseCreases:null,passes:null,...verdict},...more});
const headline=verdict=>paperScreen.headline(screen(verdict));
assert.equal(headline({falseCreases:true,passes:true}),'Passes');
assert.equal(headline({}),'Not measured: false creases one level finer');
// A failure outranks a part not measured, and the part not measured is not
// listed among the failures.
assert.equal(headline({strain:false,passes:false}),'Fails: strain');
assert.equal(headline({floor:false,falseCreases:false,passes:false}),'Fails: floor, false creases');
assert.equal(headline({passes:undefined}),'—'); // a verdict with no answer reads as neither
// A placed pose that fails everywhere: 20% stretch, a floor of 11.2 px at
// the screen, and 150 joins bent past 45 degrees, of which 40 still bend
// past it on the pose made again one level finer. Its sheet is not convex,
// and it is drawn in no picture.
const placed=screen({strain:false,floor:false,falseCreases:false,passes:false},{stretch:0.2,floor3dPixels:12.3456,floor3dPixelsAtScreen:11.2,floorPairs:[3,10],crossingPairCount:4,deepestReachPixels:0,falseCreaseJoins:150,falseCreaseTurningSheetDegrees:1234.5,falseCreaseJoinsFiner:40,falseCreaseTurningFinerSheetDegrees:212.3});
const rows=paperScreen.rows([{title:'Solved',screen:screen({}),picture:{pictureFloorPixels:4.84e-7,pictureFloorPixelsAtScreen:0}},{title:'Placed',screen:placed}],limits);
assert.deepEqual(rows.map(r=>r.length),[3,3,3,3,3,3,3,3]); // no body core rows: neither pose is a crane's body
assert.deepEqual(rows[0],['Paper screen','Solved','Placed']);
assert.deepEqual(rows[1].slice(1),['Not measured: false creases one level finer','Fails: strain, floor, false creases']);
assert.deepEqual(rows[2],['Largest stretch / squash · within 0.1%','0.120% / 0.200% · no','20.0% / 0.200% · no']);
// A pose drawn in no picture has no picture floor, and a floor over some of
// the pairs says how many. Three figures and no exponent: toPrecision
// would write 4.84e-7 and 1.23e+3.
assert.deepEqual(rows[3].slice(1),['0.500 px · 0.000000484 px','12.3 px · — (over 3 of 10 pairs: the sheet is not convex)']);
assert.deepEqual(rows[4],['Floor at 1% strain, 3D · this picture','0 px · 0 px','11.2 px · —']);
assert.deepEqual(rows[5].slice(1),['0','4 · 0 px']);
assert.deepEqual(rows[6],['False creases: joins past 45° · turning, sheet units × degrees','0 · 0','150 · 1230']);
assert.deepEqual(rows[7].slice(1),['— (not made again)','40 · 212']);
// Three figures also for a value that rounds up across a power of ten,
// for one that is a power of ten, and for a single digit. Zero is a
// measurement, and a pair that crosses by no depth at all is shown so.
const rounding=paperScreen.rows([{title:'Rounding',screen:screen({strain:false,floor:false,falseCreases:true,passes:false},{stretch:0.03,floor3dPixels:9.996,floor3dPixelsAtScreen:7.5,crossingPairCount:2,deepestReachPixels:1,falseCreaseJoinsFiner:0,falseCreaseTurningFinerSheetDegrees:0})}],limits);
assert.deepEqual(rounding.slice(3,6).map(r=>r[1]),['10.0 px · —','7.50 px · —','2 · 1.00 px']);
assert.equal(rounding[7][1],'0 · 0');
// A value a gallery did not write shows as NaN in its cell, rather than
// stopping the page's script before the rest of its tables.
assert.equal(paperScreen.number(undefined),'NaN');
// A crane's body adds its core's two rows, with a dash where a pose has no
// reading.
const body=paperScreen.rows([{title:'Crane',screen:screen({},{coreLengthSheets:Math.SQRT2-1,centreMidlineFoldDegrees:14,centreDiagonalFoldDegrees:null})},{title:'Wing',screen:screen({})}],limits);
assert.deepEqual(body.slice(8),[['Body core length, sheet units','0.414','—'],['Centre folds: midlines / diagonals','14.0° / —','— / —']]);
// A gallery's runs become poses titled by the page, each with its own
// picture floors and finer solve, which the gallery writes on the run beside
// its screen.
const runs=[{id:'a',title:'A',screen:screen({}),pictureFloorPixels:0.25,finerSolve:{id:'a2',label:'solved at 16 divisions',apartPixels:0.5}},{id:'b',title:'B',screen:placed}];
const poses=paperScreen.poses(runs,run=>run.title+'!');
assert.deepEqual(poses.map(p=>[p.title,p.screen,p.picture,p.finer]),[['A!',runs[0].screen,runs[0],runs[0].finerSolve],['B!',placed,runs[1],undefined]]);
assert.deepEqual(paperScreen.rows(poses,limits)[3].slice(1),['0.500 px · 0.250 px','12.3 px · — (over 3 of 10 pairs: the sheet is not convex)']);
// A solved pose whose finer level is its gallery's own finer solve says
// which solve, and how far apart the two are at worst (owner decision 29);
// a pose made again, as the placed one above, names none. One whose finer
// solve was refused keeps its finer level not measured.
const counted=screen({falseCreases:true,passes:true},{falseCreaseJoinsFiner:0,falseCreaseTurningFinerSheetDegrees:0});
const refused={title:'Strip',screen:screen({}),finerSolve:{id:'strip-16',label:'solved at 16 spans',refused:'the finer mesh has 32 triangles, not 64'}};
const finer=paperScreen.rows(paperScreen.poses([{title:'Wing',screen:counted,finerSolve:{id:'wing-16-40',label:'solved at 16 divisions',apartPixels:0.8068}},refused],run=>run.title),limits);
assert.deepEqual(finer[1].slice(1),['Passes','Not measured: false creases one level finer']);
assert.deepEqual(finer[7].slice(1),['0 · 0 (solved at 16 divisions, 0.807 px apart)','— (not made again)']);
// The labels and the caption take the thresholds they are given.
const other={pixelsPerSheet:500,strainScreen:0.02,strictStrainScreen:0.002,floorLimitPixels:2,falseCreaseThresholdDegrees:30};
const labels=paperScreen.rows([],other).map(r=>r[0]);
assert.deepEqual([labels[2],labels[4],labels[6]],['Largest stretch / squash · within 0.2%','Floor at 2% strain, 3D · this picture','False creases: joins past 30° · turning, sheet units × degrees']);
const caption=paperScreen.caption(other);
for(const words of ['in pixels, 500 to a sheet unit','no more than 2% strain','at most 2 px at that strain','no join bent past 30°','within 0.2% is reported','agree within 2 px at every vertex of the coarser mesh','(owner decision 29)'])assert.ok(caption.includes(words),words);
console.log('paper-screen.js: every check passed');
