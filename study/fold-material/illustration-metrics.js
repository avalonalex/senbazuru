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
export function illustrationStatus(pair, metrics, budget = 2) {
  if (!pair.eligible) return 'Diagnostic paper';
  if (!pair.resolved) return 'Visibility unresolved';
  if (!metrics) return 'Pixel check pending';
  const failed = metrics.filter(m => m.beyondBudget || m.missing);
  if (pair.maxProjectedPixels > budget || failed.some(m => !['Lower layer','Upper layer'].includes(m.name))) return 'Outside illustration budget';
  if (failed.length) return 'Layer visibility needs review';
  return 'Within sampled budget · inspect drawings';
}
