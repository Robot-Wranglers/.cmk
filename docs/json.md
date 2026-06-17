# json.cmk

`json.cmk` populates a `json.*` namespace with small JSON **validation** and **conversion** helpers.
Nothing fancy -- it is kept out of the `compose.mk` standard library just to avoid clutter, and
imported on demand with `$(call include.plugins, json.cmk)`.

The helpers also read naturally as members of the `io` and `stream` namespaces, so each is surfaced
there too; the `json.*` names stay canonical (backward compat) and the aliases are thin prereqs onto
them.

## Public surface

<hr class="section-rule lvl-3">

| Target | Purpose | Also surfaced as |
| --- | --- | --- |
| `json.validate/<path>` | validate a JSON file, or every `*.json` under a dir | `io.json.validate/<path>` |
| `json.from_cols` | autodetect columns from line input, emit JSON | `stream.json.from_cols` |
| `json.parse` | parse JSON from line input by pattern | `stream.json.parse` |
| `json.to_yaml` | convert JSON to YAML | `stream.json.to_yaml` |

The conversions are backed by [nushell](../structured-io.md#nushell) and validation shells out to
[`jq`](../structured-io.md); both -- along with [`jb`](../structured-io.md) -- are provided by the
[structured-IO standard library](../structured-io.md) without a hard dependency, so these helpers slot
straight into the same `stream.*` / `io.*` JSON pipeline vocabulary documented there.

## Executable module

<hr class="section-rule lvl-3">

Run `json.cmk` directly (`./json.cmk`) to print an overview of the helpers.  Once imported
(`$(call include.plugins, json.cmk)`), that overview is available as the `json` target (`${make} json`) --
the module's `__main__` is demoted on import, so it never collides with the importer's own.

## Usage

<hr class="section-rule lvl-3">

```Makefile
$(call include.plugins, json.cmk)

# validate one file, or every *.json under a directory
json.validate/pkg.json
json.validate/config/
```

The `stream.json.*` conversions read line input and emit JSON / YAML, so they compose with the rest of
the `stream.*` pipeline vocabulary.
