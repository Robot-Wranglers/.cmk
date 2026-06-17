# grip.cmk

`grip.cmk` **serves a GitHub-styled render of `README.md`** (via
[grip](https://github.com/joeyespo/grip)) from a container, split out of `docs.cmk`.  A library plugin
(no `__main__`); import it with `$(call include.plugins, grip.cmk)`.

## Public surface

<hr class="section-rule lvl-3">

| Target | Purpose |
| --- | --- |
| `docs.grip` / `docs.grip.serve` | serve `README.md` on `GRIP_PORT` (default `6419`) |
| `docs.grip.serve/<file>` | serve a specific markdown file |
| `GRIP_PORT` | the port grip listens on (default `6419`) |

The grip image is an inline `Dockerfile grip(| |)` container declaration; its `.build` runs on first use.

## Usage

<hr class="section-rule lvl-3">

```Makefile
$(call include.plugins, grip.cmk)

# live-preview README.md at http://localhost:6419
docs.grip

# ...or a specific file, on a custom port
GRIP_PORT=8080 docs.grip.serve/docs/guide.md
```
