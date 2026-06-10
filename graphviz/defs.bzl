"""rules_graphviz public API.

- `graphviz_toolchain` — pairs the WASM renderer + bun script with
  `GraphvizToolchainInfo` so the render rules resolve it via the standard
  toolchain mechanism. The default (`@rules_graphviz//graphviz:graphviz_toolchain_def`)
  is registered automatically.
- `dot_diagram` — render one `.dot`/`.gv` file with a chosen layout `engine`
  and `output_format`.
- `dot_corpus` — fan one `dot_diagram` out per source file.
"""

load(
    ":toolchain_type.bzl",
    "GRAPHVIZ_TOOLCHAIN_TYPE",
    "GraphvizToolchainInfo",
    "LAYOUT_ENGINES",
    "OUTPUT_FORMATS",
)

_BUN_TOOLCHAIN_TYPE = "@rules_bun//bun:toolchain_type"

def _graphviz_toolchain_impl(ctx):
    return [platform_common.ToolchainInfo(
        graphviz_info = GraphvizToolchainInfo(
            renderer = ctx.file.renderer,
            wasm = ctx.file.wasm,
            engines = ctx.attr.engines,
        ),
    )]

graphviz_toolchain = rule(
    implementation = _graphviz_toolchain_impl,
    doc = "Register a hermetic Graphviz renderer (bun script + WASM module) for " +
          "`@rules_graphviz//graphviz:toolchain_type`.",
    attrs = {
        "renderer": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "bun entry script that drives the WASM engine (render.mjs).",
        ),
        "wasm": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "@hpcc-js/wasm-graphviz module (graphviz.js, WASM inlined). Must " +
                  "sit next to `renderer` so its `import \"./graphviz.js\"` resolves.",
        ),
        "engines": attr.string_list(
            default = LAYOUT_ENGINES,
            doc = "Layout engines this toolchain supports.",
        ),
    },
)

def _dot_diagram_impl(ctx):
    gv = ctx.toolchains[GRAPHVIZ_TOOLCHAIN_TYPE].graphviz_info
    bun = ctx.toolchains[_BUN_TOOLCHAIN_TYPE].buninfo.bun

    if ctx.attr.engine not in gv.engines:
        fail("rules_graphviz: engine {!r} not in toolchain engines {}".format(
            ctx.attr.engine,
            gv.engines,
        ))

    out = ctx.actions.declare_file("{}.{}".format(ctx.label.name, ctx.attr.output_format))

    args = ctx.actions.args()
    args.add(gv.renderer)
    args.add("--engine", ctx.attr.engine)
    args.add("--format", ctx.attr.output_format)
    args.add("--out", out)
    args.add(ctx.file.src)

    ctx.actions.run(
        executable = bun,
        arguments = [args],
        inputs = [ctx.file.src, gv.renderer, gv.wasm],
        outputs = [out],
        mnemonic = "GraphvizRender",
        progress_message = "graphviz(%s) %%{label}" % ctx.attr.engine,
    )
    return [DefaultInfo(files = depset([out]))]

dot_diagram = rule(
    implementation = _dot_diagram_impl,
    doc = "Render a single Graphviz `.dot`/`.gv` file via the hermetic WASM " +
          "toolchain (bun). Pick the layout `engine` and `output_format`.",
    attrs = {
        "src": attr.label(
            allow_single_file = [".dot", ".gv"],
            mandatory = True,
            doc = "A Graphviz `.dot`/`.gv` source file.",
        ),
        "engine": attr.string(
            default = "dot",
            values = LAYOUT_ENGINES,
            doc = "Graphviz layout engine.",
        ),
        "output_format": attr.string(
            default = "svg",
            values = OUTPUT_FORMATS,
            doc = "Output format (svg / dot / json / plain / xdot / …). Raster " +
                  "png/pdf are not in the WASM build.",
        ),
    },
    toolchains = [GRAPHVIZ_TOOLCHAIN_TYPE, _BUN_TOOLCHAIN_TYPE],
)

def dot_corpus(name, srcs, engine = "dot", output_format = "svg", **kwargs):
    """Emit one `dot_diagram` per `.dot`/`.gv` in `srcs`, grouped under `name`.

    Args:
      name: filegroup name; per-file targets are `<name>__<basename>`.
      srcs: list of `.dot`/`.gv` labels.
      engine: layout engine forwarded to each diagram.
      output_format: output format forwarded to each diagram.
      **kwargs: forwarded to each generated rule (visibility, tags, …).
    """
    outs = []
    for src in srcs:
        bare = src.lstrip(":").rsplit("/", 1)[-1]
        slug = bare.replace(".", "_").replace("/", "_")
        target = "{}__{}".format(name, slug)
        dot_diagram(
            name = target,
            src = src,
            engine = engine,
            output_format = output_format,
            **kwargs
        )
        outs.append(":" + target)
    native.filegroup(
        name = name,
        srcs = outs,
        **{k: v for k, v in kwargs.items() if k in ("visibility", "tags")}
    )
