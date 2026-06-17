# mmd.cmk

`mmd.cmk` renders [Mermaid](https://mermaid.js.org/) diagrams (`*.mmd`) to **PNG**, split out of
`docs.cmk`.  It wraps `mermaid-cli` (`mmdc`) in a container, then trims each PNG to its content with
imagemagick.  A library plugin (no `__main__`); import it with `$(call include.plugins, mmd.cmk)`.

## Public surface

<hr class="section-rule lvl-3">

| Target | Purpose |
| --- | --- |
| `docs.mmd/<file>` | render one `*.mmd` to a sibling `<name>.png` (trimmed) |
| `docs.mmd` / `docs.mermaid` | render every `*.mmd` under `docs.root` |
| `docs.mmd.build` | build the mermaid container |
| `docs.mmd.shell` / `.stat` / `.version` | container shell + version/info helpers |

## How it works

<hr class="section-rule lvl-3">

The mermaid image is an inline `define Dockerfile.mermaid` (built by `docs.mmd.build`).  Each render
runs `mmdc` in that container to produce a PNG, then a second pass pipes it through imagemagick
(`-trim`) so the output is cropped to content.  `mmd.config` optionally points at a mermaid config file.

## Usage

<hr class="section-rule lvl-3">

```Makefile
$(call include.plugins, mmd.cmk)

# render one diagram to a sibling PNG...
docs.mmd/docs/img/flow.mmd

# ...or every *.mmd under the docs root
docs.mermaid
```
