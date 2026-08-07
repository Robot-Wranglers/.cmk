# grip.cmk

`grip.cmk` **serves a GitHub-styled render of `README.md`** (via
[grip](https://github.com/joeyespo/grip)) from a container, split out of `docs.cmk`.  A library plugin
(no `__main__`); import it with `$(call include.plugins, grip.cmk)`.

## Public surface

<hr class="section-rule lvl-3">

| Target | Purpose |
| --- | --- |
| `docs.grip` / `docs.grip.serve` | serve `README.md` on `GRIP_PORT`, blocking |
| `docs.grip.serve/<file>` | serve a specific markdown file, blocking |
| `docs.grip.serve.bg` | serve detached, in a container named `grip` |
| `docs.grip.stop` | stop that container |
| `docs.grip.status` | report whether it is running |
| `GRIP_PORT` | the port grip listens on (default `6419`) |

Every verb is also reachable unprefixed, as `grip.serve`, `grip.stop`, and so on.  Serving a
missing file fails on the `assert.file` guard rather than starting a container.

## Lifecycle

<hr class="section-rule lvl-3">

The image is an inline `Dockerfile grip(| |)` declaration whose `.build` runs on first use.  It
declares two things past the recipe:

```Makefile
Dockerfile grip(bases=lifecycle.container, docker_args="-p ${GRIP_PORT}:${GRIP_PORT}")(| .. |)
```

`docker_args` publishes the port, and is read from the declaration keyword rather than repeated at
each call site.  `bases=lifecycle.container` mixes in the [Lifecycle](/compose.mk/cmk/concepts/#protocols)
protocol's container variant, which is where the detached, stop, and status verbs come from: the
container is identified by name, so stopping it is a `docker stop` rather than a signal to whatever
launched it.  The blocking verb stays local, supplied as `grip.__serve__`.

## Usage

<hr class="section-rule lvl-3">

```Makefile
$(call include.plugins, grip.cmk)

# live-preview README.md at http://localhost:6419, blocking
docs.grip

# ...or a specific file, on a custom port
GRIP_PORT=8080 docs.grip.serve/docs/guide.md

# ...or in the background, then check on it and shut it down
docs.grip.serve.bg
docs.grip.status
docs.grip.stop
```
