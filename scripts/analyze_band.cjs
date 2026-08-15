const fs = require('fs');
const path = require('path');

const scfDir = path.resolve(process.argv[2]);
const bandDir = path.resolve(process.argv[3]);
const outputDir = path.resolve(process.argv[4]);
const rulesPath = path.resolve(process.argv[5] || path.join(__dirname, '..', 'config', 'rules', 'analysis-rules.json'));

function loadAnalysisRules(file) {
  const rules = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (rules.schemaVersion !== 1 || !rules.plot || !Array.isArray(rules.supportedIspin)) {
    throw new Error(`Unsupported or invalid analysis rules: ${file}`);
  }
  if (rules.bandEdgeModel !== 'closed-shell-electron-count') {
    throw new Error(`Unsupported band-edge model: ${rules.bandEdgeModel}`);
  }
  return rules;
}

const analysisRules = loadAnalysisRules(rulesPath);

function readText(file) {
  return fs.readFileSync(file, 'utf8');
}

function parseEigenval(file) {
  const lines = readText(file).split(/\r?\n/);
  const counts = lines[5].trim().split(/\s+/).map(Number);
  const [nelect, nkpoints, nbands] = counts;
  let cursor = 6;
  const kpoints = [];
  const weights = [];
  const energies = [];
  const occupations = [];
  for (let k = 0; k < nkpoints; k += 1) {
    while (cursor < lines.length && !lines[cursor].trim()) cursor += 1;
    const kp = lines[cursor].trim().split(/\s+/).map(Number);
    cursor += 1;
    kpoints.push(kp.slice(0, 3));
    weights.push(kp[3]);
    const e = [];
    const o = [];
    for (let band = 0; band < nbands; band += 1) {
      const fields = lines[cursor].trim().split(/\s+/).map(Number);
      cursor += 1;
      e.push(fields[1]);
      o.push(fields[2]);
    }
    energies.push(e);
    occupations.push(o);
  }
  return { nelect, nkpoints, nbands, kpoints, weights, energies, occupations };
}

function parsePoscar(file) {
  const lines = readText(file).trim().split(/\r?\n/);
  const scale = Number(lines[1].trim());
  const lattice = lines.slice(2, 5).map((line) => line.trim().split(/\s+/).map(Number).map((value) => value * scale));
  return { lattice };
}

function cross(a, b) {
  return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
}

function dot(a, b) {
  return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

function scaleVec(vector, factor) {
  return vector.map((value) => value * factor);
}

function reciprocalLattice(lattice) {
  const [a1, a2, a3] = lattice;
  const volume = dot(a1, cross(a2, a3));
  const factor = 2 * Math.PI / volume;
  return [scaleVec(cross(a2, a3), factor), scaleVec(cross(a3, a1), factor), scaleVec(cross(a1, a2), factor)];
}

function fractionalToCartesian(kpoint, reciprocal) {
  return [0, 1, 2].map((component) => kpoint[0] * reciprocal[0][component] + kpoint[1] * reciprocal[1][component] + kpoint[2] * reciprocal[2][component]);
}

function distance(a, b) {
  return Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);
}

function parseFermi(file) {
  const matches = [...readText(file).matchAll(/E-fermi\s*:\s*([-+0-9.Ee]+)/g)];
  return matches.length ? Number(matches[matches.length - 1][1]) : null;
}

function bandEdges(dataset) {
  const occupiedBand = Math.round(dataset.nelect / 2) - 1;
  const conductionBand = occupiedBand + 1;
  let vbm = { energy: -Infinity, kIndex: -1, bandIndex: occupiedBand };
  let cbm = { energy: Infinity, kIndex: -1, bandIndex: conductionBand };
  let directGap = { energy: Infinity, kIndex: -1 };
  for (let k = 0; k < dataset.nkpoints; k += 1) {
    const valence = dataset.energies[k][occupiedBand];
    const conduction = dataset.energies[k][conductionBand];
    if (valence > vbm.energy) vbm = { energy: valence, kIndex: k, bandIndex: occupiedBand };
    if (conduction < cbm.energy) cbm = { energy: conduction, kIndex: k, bandIndex: conductionBand };
    if (conduction - valence < directGap.energy) directGap = { energy: conduction - valence, kIndex: k };
  }
  return {
    occupiedBand: occupiedBand + 1,
    conductionBand: conductionBand + 1,
    vbm,
    cbm,
    indirectGap: cbm.energy - vbm.energy,
    directGap,
    isDirect: vbm.kIndex === cbm.kIndex,
  };
}

function parseBandPath(file) {
  const lines = readText(file).split(/\r?\n/);
  const pointsPerSegment = Number(lines[1].trim());
  const endpointLines = lines.slice(4).filter((line) => line.trim());
  const endpoints = endpointLines.map((line) => {
    const parts = line.trim().split(/\s+/);
    return { k: parts.slice(0, 3).map(Number), label: parts.slice(3).join(' ') || '' };
  });
  const segments = [];
  for (let index = 0; index < endpoints.length; index += 2) {
    segments.push({ start: endpoints[index], end: endpoints[index + 1] });
  }
  return { pointsPerSegment, segments };
}

function cleanLabel(label) {
  return label.toLowerCase() === 'gamma' ? 'Γ' : label;
}

function buildPathCoordinates(dataset, pathDefinition, reciprocal) {
  const { pointsPerSegment, segments } = pathDefinition;
  if (segments.length * pointsPerSegment !== dataset.nkpoints) {
    throw new Error(`Band path mismatch: ${segments.length} segments x ${pointsPerSegment} points != ${dataset.nkpoints}`);
  }
  const x = new Array(dataset.nkpoints).fill(0);
  const segmentIndex = new Array(dataset.nkpoints).fill(0);
  let offset = 0;
  const ticks = [{ x: 0, label: cleanLabel(segments[0].start.label) }];
  for (let segment = 0; segment < segments.length; segment += 1) {
    const startIndex = segment * pointsPerSegment;
    const endIndex = startIndex + pointsPerSegment - 1;
    let local = 0;
    x[startIndex] = offset;
    segmentIndex[startIndex] = segment;
    for (let index = startIndex + 1; index <= endIndex; index += 1) {
      const previous = fractionalToCartesian(dataset.kpoints[index - 1], reciprocal);
      const current = fractionalToCartesian(dataset.kpoints[index], reciprocal);
      local += distance(previous, current);
      x[index] = offset + local;
      segmentIndex[index] = segment;
    }
    offset += local;
    const endLabel = cleanLabel(segments[segment].end.label);
    const nextStart = segment + 1 < segments.length ? cleanLabel(segments[segment + 1].start.label) : null;
    ticks.push({ x: offset, label: nextStart && nextStart !== endLabel ? `${endLabel}|${nextStart}` : endLabel });
  }
  return { x, ticks, segmentIndex, totalLength: offset };
}

function describeBandLocation(index, dataset, pathDefinition, pathCoordinates) {
  const segment = pathCoordinates.segmentIndex[index];
  const startIndex = segment * pathDefinition.pointsPerSegment;
  const fraction = (index - startIndex) / (pathDefinition.pointsPerSegment - 1);
  const definition = pathDefinition.segments[segment];
  return {
    kIndex: index + 1,
    segment: `${cleanLabel(definition.start.label)}–${cleanLabel(definition.end.label)}`,
    segmentFraction: fraction,
    fractionalKpoint: dataset.kpoints[index],
    pathDistance: pathCoordinates.x[index],
  };
}

function formatNumber(value, digits = 6) {
  return Number(value.toFixed(digits));
}

function escapeXml(value) {
  return String(value).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function buildSvg(dataset, edges, pathCoordinates, pathDefinition, fermiEnergy, plotRules) {
  const width = plotRules.width;
  const height = plotRules.height;
  const margin = plotRules.margin;
  const plotWidth = width - margin.left - margin.right;
  const plotHeight = height - margin.top - margin.bottom;
  const yMin = plotRules.energyWindowEv.minimum;
  const yMax = plotRules.energyWindowEv.maximum;
  const reference = edges.vbm.energy;
  const xScale = (value) => margin.left + (value / pathCoordinates.totalLength) * plotWidth;
  const yScale = (value) => margin.top + ((yMax - value) / (yMax - yMin)) * plotHeight;
  const occupiedIndex = edges.occupiedBand - 1;
  const conductionIndex = edges.conductionBand - 1;
  const parts = [];
  parts.push(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" role="img" aria-labelledby="title desc">`);
  parts.push('<title id="title">VASP electronic band structure</title>');
  parts.push(`<desc id="desc">VASP electronic band structure. Indirect path gap ${edges.indirectGap.toFixed(3)} electron volts.</desc>`);
  parts.push('<rect width="100%" height="100%" fill="#ffffff"/>');
  parts.push(`<text x="${margin.left}" y="48" font-family="Segoe UI, Arial, sans-serif" font-size="31" font-weight="700" fill="#172033">VASP Band Structure</text>`);
  parts.push(`<text x="${margin.left}" y="82" font-family="Segoe UI, Arial, sans-serif" font-size="18" fill="#526072">gap along plotted path = ${edges.indirectGap.toFixed(3)} eV · energies referenced to VBM</text>`);
  parts.push(`<rect x="${margin.left}" y="${margin.top}" width="${plotWidth}" height="${plotHeight}" fill="#fbfcfe" stroke="#c9d1dc" stroke-width="1"/>`);
  for (let tick = Math.ceil(yMin); tick <= Math.floor(yMax); tick += 1) {
    const y = yScale(tick);
    parts.push(`<line x1="${margin.left}" x2="${margin.left + plotWidth}" y1="${y}" y2="${y}" stroke="${tick === 0 ? '#596579' : '#e4e8ef'}" stroke-width="${tick === 0 ? 1.7 : 1}" ${tick === 0 ? 'stroke-dasharray="7 5"' : ''}/>`);
    parts.push(`<text x="${margin.left - 16}" y="${y + 6}" text-anchor="end" font-family="Segoe UI, Arial, sans-serif" font-size="16" fill="#566174">${tick}</text>`);
  }
  for (const tick of pathCoordinates.ticks) {
    const x = xScale(tick.x);
    parts.push(`<line x1="${x}" x2="${x}" y1="${margin.top}" y2="${margin.top + plotHeight}" stroke="#c3cad5" stroke-width="1"/>`);
    parts.push(`<text x="${x}" y="${margin.top + plotHeight + 37}" text-anchor="middle" font-family="Segoe UI, Arial, sans-serif" font-size="19" fill="#273247">${escapeXml(tick.label)}</text>`);
  }
  const clipId = 'plot-clip';
  parts.push(`<defs><clipPath id="${clipId}"><rect x="${margin.left}" y="${margin.top}" width="${plotWidth}" height="${plotHeight}"/></clipPath></defs>`);
  parts.push(`<g clip-path="url(#${clipId})">`);
  for (let band = 0; band < dataset.nbands; band += 1) {
    const color = band <= occupiedIndex ? plotRules.colors.valence : plotRules.colors.conduction;
    const widthBand = band === occupiedIndex || band === conductionIndex ? plotRules.lineWidth.edge : plotRules.lineWidth.other;
    const opacity = band === occupiedIndex || band === conductionIndex ? plotRules.opacity.edge : plotRules.opacity.other;
    for (let segment = 0; segment < pathDefinition.segments.length; segment += 1) {
      const start = segment * pathDefinition.pointsPerSegment;
      const end = start + pathDefinition.pointsPerSegment;
      let d = '';
      for (let index = start; index < end; index += 1) {
        const px = xScale(pathCoordinates.x[index]);
        const py = yScale(dataset.energies[index][band] - reference);
        d += `${index === start ? 'M' : 'L'}${px.toFixed(2)},${py.toFixed(2)} `;
      }
      parts.push(`<path d="${d.trim()}" fill="none" stroke="${color}" stroke-width="${widthBand}" opacity="${opacity}"/>`);
    }
  }
  parts.push('</g>');
  const vbmX = xScale(pathCoordinates.x[edges.vbm.kIndex]);
  const vbmY = yScale(0);
  const cbmX = xScale(pathCoordinates.x[edges.cbm.kIndex]);
  const cbmY = yScale(edges.indirectGap);
  parts.push(`<circle cx="${vbmX}" cy="${vbmY}" r="6" fill="${plotRules.colors.vbm}" stroke="#ffffff" stroke-width="2"/>`);
  parts.push(`<circle cx="${cbmX}" cy="${cbmY}" r="6" fill="${plotRules.colors.cbm}" stroke="#ffffff" stroke-width="2"/>`);
  const annotationX = Math.min(margin.left + plotWidth - 150, Math.max(margin.left + 150, cbmX + 55));
  parts.push(`<line x1="${annotationX}" x2="${annotationX}" y1="${vbmY}" y2="${cbmY}" stroke="${plotRules.colors.gap}" stroke-width="2" marker-start="url(#arrow)" marker-end="url(#arrow)"/>`);
  parts.push(`<defs><marker id="arrow" markerWidth="8" markerHeight="8" refX="4" refY="4" orient="auto"><path d="M0,4 L8,0 L8,8 Z" fill="${plotRules.colors.gap}"/></marker></defs>`);
  parts.push(`<text x="${annotationX + 13}" y="${(vbmY + cbmY) / 2 + 6}" font-family="Segoe UI, Arial, sans-serif" font-size="18" font-weight="700" fill="#704900">${edges.indirectGap.toFixed(3)} eV</text>`);
  parts.push(`<text x="${width / 2}" y="${height - 25}" text-anchor="middle" font-family="Segoe UI, Arial, sans-serif" font-size="17" fill="#566174">Wave vector</text>`);
  parts.push(`<text x="30" y="${margin.top + plotHeight / 2}" transform="rotate(-90 30 ${margin.top + plotHeight / 2})" text-anchor="middle" font-family="Segoe UI, Arial, sans-serif" font-size="18" fill="#566174">Energy − VBM (eV)</text>`);
  parts.push(`<text x="${margin.left + plotWidth - 10}" y="${margin.top + 28}" text-anchor="end" font-family="Segoe UI, Arial, sans-serif" font-size="15" fill="${plotRules.colors.valence}">Valence</text>`);
  parts.push(`<text x="${margin.left + plotWidth - 10}" y="${margin.top + 51}" text-anchor="end" font-family="Segoe UI, Arial, sans-serif" font-size="15" fill="${plotRules.colors.conduction}">Conduction</text>`);
  parts.push('</svg>');
  return parts.join('\n');
}

function main() {
  fs.mkdirSync(outputDir, { recursive: true });
  if (!process.argv[4]) throw new Error('Usage: node analyze_band.cjs <scf-dir> <band-dir> <output-dir> [analysis-rules.json]');
  const outcarText = readText(path.join(bandDir, 'OUTCAR'));
  const ispin = Number((outcarText.match(/^\s*ISPIN\s*=\s*(\d+)/m) || [])[1] || 1);
  if (!analysisRules.supportedIspin.includes(ispin)) throw new Error(`ISPIN=${ispin} is disabled by the analysis rules.`);
  if (ispin !== 1) throw new Error('The current EIGENVAL parser only supports ISPIN=1.');
  const incarText = readText(path.join(bandDir, 'INCAR'));
  const spinOrbitCoupling = /^\s*LSORBIT\s*=\s*(?:T|\.TRUE\.|TRUE)/mi.test(incarText);
  const scf = parseEigenval(path.join(scfDir, 'EIGENVAL'));
  const band = parseEigenval(path.join(bandDir, 'EIGENVAL'));
  const lattice = parsePoscar(path.join(bandDir, 'POSCAR')).lattice;
  const reciprocal = reciprocalLattice(lattice);
  const pathDefinition = parseBandPath(path.join(bandDir, 'KPOINTS'));
  const pathCoordinates = buildPathCoordinates(band, pathDefinition, reciprocal);
  const scfEdges = bandEdges(scf);
  const bandEdgesResult = bandEdges(band);
  const scfFermi = parseFermi(path.join(scfDir, 'OUTCAR'));
  const bandFermi = parseFermi(path.join(bandDir, 'OUTCAR'));
  const summary = {
    method: `VASP band structure (ISPIN=1, ${spinOrbitCoupling ? 'SOC' : 'no SOC'})`,
    spinOrbitCoupling,
    electronCount: band.nelect,
    occupiedBand: bandEdgesResult.occupiedBand,
    conductionBand: bandEdgesResult.conductionBand,
    scfMesh: {
      kpoints: scf.nkpoints,
      bands: scf.nbands,
      fermiEnergyEv: scfFermi,
      indirectGapEv: scfEdges.indirectGap,
      minimumDirectGapEv: scfEdges.directGap.energy,
      isDirectAtSampledKpoints: scfEdges.isDirect,
      vbmEnergyEv: scfEdges.vbm.energy,
      cbmEnergyEv: scfEdges.cbm.energy,
      vbmFractionalKpoint: scf.kpoints[scfEdges.vbm.kIndex],
      cbmFractionalKpoint: scf.kpoints[scfEdges.cbm.kIndex],
    },
    plottedPath: {
      kpoints: band.nkpoints,
      bands: band.nbands,
      fermiEnergyEv: bandFermi,
      indirectGapEv: bandEdgesResult.indirectGap,
      minimumDirectGapEv: bandEdgesResult.directGap.energy,
      isDirect: bandEdgesResult.isDirect,
      vbmEnergyEv: bandEdgesResult.vbm.energy,
      cbmEnergyEv: bandEdgesResult.cbm.energy,
      vbmLocation: describeBandLocation(bandEdgesResult.vbm.kIndex, band, pathDefinition, pathCoordinates),
      cbmLocation: describeBandLocation(bandEdgesResult.cbm.kIndex, band, pathDefinition, pathCoordinates),
      directGapLocation: describeBandLocation(bandEdgesResult.directGap.kIndex, band, pathDefinition, pathCoordinates),
      labels: pathCoordinates.ticks,
    },
  };
  const roundedSummary = JSON.parse(JSON.stringify(summary, (_key, value) => typeof value === 'number' ? formatNumber(value, 8) : value));
  fs.writeFileSync(path.join(outputDir, 'band_gap_summary.json'), JSON.stringify(roundedSummary, null, 2) + '\n');
  const summaryText = [
    'VASP band-gap analysis',
    '======================',
    summary.method,
    '',
    `SCF mesh indirect gap: ${summary.scfMesh.indirectGapEv.toFixed(6)} eV`,
    `SCF mesh minimum direct gap: ${summary.scfMesh.minimumDirectGapEv.toFixed(6)} eV`,
    `SCF VBM k-point: ${summary.scfMesh.vbmFractionalKpoint.map((value) => value.toFixed(7)).join(' ')}`,
    `SCF CBM k-point: ${summary.scfMesh.cbmFractionalKpoint.map((value) => value.toFixed(7)).join(' ')}`,
    '',
    `Plotted-path gap: ${summary.plottedPath.indirectGapEv.toFixed(6)} eV`,
    `Plotted-path minimum direct gap: ${summary.plottedPath.minimumDirectGapEv.toFixed(6)} eV`,
    `VBM: ${summary.plottedPath.vbmLocation.segment}, fraction ${summary.plottedPath.vbmLocation.segmentFraction.toFixed(6)}, k = ${summary.plottedPath.vbmLocation.fractionalKpoint.map((value) => value.toFixed(7)).join(' ')}`,
    `CBM: ${summary.plottedPath.cbmLocation.segment}, fraction ${summary.plottedPath.cbmLocation.segmentFraction.toFixed(6)}, k = ${summary.plottedPath.cbmLocation.fractionalKpoint.map((value) => value.toFixed(7)).join(' ')}`,
    `Direct/indirect on plotted path: ${summary.plottedPath.isDirect ? 'direct' : 'indirect'}`,
    '',
    `SCF E-fermi: ${scfFermi.toFixed(6)} eV`,
    `Band E-fermi: ${bandFermi.toFixed(6)} eV`,
  ].join('\n');
  fs.writeFileSync(path.join(outputDir, 'band_gap_summary.txt'), summaryText + '\n');
  const rows = ['k_index,segment_index,path_distance_invA,kx,ky,kz,band_index,energy_ev,energy_minus_vbm_ev,occupation'];
  for (let k = 0; k < band.nkpoints; k += 1) {
    for (let b = 0; b < band.nbands; b += 1) {
      rows.push([
        k + 1,
        pathCoordinates.segmentIndex[k] + 1,
        pathCoordinates.x[k].toFixed(9),
        ...band.kpoints[k].map((value) => value.toFixed(9)),
        b + 1,
        band.energies[k][b].toFixed(9),
        (band.energies[k][b] - bandEdgesResult.vbm.energy).toFixed(9),
        band.occupations[k][b].toFixed(6),
      ].join(','));
    }
  }
  fs.writeFileSync(path.join(outputDir, 'band_structure.csv'), rows.join('\n') + '\n');
  const svg = buildSvg(band, bandEdgesResult, pathCoordinates, pathDefinition, bandFermi, analysisRules.plot);
  const svgPath = path.join(outputDir, 'band_structure.svg');
  fs.writeFileSync(svgPath, svg);
  console.log(summaryText);
  console.log(`SVG: ${svgPath}`);
}

try {
  main();
} catch (error) {
  console.error(error.stack || error.message || String(error));
  process.exit(1);
}
