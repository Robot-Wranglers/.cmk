## CMK Extensions

[compose.mk](http://robot-wranglers.github.io/compose.mk) is a standard library for `make` that supports docker, polyglots, and domain-agnostic project automation.  It's also secretly [a programming language](https://robot-wranglers.github.io/compose.mk/cmk).  

This repository tracks some reusable plugins and modules that can extend core without cluttering it.

### Plugins vs Modules

On the back-end, modules and plugins have some shared and some diverging import mechanics, but see the [upstream docs](https://robot-wranglers.github.io/compose.mk/plugins/overview) for more details.  Here's the quick version:

**Plugins** are roughly domain-specific extensions to the core.  For example, `css.minifier/%` is defined in [docs.mk](docs.mk).  These are often *pure Makefile*, but using the `compose.mk` std-lib freely.  These are an opinionated take on workflows I find useful; they might be *too opinionated* for you to be interested in them!  

* For an example, see `css.minify/%` as part of [docs.mk](docs.mk)

**Modules** are larger and potentially *very significant extensions* to `compose.mk` and/or [CMK-lang](https://robot-wranglers.github.io/compose.mk/compiler) itself, and are potentially written in CMK too.  Since they are compiled just-in-time (and since that lowers them to pure Makefile), modules in CMK can be used *from* pure Makefiles.

* For an example, see `polyglot.golang.lambda` which does JIT compilation / execution of embedded golang source as part of [this module](polyglot.golang.cmk).

### Fork and Forget

See also the upstream [compose.mk quickstart](https://robot-wranglers.github.io/compose.mk/quickstart/#plugins-forks-versioning).

Grab individual tool-suite files, placing them inside a `your_project/.cmk` folder.  Then `include` them as usual in your project Makefile:

```Makefile
include compose.mk
include .cmk/py.mk # python project automation.
```

Or load them through the plugin verb, which resolves from `CMK_PLUGINS_DIR` (`.cmk` by default) and decides how to bind by file extension: a plain `.mk` plugin is `include`d verbatim (fast), while a `.cmk` plugin is JIT-compiled (lowered) then included -- so plugins can be written in CMK-Lang:

```Makefile
include compose.mk
$(call include.plugins, py.mk helpers.cmk) # .mk verbatim; .cmk lowered then included
```

Track the fork in your project repository, modify stuff if you want, and never look back.

### Git Submodules

You can also use this repository (or a fork of it) as a [git submodule](https://github.blog/open-source/git/working-with-submodules/) inside your main project repository.

```bash
# Add .cmk plugins to existing project
$ cd my-project

# Add this repository as a submodule (or your fork)
$ git submodule add git@github.com:robot-wranglers/.cmk.git
```

Sometimes the HTTPS version for the submodule works better, for example if you're running pip-install directly from your repository.

```bash
$ git submodule add https://github.com/Robot-Wranglers/.cmk.git
```

With the submodules approach, note that users and CI/CD must now use `--recursive` now when cloning parent!  

In github actions, the correct configuration for `jobs.my_job_name.steps` looks like this:

```yaml
- name: Checkout
  uses: actions/checkout@v4
  with:
    submodules: recursive
```

## Usage

Besides plugins, a stable version of the standard library for `compose.mk` is *also* tracked here.  You can use it, or overwrite it with a preferred version, or ignore it in favor of one you are tracking in your project root.. just make sure you adjust paths accordingly.  

For example, a rewrite of your project Makefile might look like this:

```Makefile

# Get standard lib from plugins folder too.
include .cmk/compose.mk

# py.mk: plugin for python project automation
include .cmk/py.mk

# or, include several plugins at once
$(call include.plugins, docs.mk actions.mk)

# or, include if available (strict=0 -> log + continue if missing)
$(call include.plugin, file=local.mk strict=0)
```

Note that `include.plugin` respects [`CMK_PLUGINS_DIR`](https://robot-wranglers.github.io/compose.mk/plugins/overview#where-plugins-are-found) (a `:`-separated search path; [reference](https://robot-wranglers.github.io/compose.mk/config#general-environment-variables)) to avoid hardcoded paths.  After `compose.mk` is included, this defaults to `.cmk/` if it's not already set.

The same thing in [CMK-lang](https://robot-wranglers.github.io/compose.mk/compiler), where the call-form sugar lowers to exactly the `$(call ..)` above:

```cmk
# Get standard lib from plugins folder too.
include .cmk/compose.mk

# py.mk: plugin for python project automation
include .cmk/py.mk

# or, include several plugins at once
cmk.include.plugins(docs.mk actions.mk)

# or, include if available (strict=0 -> log + continue if missing)
cmk.include.plugin(file=local.mk strict=0)
```

## Contents

These plugins are also covered upstream in the [Plugin Overview](https://robot-wranglers.github.io/compose.mk/plugins/overview), which explains how plugins bind/load and carries a generated index of this same set.

* [actions.mk](blob/main/actions.mk): Github actions helpers, mostly assuming that `gh` CLI is already available.
* [gitops.cmk](blob/main/gitops.cmk): Git-flavored project automation.  Provides `gitops.release`, a generic, project-agnostic release orchestrator: it runs a preflight (clean tree, not-diverged, tag-not-taken), dispatches every `gitops.release.*` helper (discovered across includes and run in lexical order, via `flux.star`), creates + pushes the `vX.Y.Z` tag, then polls any configured GitHub-Actions workflows (`gitops.watch`) to completion.  Add a release step from anywhere just by defining a `gitops.release.<name>:` target (see `py.mk`'s `gitops.release.py`).  Invoke with `version=<x.y.z>` (or `VERSION=`).  `gitops.rerelease` is a separate, explicit verb that *overwrites* an existing tag (force) -- for recovering a botched release only.  Configure via `gitops.{remote,tag_prefix,watch,watch.attempts,version_check,force}`.
* [doc.mk](blob/main/docs.mk): Documentation helpers, focusing especially on tools like mermaid, drawio, mkdocs, grip, and jinja2.
* [pdoc.mk](blob/main/pdoc.mk): Python documentation, focusing especially on [pdoc](https://pypi.org/project/pdoc/).
* [py.mk](blob/main/py.mk): Python related functionality, including stuff like pip and tox.  Also provides `gitops.release.py`, a build-only release step (PEP 517 `python -m build`) that respects `VERSION` and builds the project at `py.release.root` (skips cleanly when there's no python project there).
* [json.mk](blob/main/json.mk): JSON helpers (currently just validation).  See the [compose.mk docs for structured IO](https://robot-wranglers.github.io/compose.mk/standard-lib/#structured-io) for details about using `jq` and `jb`.
* [polyglot.golang.cmk](blob/main/polyglot.golang.cmk): Cross-build inline Go (CMK block-refs) in the dockerized golang toolchain, cache the binary per-host, and exec it.  Exposes `polyglot.golang.lambda(..)` (build-then-exec) and `declare.polyglot.golang(namespace=.. ..)` (wires run targets in one line).
* [tux.repl.cmk](blob/main/tux.repl.cmk): A reusable 3-region Bubbletea REPL (scrolling stream + multiline input + mode-line), cross-built via `polyglot.golang.cmk`.  Exposes the `tux.repl(read= eval= print= ..)` callable, `declare.tux.repl(namespace=.. ..)` (wires a REPL target in one line), the `tux.repl.run` target (the env-driven launch entrypoint REPL-as-execution-mode uses: compose.mk compiles this plugin + runs it), and `tux.repl/<t1,t2,..>` (the canonical no-pragma form for a PLAIN Makefile: `__main__: tux.repl/t1,t2,t3`).  See demos/cmk/repl.cmk + demos/cmk/overlay.cmk (`.cmk`) and demos/repl.mk (plain Makefile) for clients.
* [virtual-machine.cmk](blob/main/virtual-machine.cmk): The control-stack + `__vm__` CEK machine (the MAKE_CLI continuation as a control stack: peek/push/drop/goto + call/return/yield/fork over saved frames, plus an opt-in reflective environment via `declare.cmk.virtual_machine`).  Pure-make bodies wrapped as a `.cmk` plugin (JIT-compiled at include-time).  See demos/call_stack.mk, demos/vm.mk, demos/cmk/overlay.cmk.
* [fault.cmk](blob/main/fault.cmk): Typed faults (typed exceptions) built on the Events/channel stdlib.  A target raises with `fault.throw(<Type>, k=v ..)` (emit a typed event onto the `fault` channel, then fail); swallowed failures stay in-flight and are drained at-exit, routed to `fault/<Type>:` handlers by make's own rule precedence (no registry).  Exposes `fault.throw`, the `fault.guarded`/`@fault.guarded` inline catch (bridges a raw subprocess failure to a typed `SubprocessFault`), and owns the `fault.` vocabulary + `fault/` route verbatim.  Bootstrap-safe (best-effort emit never masks the real fault) and exits via `mk.exit.code`.  When loaded, core's `assert.env.var` transparently upgrades from `exit 39` to a typed `EnvVarUnset` fault.  See demos/fault.mk (plain Makefile) and demos/cmk/exceptions.cmk (the demo it was promoted from).

## See Also

See also [k8s-tools.git](https://github.com/Robot-Wranglers/k8s-tools) for kubernetes-specific automation.
