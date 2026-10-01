// The paper screen as a gallery page shows it (PRD 11, R-11-1). Every page
// with a screen loads this one copy, so a verdict reads the same on each.
// It is a plain script rather than a module, so a page opened from disk
// still shows its screen, and it declares one name, `paperScreen`, since a
// page's own script may already use `percent` or `number`. Checked by
// `node study/fold-material/check-paper-screen.mjs`.
const paperScreen = (() => {
  // Three significant figures with no exponent, from a hundred-millionth
  // to about 1e21, far past any screen value: toPrecision writes 4.84e-7
  // below a millionth and 1.23e+3 from a thousand, beside cells that read
  // 0.00000119 and 145. Round first, so that 9.996 becomes 10.0 and not
  // 10.00.
  const number = n => {
    const value = Number(n);
    if (Math.abs(value) < 1e-8) return '0';
    const rounded = Number(value.toPrecision(3));
    return rounded.toFixed(Math.max(0, 2 - Math.floor(Math.log10(Math.abs(rounded)))));
  };
  const percent = n => `${Number((100 * n).toPrecision(3))}%`;
  const pixels = n => n == null ? '—' : number(n) + ' px';
  const degrees = n => n == null ? '—' : number(n) + '°';
  const parts = [['strain', 'strain'], ['floor', 'floor'], ['falseCreases', 'false creases', 'false creases one level finer']];

  // The headline is the verdict's own; the parts only say which failed, or
  // were not measured. A part not measured is null, which is neither a pass
  // nor a fail, so `!verdict[key]` would misread it.
  function headline(screen) {
    const verdict = screen.verdict;
    const failing = parts.filter(([key]) => verdict[key] === false).map(([, label]) => label);
    const unmeasured = parts.filter(([key]) => verdict[key] === null).map(([, label, missing]) => missing || label);
    if (verdict.passes === true) return 'Passes';
    if (verdict.passes === false) return 'Fails: ' + failing.join(', ');
    if (verdict.passes === null) return 'Not measured: ' + unmeasured.join(', ');
    return '—';
  }

  // A floor over only some pairs says so: on a sheet that is not convex, it
  // takes the pairs whose chord stays on the paper.
  const pairs = screen => screen.floorPairs ? ` (over ${screen.floorPairs[0]} of ${screen.floorPairs[1]} pairs: the sheet is not convex)` : '';

  // The false creases one level finer. Where they come from the gallery's
  // own finer solve (owner decision 29), the cell names that solve and how
  // far apart the two are at worst; where the gallery named a finer solve
  // that does not count, it says so, the finer level then not measured.
  function finerCell(s, finer) {
    if (s.falseCreaseJoinsFiner == null) return finer ? `— (the solve at ${finer.label} does not count)` : '— (not made again)';
    const turning = `${s.falseCreaseJoinsFiner} · ${number(s.falseCreaseTurningFinerSheetDegrees)}`;
    return finer && finer.apartPixels != null ? `${turning} (solved at ${finer.label}, ${pixels(finer.apartPixels)} apart)` : turning;
  }

  // One row per part of the screen, one column per pose. A pose is
  // {title, screen, picture, finer}; `picture` holds its floors after
  // projecting onto the drawing, and a pose drawn in no picture shows a dash
  // there; `finer` is the finer solve its gallery named for it, counted or
  // not. The body core's two rows appear where some pose is a crane's body.
  function rows(poses, limits) {
    const measures = [
      ['Screen (crossings reported only)', s => headline(s)],
      [`Largest stretch / squash · within ${percent(limits.strictStrainScreen)}`, s => `${number(100 * s.stretch)}% / ${number(100 * s.squash)}% · ${s.verdict.strictStrain ? 'yes' : 'no'}`],
      ['No-stretch floor, 3D · this picture', (s, p) => `${pixels(s.floor3dPixels)} · ${pixels(p && p.pictureFloorPixels)}${pairs(s)}`],
      [`Floor at ${percent(limits.strainScreen)} strain, 3D · this picture`, (s, p) => `${pixels(s.floor3dPixelsAtScreen)} · ${pixels(p && p.pictureFloorPixelsAtScreen)}`],
      ['Crossing pairs, strict test · largest reach-through', s => s.crossingPairCount + (s.deepestReachPixels == null ? '' : ' · ' + pixels(s.deepestReachPixels))],
      [`False creases: joins past ${limits.falseCreaseThresholdDegrees}° · turning, sheet units × degrees`, s => `${s.falseCreaseJoins} · ${number(s.falseCreaseTurningSheetDegrees)}`],
      ['The same, one level finer', (s, _, finer) => finerCell(s, finer)]
    ];
    const core = [
      ['Body core length, sheet units', s => s.coreLengthSheets == null ? '—' : number(s.coreLengthSheets)],
      ['Centre folds: midlines / diagonals', s => `${degrees(s.centreMidlineFoldDegrees)} / ${degrees(s.centreDiagonalFoldDegrees)}`]
    ];
    const body = s => s.coreLengthSheets != null || s.centreMidlineFoldDegrees != null || s.centreDiagonalFoldDegrees != null;
    const shown = poses.some(p => body(p.screen)) ? [...measures, ...core] : measures;
    return [['Paper screen', ...poses.map(p => p.title)], ...shown.map(([name, cell]) => [name, ...poses.map(p => cell(p.screen, p.picture, p.finer))])];
  }

  // A gallery's runs as the poses of a table, titled by `titleOf`. A gallery
  // writes beside a run's screen, on the run, its floors in its picture and
  // the finer solve it takes its finer level from.
  const poses = (runs, titleOf) => runs.map(run => ({title: titleOf(run), screen: run.screen, picture: run, finer: run.finerSolve}));

  // Put rows into `container` as a table, the first row as its heading.
  function fill(container, table) {
    const element = document.createElement('table');
    const head = element.createTHead(), body = element.createTBody();
    table.forEach((values, i) => {
      const row = (i === 0 ? head : body).insertRow();
      for (const value of values) {
        const cell = document.createElement(i === 0 ? 'th' : 'td');
        cell.textContent = value;
        row.append(cell);
      }
    });
    container.replaceChildren(element);
  }

  // Show a gallery's runs in `container`, one column each.
  const show = (container, runs, titleOf, limits) => fill(container, rows(poses(runs, titleOf), limits));

  function caption(limits) {
    return `The no-stretch floor is how far some point must move before a pose could be paper. It is a proof, not an estimate: paper cannot stretch, so no two of its points end up further apart than on the flat sheet. Floors and reach-throughs are in pixels, ${limits.pixelsPerSheet} to a sheet unit: one unit of the flat sheet's coordinates, the side of the crane's square and the length of the wing studies' test wing. A pose passes with no more than ${percent(limits.strainScreen)} strain (owner decision 16), a floor of at most ${limits.floorLimitPixels} px at that strain, and no join bent past ${limits.falseCreaseThresholdDegrees}°, on the pose's mesh or on the same pose made again with every triangle split into four (PRD 11's targets). A pose that is not made again is judged on its own mesh, and its finer level is not measured, which neither passes nor fails (owner decision 27). Where its gallery has solved the same control on the mesh split into four, accepts that solve, and finds the two solves within ${limits.floorLimitPixels} px of each other at every vertex of the coarser mesh, that solve counts as the pose made again (owner decisions 29 and 31). A curve the mesh only samples loses turning on the finer mesh; a fold keeps it, and so can a bend narrower than the finer triangles. Strain within ${percent(limits.strictStrainScreen)} is reported and not required. Crossings are reported, not judged: where layers touch, a count measures rounding, and the reach-through is an upper bound on how deep a pair crosses. The screen changes no pose.`;
  }

  return {number, headline, rows, poses, fill, show, caption};
})();
