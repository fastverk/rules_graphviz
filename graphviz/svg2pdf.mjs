// Hermetic SVG -> vector PDF, run under bun. No host tools, no browser.
//
//   bun svg2pdf.bundle.js <input.svg> -o <output.pdf>
//   bun svg2pdf.bundle.js -o out.pdf  < input.svg     (reads stdin)
//
// pdfkit writes the PDF; svg-to-pdfkit translates the SVG into pdfkit drawing
// ops. svg-to-pdfkit computes its own geometry from the SVG attributes (it does
// not call getBBox/getCTM), so it is headless-safe: the only DOM it needs is an
// XML parser to walk the tree, supplied by @xmldom/xmldom. That is why this can
// run under bun with no DOM/canvas/native dependency.
//
// This file is the *source*; the vendored, self-contained artifact the toolchain
// runs is `svg2pdf.bundle.js`, produced by:
//
//   bun install   # pins pdfkit, svg-to-pdfkit, @xmldom/xmldom (see README)
//   bun build ./svg2pdf.mjs --target=bun --outfile=svg2pdf.bundle.js
//
// bun inlines every dependency (including pdfkit's standard-font metric data),
// so the bundle needs no node_modules at run time.
import PDFDocument from "pdfkit";
import SVGtoPDF from "svg-to-pdfkit";
import { DOMParser } from "@xmldom/xmldom";

const argv = process.argv.slice(2);
let inPath = null,
  outPath = null;
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === "-o" || a === "--out") outPath = argv[++i];
  else inPath = a;
}

let svg = inPath ? await Bun.file(inPath).text() : await Bun.stdin.text();

// Size the PDF page to the SVG's own coordinate box. Graphviz emits
// width="Wpt" height="Hpt" viewBox="0 0 W H", where one viewBox unit is one
// PostScript point (= one PDF point). We strip the explicit width/height (whose
// "pt" unit otherwise double-scales in svg-to-pdfkit) and drive sizing purely
// from the viewBox at scale 1, so the page matches the graphic exactly.
const vb = svg.match(/viewBox="([\d.\-]+)\s+([\d.\-]+)\s+([\d.]+)\s+([\d.]+)"/);
const W = vb ? parseFloat(vb[3]) : 612;
const H = vb ? parseFloat(vb[4]) : 792;
svg = svg
  .replace(/(<svg\b[^>]*?)\swidth="[^"]*"/, "$1")
  .replace(/(<svg\b[^>]*?)\sheight="[^"]*"/, "$1");

const doc = new PDFDocument({ size: [W, H], margin: 0 });
const chunks = [];
doc.on("data", (c) => chunks.push(c));
const done = new Promise((resolve) => doc.on("end", resolve));

SVGtoPDF(doc, svg, 0, 0, { assumePt: true, width: W, height: H, DOMParser });
doc.end();
await done;

const pdf = Buffer.concat(chunks);
if (outPath) await Bun.write(outPath, pdf);
else process.stdout.write(pdf);
