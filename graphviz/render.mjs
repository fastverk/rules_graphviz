// Hermetic Graphviz renderer: runs @hpcc-js/wasm-graphviz (WASM, inlined in
// graphviz.js) under bun. No host graphviz needed.
//   bun render.mjs --engine <dot|neato|...> --format <svg|dot|json|...> --out <path> <input.dot>
// Reads stdin if no input path is given; writes stdout if no --out.
import { Graphviz } from "./graphviz.js";

const argv = process.argv.slice(2);
let engine = "dot", format = "svg", out = null, input = null;
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === "--engine") engine = argv[++i];
  else if (a === "--format") format = argv[++i];
  else if (a === "--out" || a === "-o") out = argv[++i];
  else input = a;
}

const graphviz = await Graphviz.load();
const dot = input ? await Bun.file(input).text() : await Bun.stdin.text();
const rendered = graphviz.layout(dot, format, engine);
if (out) await Bun.write(out, rendered);
else process.stdout.write(rendered);
