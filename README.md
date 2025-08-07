## CMK Plugins / Extensions
----------------------------------------

[compose.mk](http://robot-wranglers.github.io/compose.mk) is a framework for writing domain-agnostic project automation that runs anywhere and uses any programming language.

This is an opinionated starter kit of plugins / extensions for more specific types of projects and tasks.

## Installation
----------------------------------------

See also the upstream [compose.mk quickstart](https://robot-wranglers.github.io/compose.mk/quickstart/)

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

# Or use your fork
$ git submodule add git@github.com:mattvonrocketstein/.cmk.git
```

*(Note: Users and CI/CD must now use `--recursive` now when cloning parent!)*

## Usage
----------------------------------------

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

To avoid hardcoded paths, you can also set or use the environment variable `CMK_PLUGINS_DIR`.  After `compose.mk` is included, this defaults to `.cmk/` if it's not already set.