## CMK Plugins / Extensions

[compose.mk](http://robot-wranglers.github.io/compose.mk) is a standard library for `make` that supports docker, polyglots, and domain-agnostic project automation.

This is an opinionated starter kit of plugins / extensions for more specific types of projects automation tasks.  They are perhaps *too opinionated* for you to be interested in them!, but they do demonstrate one want to integrate projects with `compose.mk` and to extend that more basic functionality.

See also [k8s-tools.git](https://github.com/Robot-Wranglers/k8s-tools) for kubernetes-specific automation.

## Installation

See also the upstream [compose.mk quickstart](https://robot-wranglers.github.io/compose.mk/quickstart/#plugins-forks-versioning).

### Fork and Forget

Grab individual tool-suite files, placing them inside a `your_project/.cmk` folder.  Then `include` them as usual in your project Makefile:

```Makefile
include compose.mk
include .cmk/py.mk # python project automation.
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

Besides plugins, a stable version of the standard library for `compose.mk` is *also* tracked in the plugin folder.  You can use it, or overwrite it with a preferred version, or ignore it in favor of one you are tracking in your project root.. just make sure you adjust paths accordingly.  

For example, a rewrite of your project Makefile might look like this:

```Makefile

# Get standard lib from plugins folder too.
include .cmk/compose.mk

# py.mk: plugin for python project automation
include .cmk/py.mk

# or, include several plugins at once
$(call mk.import.plugins, docs.mk actions.mk)

# or, include if available (no error if missing)
$(call mk.import.plugin.maybe, site.mk local.mk)
```

Note that `mk.import.plugin` respects `CMK_PLUGIN_DIR` to avoid hardcoded paths.  After `compose.mk` is included, this defaults to `.cmk/` if it's not already set.

## Contents

* [actions.mk](blob/main/actions.mk): Github actions helpers, mostly assuming that `gh` CLI is already available.
* [doc.mk](blob/main/pdoc.mk): Documentation helpers, focusing especially on mermaid, drawio, mkdocs, and jinja2 by way of [pynchon](https://github.com/robot-wranglers/pynchon).
* [pdoc.mk](blob/main/pdoc.mk): Python documentation, focusing especially on [pdoc](https://pypi.org/project/pdoc/).
* [py.mk](blob/main/py.mk): Python related functionality, including stuff like pip and tox.
