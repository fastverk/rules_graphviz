"""Toolchain type + info provider for hermetic Graphviz.

Graphviz's native binaries drag in a large C dependency tree (cairo, pango, gd,
freetype, fontconfig, …) and a plugin architecture, which makes a clean
cross-platform native bundle hard. Instead, the default toolchain registered by
rules_graphviz runs **@hpcc-js/wasm-graphviz** (Graphviz compiled to WebAssembly,
with the WASM inlined into a single JS file) under a **hermetic bun** runtime
(via rules_bun). That gives every layout engine + the structured output formats
with zero host dependency, on every platform bun runs on.

Consumers who need the native standalone tools (gvpr/gvpack/tred/…) or raster
output (png/pdf — not in the WASM build) can register their own toolchain for
`@rules_graphviz//graphviz:toolchain_type` and the rules pick it up unchanged.
"""

GraphvizToolchainInfo = provider(
    doc = "Carries the hermetic Graphviz renderer used by dot_diagram et al.",
    fields = {
        "renderer": "File — the bun entry script (render.mjs) that drives the WASM engine.",
        "wasm": "File — the @hpcc-js/wasm-graphviz module (graphviz.js, WASM inlined).",
        "engines": "list[str] — Graphviz layout engines this toolchain supports.",
    },
)

GRAPHVIZ_TOOLCHAIN_TYPE = "@rules_graphviz//graphviz:toolchain_type"

# Graphviz layout engines (all present in the WASM build, selected per render).
LAYOUT_ENGINES = [
    "dot",
    "neato",
    "fdp",
    "sfdp",
    "twopi",
    "circo",
    "osage",
    "patchwork",
]

# Output formats the WASM build emits. (Raster png/pdf need cairo, which is not
# in the WASM build — register a native toolchain for those.)
OUTPUT_FORMATS = [
    "svg",
    "dot",
    "canon",
    "xdot",
    "json",
    "json0",
    "plain",
    "plain-ext",
    "gv",
]
