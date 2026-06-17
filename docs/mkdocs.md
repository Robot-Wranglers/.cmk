# mkdocs.cmk

`mkdocs.cmk` is thin **build / serve / open** helpers over the working-directory `mkdocs.yml`, split
out of `docs.cmk`.  They wrap the host `mkdocs` CLI directly (no container).  A library plugin (no
`__main__`); import it with `$(call include.plugins, mkdocs.cmk)`.

## Public surface

<hr class="section-rule lvl-3">

| Target | Purpose |
| --- | --- |
| `mkdocs` | `mkdocs.build` then `mkdocs.serve` |
| `mkdocs.build` | run `mkdocs build` |
| `mkdocs.serve` | run `mkdocs serve` (honors `MKDOCS_LISTEN_HOST` / `MKDOCS_LISTEN_PORT`) |
| `mkdocs.open` | open the local site in `$BROWSER` |
| `mkdocs.get/<key>` | read a value from `mkdocs.yml` (via `yq`) |

## Usage

<hr class="section-rule lvl-3">

```Makefile
$(call include.plugins, mkdocs.cmk)

# live preview on MKDOCS_LISTEN_PORT
mkdocs.serve

# read a config value from mkdocs.yml
mkdocs.get/site_name
```
