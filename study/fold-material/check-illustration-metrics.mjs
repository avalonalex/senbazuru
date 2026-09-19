// Run with node study/fold-material/check-illustration-metrics.mjs.
// No DOM or graphics dependency: these are semantic-mask counterexamples.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const source=await readFile(new URL('./illustration-metrics.js',import.meta.url),'utf8');
const {classifyMask,compareMasks,illustrationStatus,coverageArea,layerSamplings,samplingVerdict,regionDistanceStatus}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
const width=16,height=16,mask=(x,y,label=1)=>{const a=new Uint8Array(width*height);a[y*width+x]=label;return a;};
const compare=(a,b,options={})=>compareMasks(a,b,width,height,options);
const a=mask(3,3);
assert.equal(compare(a,a).maxDistancePixels,0);
assert.equal(compare(a,mask(7,3)).status,'Within sampled budget'); // exactly 2 px
assert.equal(compare(a,mask(8,3)).status,'Outside budget');
assert.equal(compare(mask(15,3),mask(0,4)).status,'Outside budget'); // no row wrap
assert.equal(compare(new Uint8Array(256),new Uint8Array(256)).status,'Not visible in either');
assert.equal(compare(a,new Uint8Array(256)).status,'Appears or disappears');
assert.equal(compare(a,mask(3,3,2)).changed,0); // same silhouette
assert.equal(compare(a,mask(3,3,2),{label:1}).missing,true); // changed visible owner
const solid=new Uint8Array(256).fill(1),hole=solid.slice();
for(let y=2;y<14;y++)for(let x=2;x<14;x++)hole[y*16+x]=0;
assert.ok(compare(solid,hole).beyondBudget>0); // internal holes, not only outer bounds
assert.deepEqual([...classifyMask(new Uint8ClampedArray([255,0,0,255,0,0,255,255,0,0,0,127]),true)],[1,2,0]);
assert.throws(()=>compareMasks(a,a,15,16));
assert.throws(()=>compare(a,a,{scale:Infinity}));
assert.throws(()=>compare(a,a,{budget:Infinity}));
const good={eligible:true,resolved:true,maxProjectedPixels:1.5},metrics=[compare(a,a)];
assert.equal(illustrationStatus(good,metrics),'Within sampled budget · inspect drawings');
assert.equal(illustrationStatus({...good,eligible:false},metrics),'Diagnostic paper');
assert.equal(illustrationStatus({...good,resolved:false},metrics),'Visibility unresolved');
assert.equal(illustrationStatus({...good,maxProjectedPixels:2.01},metrics),'Outside illustration budget');
assert.equal(illustrationStatus(good,null),'Pixel check pending');
assert.equal(illustrationStatus(good,[compare(a,new Uint8Array(256))]),'Outside illustration budget');
assert.equal(illustrationStatus(good,[{name:'Lower layer',...compare(a,new Uint8Array(256))}]),'Layer visibility needs review');
assert.equal(illustrationStatus(good,[{name:'Visible creases',...compare(a,new Uint8Array(256))}]),'Outside illustration budget');
// A real translucent strip can have area while selecting no thresholded pixels.
const faint=new Uint8ClampedArray([0,0,0,64,0,0,0,64]);
assert.deepEqual([...classifyMask(faint)],[0,0]);
assert.ok(coverageArea(faint,2)>0);
assert.equal(coverageArea(new Uint8ClampedArray([0,0,0,255]),2),0.25);
assert.throws(()=>coverageArea(faint,0));
const audits=layerSamplings.map(s=>({...s,metrics:['Lower layer','Upper layer'].map(name=>({name,...compare(a,a)}))}));
assert.equal(samplingVerdict(good,audits),'Layers within budget on all sampled grids');
const failed={...audits[0],metrics:[{name:'Lower layer',...compare(a,mask(8,3))},audits[0].metrics[1]]};
assert.equal(samplingVerdict(good,[failed,...audits.slice(1)]),'Layer comparison depends on sampling');
assert.equal(samplingVerdict(good,audits.map(s=>({...s,metrics:failed.metrics}))),'Layer difference on every sampled grid');
assert.equal(samplingVerdict(good,audits.slice(1)),'Sampling audit incomplete');
assert.equal(samplingVerdict(good,[audits[1],...audits.slice(1)]),'Sampling audit incomplete');
assert.equal(samplingVerdict({...good,eligible:false},audits),'Diagnostic paper');
assert.equal(samplingVerdict({...good,resolved:false},audits),'Visibility unresolved');
assert.equal(samplingVerdict(good,audits.map(s=>({...s,metrics:[]}))),'Sampling audit incomplete');
assert.equal(illustrationStatus(good,metrics,2,[failed,...audits.slice(1)]),'Layer visibility needs review');
assert.equal(illustrationStatus(good,metrics,2,audits.slice(1)),'Sampling audit incomplete');
assert.equal(illustrationStatus(good,metrics,2,audits),'Within sampled budget · inspect drawings');
const bound=(lo,hi)=>({state:'bounded',lowerPixels:lo,upperPixels:hi});
const geometric={owner:0,forward:bound(0.1,0.2),backward:bound(0.3,0.4)};
assert.equal(regionDistanceStatus(geometric),'Within geometric budget');
assert.equal(regionDistanceStatus({...geometric,forward:bound(1.99,2.01)}),'Geometric budget unresolved');
assert.equal(regionDistanceStatus({...geometric,forward:bound(2.01,2.02)}),'Outside geometric budget');
assert.equal(regionDistanceStatus({...geometric,forward:bound(3,2)}),'Geometric check incomplete');
assert.equal(regionDistanceStatus({forward:{state:'empty-source'},backward:{state:'missing-target'}}),'Layer appears or disappears');
assert.equal(regionDistanceStatus({forward:{state:'empty-source'},backward:{state:'empty-source'}}),'No exposure in either');
const geometricPair={...good,regionDistances:[geometric,{...geometric,owner:1,forward:bound(2.01,2.02)}]};
assert.equal(illustrationStatus(geometricPair,metrics),'Layer visibility needs review');
assert.equal(illustrationStatus({...good,regionDistances:[geometric]},metrics),'Geometric check incomplete');
assert.equal(illustrationStatus({...geometricPair,eligible:false},metrics),'Diagnostic paper');
// Area describes the failure; even microscopic exposure cannot waive it.
const tinyArea={totalPixelsSquared:0.00001,outsideLowerPixelsSquared:0.000001,outsideUpperPixelsSquared:0.000001,unresolvedPixelsSquared:0,accuracyMet:true};
const tinyPair={...geometricPair,regionDistances:geometricPair.regionDistances.map(layer=>({...layer,forwardArea:tinyArea,backwardArea:tinyArea}))};
assert.equal(illustrationStatus(tinyPair,metrics),'Layer visibility needs review');
assert.equal(illustrationStatus({...tinyPair,eligible:false},metrics),'Diagnostic paper');
const zeroPair={...good,regionDistances:[0,1].map(owner=>({...geometric,owner,forwardArea:{...tinyArea,outsideLowerPixelsSquared:0,outsideUpperPixelsSquared:0},backwardArea:{...tinyArea,outsideLowerPixelsSquared:0,outsideUpperPixelsSquared:0}}))};
assert.equal(illustrationStatus(zeroPair,[{name:'Lower layer',...compare(a,mask(8,3))}]),'Layer visibility needs review');
console.log('All illustration-mask counterexamples pass.');
