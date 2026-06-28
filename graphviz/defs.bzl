"""rules_graphviz public API.

- `graphviz_toolchain` — pairs the WASM renderer + bun script (and the optional
  svg2pdf bundle) with `GraphvizToolchainInfo` so the render rules resolve it via
  the standard toolchain mechanism. The default
  (`@rules_graphviz//graphviz:graphviz_toolchain_def`) is registered automatically.
- `dot_diagram` — render one `.dot`/`.gv` file with a chosen layout `engine`
  and `output_format`.
- `dot_corpus` — fan one `dot_diagram` out per source file.
- `svg_pdf` — convert one `.svg` to a vector `.pdf` hermetically (bun + the
  vendored svg2pdf bundle; no host tools, no cairo).
- `dot_pdf` — render a `.dot`/`.gv` straight to vector `.pdf` (dot -> svg -> pdf).
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
            svg2pdf = ctx.file.svg2pdf,
        ),
    )]

graphviz_toolchain = rule(
    implementation = _graphviz_toolchain_impl,
    doc = "Register a hermetic Graphviz renderer (bun script + WASM module, plus " +
          "the optional svg2pdf bundle) for `@rules_graphviz//graphviz:toolchain_type`.",
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
        "svg2pdf": attr.label(
            allow_single_file = True,
            doc = "Self-contained bun bundle (svg2pdf.bundle.js) that converts SVG " +
                  "to vector PDF. Optional; required only for svg_pdf / dot_pdf.",
        ),
    },
)

def _svg_pdf_impl(ctx):
    gv = ctx.toolchains[GRAPHVIZ_TOOLCHAIN_TYPE].graphviz_info
    bun = ctx.toolchains[_BUN_TOOLCHAIN_TYPE].buninfo.bun

    if not gv.svg2pdf:
        fail("rules_graphviz: the resolved toolchain has no svg2pdf bundle; " +
             "svg_pdf/dot_pdf need a toolchain with the `svg2pdf` attribute set.")

    out = ctx.actions.declare_file(ctx.label.name + ".pdf")

    args = ctx.actions.args()
    args.add(gv.svg2pdf)
    args.add(ctx.file.src)
    args.add("-o", out)

    ctx.actions.run(
        executable = bun,
        arguments = [args],
        inputs = [ctx.file.src, gv.svg2pdf],
        outputs = [out],
        mnemonic = "SvgToPdf",
        progress_message = "svg2pdf %{label}",
    )
    return [DefaultInfo(files = depset([out]))]

svg_pdf = rule(
    implementation = _svg_pdf_impl,
    doc = "Convert a single `.svg` to a vector `.pdf` hermetically (bun + the " +
          "vendored svg2pdf bundle — no host tools, no cairo). The page is sized " +
          "to the SVG's viewBox.",
    attrs = {
        "src": attr.label(
            allow_single_file = [".svg"],
            mandatory = True,
            doc = "An SVG file (e.g. the output of a dot_diagram).",
        ),
    },
    toolchains = [GRAPHVIZ_TOOLCHAIN_TYPE, _BUN_TOOLCHAIN_TYPE],
)

def dot_pdf(name, src, engine = "dot", **kwargs):
    """Render a `.dot`/`.gv` straight to a vector `.pdf` (dot -> svg -> pdf).

    Produces a target `name` whose output is `<name>.pdf`. Internally renders
    the SVG with the WASM engine (`<name>__svg`) and converts it with `svg_pdf`.

    Args:
      name: target name; output is `<name>.pdf`.
      src: a `.dot`/`.gv` label.
      engine: layout engine (dot/neato/fdp/sfdp/twopi/circo/osage/patchwork).
      **kwargs: forwarded to both rules (visibility, tags, …).
    """
    dot_diagram(
        name = name + "__svg",
        src = src,
        engine = engine,
        output_format = "svg",
        **{k: v for k, v in kwargs.items() if k in ("visibility", "tags")}
    )
    svg_pdf(
        name = name,
        src = ":" + name + "__svg",
        **kwargs
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
