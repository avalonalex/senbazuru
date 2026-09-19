// Pixel centres at a fixed supersampling scale. This deliberately compares
// shape/semantic masks, not SVG strings or antialiased display colours.
// Distances are between sampled centres; features below one sample can vanish.
export function classifyMask(rgba, layers = false) {
  const labels = new Uint8Array(rgba.length / 4);
  for (let i = 0; i < labels.length; i++) {
    const p = 4 * i;
    if (rgba[p + 3] >= 128) labels[i] = layers && rgba[p + 2] > rgba[p] ? 2 : 1;
  }
  return labels;
}

export function compareMasks(a, b, width, height, { scale = 2, budget = 2, label = null } = {}) {
  if (!Number.isInteger(width) || !Number.isInteger(height) || width < 1 || height < 1 || a.length !== width * height || b.length !== a.length || !Number.isFinite(scale) || !Number.isFinite(budget) || !(scale > 0) || !(budget >= 0)) {
    throw new Error('Mask dimensions, scale and budget must be valid and equal.');
  }
  const offsets = [], radius = Math.floor(budget * scale);
  for (let dy = -radius; dy <= radius; dy++) {
    for (let dx = -radius; dx <= radius; dx++) {
      const distance = Math.hypot(dx, dy) / scale;
      if (distance <= budget) offsets.push({ dx, dy, distance });
    }
  }
  offsets.sort((x, y) => x.distance - y.distance);
  const selected = value => label === null ? value !== 0 : value === label;
  const count = xs => xs.reduce((n, value) => n + Number(selected(value)), 0);
  const counts = [count(a), count(b)];
  const outliers = [];
  let maxWithinBudget = 0, beyondBudget = 0, changed = 0;
  for (const [source, target] of [[a, b], [b, a]]) {
    for (let i = 0; i < source.length; i++) {
      if (!selected(source[i]) || selected(target[i])) continue;
      changed++;
      const x = i % width, y = Math.floor(i / width);
      const nearest = offsets.find(({ dx, dy }) => {
        const xx = x + dx, yy = y + dy;
        return xx >= 0 && xx < width && yy >= 0 && yy < height && selected(target[yy * width + xx]);
      });
      if (nearest) maxWithinBudget = Math.max(maxWithinBudget, nearest.distance);
      else {
        beyondBudget++;
        if (outliers.length < 200) outliers.push([x, y]);
      }
    }
  }
  const missing = (counts[0] === 0) !== (counts[1] === 0);
  return {
    counts, changed, beyondBudget, missing, outliers,
    maxDistancePixels: beyondBudget ? null : maxWithinBudget,
    status: counts.every(n => n === 0) ? 'Not visible in either' : missing ? 'Appears or disappears' : beyondBudget ? 'Outside budget' : 'Within sampled budget'
  };
}

// Passing pixels never rehabilitates invalid paper or unresolved visibility.
export function illustrationStatus(pair, metrics, budget = 2, reports = null) {
  if (!pair.eligible) return 'Diagnostic paper';
  if (!pair.resolved) return 'Visibility unresolved';
  if (!metrics) return 'Pixel check pending';
  const failed = metrics.filter(m => m.beyondBudget || m.missing);
  if (pair.maxProjectedPixels > budget || failed.some(m => !['Lower layer','Upper layer'].includes(m.name))) return 'Outside illustration budget';
  if (failed.length) return 'Layer visibility needs review';
  if (pair.regionDistances) {
    if (pair.regionDistances.length !== 2 || [0,1].some(owner => pair.regionDistances.filter(d => d.owner === owner).length !== 1)) return 'Geometric check incomplete';
    const geometry = pair.regionDistances.map(d => regionDistanceStatus(d, budget));
    if (geometry.some(s => ['Outside geometric budget','Layer appears or disappears'].includes(s))) return 'Layer visibility needs review';
    if (geometry.some(s => !['Within geometric budget','No exposure in either'].includes(s))) return 'Geometric check unresolved';
  }
  if (reports !== null) {
    const verdict = samplingVerdict(pair, reports);
    if (verdict === 'Sampling audit incomplete') return verdict;
    if (verdict !== 'Layers within budget on all sampled grids') return 'Layer visibility needs review';
  }
  return 'Within sampled budget · inspect drawings';
}

// Integrate opacity before thresholding. Isolated black masks avoid losing a
// minority layer when the next coloured layer paints an antialiased edge.
export function coverageArea(rgba, scale) {
  if (!(scale > 0) || !Number.isFinite(scale) || rgba.length % 4) throw new Error('Invalid coverage samples.');
  let alpha = 0;
  for (let i = 3; i < rgba.length; i += 4) alpha += rgba[i];
  return alpha / (255 * scale * scale);
}

// Phase is measured in raster samples, not page pixels: a half-sample shift
// stays a genuinely different sampling grid at every density.
export const layerSamplings = [2,4,8].flatMap(scale =>
  [[0,0],[0.5,0],[0,0.5],[0.5,0.5]].map(phase => ({key:`${scale}/${phase.join('/')}`,scale,phase})));

export function samplingVerdict(pair, reports) {
  if (!pair.eligible) return 'Diagnostic paper';
  if (!pair.resolved) return 'Visibility unresolved';
  if (reports.length !== layerSamplings.length || layerSamplings.some(s => reports.filter(r => r.key === s.key).length !== 1) || reports.some(r => r.metrics.length !== 2 || ['Lower layer','Upper layer'].some(name => r.metrics.filter(m => m.name === name).length !== 1))) return 'Sampling audit incomplete';
  const failures = reports.filter(r => r.metrics.some(m => m.beyondBudget || m.missing)).length;
  if (!failures) return 'Layers within budget on all sampled grids';
  return failures === reports.length ? 'Layer difference on every sampled grid' : 'Layer comparison depends on sampling';
}

// The two directions cover filled regions, not just their outlines. A finite
// interval straddling the budget is unresolved, even if its midpoint passes.
export function regionDistanceStatus(layer, budget = 2) {
  const directions = [layer.forward,layer.backward];
  if (directions.some(d => !d)) return 'Geometric check incomplete';
  if (directions.some(d => d.state === 'missing-target')) return 'Layer appears or disappears';
  if (directions.every(d => d.state === 'empty-source')) return 'No exposure in either';
  if (!directions.every(d => d.state === 'bounded' && Number.isFinite(d.lowerPixels) && Number.isFinite(d.upperPixels) && d.lowerPixels >= 0 && d.lowerPixels <= d.upperPixels)) return 'Geometric check incomplete';
  if (directions.some(d => d.lowerPixels > budget)) return 'Outside geometric budget';
  if (directions.every(d => d.upperPixels <= budget)) return 'Within geometric budget';
  return 'Geometric budget unresolved';
}
