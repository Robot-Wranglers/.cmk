# io.fs.drop_in

!!! terminology "Drop-in dir"
    A **drop-in dir** (`<prefix>.d`) is a directory of independent "parts" that a single managed
    entrypoint fans out to: the `/etc/cron.d`, `conf.d`, `*.d` idiom. Each part is a small,
    self-contained behavior sitting behind one slot, and the entrypoint runs them all in order.

`io.fs.drop_in` packages that idiom as a single CMK plugin (`io.fs.drop_in.cmk`, contributing the
`io.fs.drop_in.*` targets to the core `io.fs` api) that installs/lists/removes the symlinks *and*
carries the runner script (a `define`) it materializes on demand. `gitops.hooks.*` is one consumer
(git hooks); any project that wants "many small, independent behaviors behind one slot" can use a
drop-in dir directly.

One file, two roles:
- **`.cmk/io.fs.drop_in.cmk`** - the plugin. The make-side convention (installs/lists/uninstalls the
  drop-in dir) *and* the source of the runtime runner, held in the `io.fs.drop_in.runner.script` define.
- **`.cmk/drop_in`** - the runtime runner (a shell script). Runs the parts. NOT committed: it is
  materialized from the plugin's define by `io.fs.drop_in.runner.ensure` (a prereq of install/run) into a
  stable, gitignored path, because a `<name>.d/` symlink points at it and git execs that symlink
  directly. Override the path with `io.fs.drop_in.runner`.

## Why not the `run-parts` binary

<hr class="section-rule lvl-3">

`drop_in` hand-rolls the loop rather than shelling out to `run-parts`, on purpose:
- **Portability**: `run-parts` is absent on macOS, a different implementation on busybox/Alpine, and
  inconsistently packaged on RHEL. Git hooks and dev tooling run on everyone's machine.
- **Stdin**: debianutils `run-parts` shares one stdin fd across sequentially-run scripts, so the
  first part that reads stdin drains it and the rest get nothing. `drop_in` buffers stdin once and
  **replays** it to every part, which hooks like `pre-push`/`pre-receive` require.
- **Semantics**: reliable fail-fast+veto (`--exit-on-error` is newer and not universal) and
  dot-in-filename tolerance (Debian `run-parts` silently skips `20-foo.sh` without `--regex`).

Nothing in `io.fs.drop_in` calls the `run-parts` binary; a drop-in dir is the *pattern*, and the
runner just runs its parts.

## The runner (`.cmk/drop_in`)

<hr class="section-rule lvl-3">

The runner lives as the `io.fs.drop_in.runner.script` define inside `io.fs.drop_in.cmk`; `io.fs.drop_in.runner.ensure`
materializes it to `${io.fs.drop_in.runner}` (default `.cmk/drop_in`, gitignored) and marks it executable.
Install and `io.fs.drop_in.run/%` depend on it, so the on-disk script is always present when needed. Once
written it is plain bash with no make/CMK dependency, so git can exec it (or the symlink at it)
directly.

Runs every executable part in a `.d` directory in lexical (`LC_ALL=C`) order. Each part receives the
forwarded **args** and a replay of the invocation's **stdin**; the first part to exit non-zero
aborts with that status (**fail-fast**). Parts that are dotfiles, or are not executable regular
files, are **skipped**.

Two modes, disambiguated by `argv[0]`'s basename:

- **Generic:** invoked as `drop_in`:
  ```sh
  drop_in <parts-dir> [args...]      # e.g. .cmk/drop_in path/to/build.d --flag
  ```
- **Git-hook adapter:** invoked under any other name - i.e. as a symlink named for the hook, such
  as `.git/hooks/pre-commit`. The parts dir is derived as
  `<toplevel>/${DROP_IN_SRC:-hooks}/<basename $0>.d` via `git rev-parse --show-toplevel`. Everything
  the loop needs is derived here, so there is no script-to-script path lookup (which would need
  macOS-missing `readlink -f`).

Details worth knowing:
- **Stdin + tty guard**: stdin is buffered once and replayed to each part. When stdin is a
  **terminal** (e.g. `pre-commit` during an interactive `git commit`) it is *not* drained - a bare
  `cat` would block on an EOF that never comes and hang the commit - so the buffer is left empty. A
  part that needs to prompt can open `/dev/tty` itself.
- **`DROP_IN_SRC`**: only relevant to git-hook mode, and only if a consumer uses a non-default source
  dir; export it so the runner finds the parts at fire time.

## The convention (`.cmk/io.fs.drop_in.cmk`)

<hr class="section-rule lvl-3">

A CMK plugin. Import it and drive it with three config vars:

| variable       | meaning                                              | default     |
| -------------- | ---------------------------------------------------- | ----------- |
| `io.fs.drop_in.src`     | source dir holding files and `<name>.d/` dirs        | (required)  |
| `io.fs.drop_in.linkdir` | dir the managed symlinks are installed into          | (required)  |
| `io.fs.drop_in.runner`  | where the runner is materialized + `<name>.d/` links at | `.cmk/drop_in` |

Two entry shapes in `io.fs.drop_in.src` (the registry is just its contents):
- a **regular file** `<src>/<name>` -> symlinked 1:1 at `<linkdir>/<name>`.
- a **directory** `<src>/<name>.d/` -> `<linkdir>/<name>` is symlinked at `io.fs.drop_in.runner`.

All symlinks are **absolute** (they survive worktrees and relative-path moves), and install makes
the runner and every part executable.

### Targets

<hr class="section-rule lvl-3">

```sh
make io.fs.drop_in.install    io.fs.drop_in.src=<dir> io.fs.drop_in.linkdir=<dir>   # install files 1:1, .d dirs via the runner
make io.fs.drop_in.uninstall  io.fs.drop_in.src=<dir> io.fs.drop_in.linkdir=<dir>   # remove only the symlinks we own
make io.fs.drop_in.list       io.fs.drop_in.src=<dir> io.fs.drop_in.linkdir=<dir>   # report install state (see below)
make io.fs.drop_in.run/<dir>                                      # run a .d dir now (non-git consumers)
make io.fs.drop_in.runner.ensure                                  # materialize the runner script (install/run do this for you)
```

### `io.fs.drop_in.list` states

<hr class="section-rule lvl-3">

State is read by RESOLVING each symlink (a portable single-hop resolver, since `drop_in` only creates
single-level absolute links), never guessed from `-L`:

| state       | meaning                                                                    |
| ----------- | -------------------------------------------------------------------------- |
| `linked`    | a symlink we own, resolving to the expected target (source, or runner)     |
| `stale`     | a symlink resolving SOMEWHERE ELSE (the actual target is shown)            |
| `unmanaged` | a real file we did not create and will not touch                           |
| `absent`    | nothing installed for this name yet                                        |

A `<name>.d` entry is shown as a `(drop_in)` header followed by its ordered parts, each tagged `run`
or `skipped`. A plain entry flags its own executable bit. After the rows, a scan for ORPHANS
(symlinks we own whose source is gone) and a one-line tally.

## Example: a consumer plugin

<hr class="section-rule lvl-3">

`gitops.hooks.*` is the reference consumer. Its `gitops.hooks.init` is primarily reflection-based, but
it *also* delegates here to install any hand-authored parts under `${gitops.hooks.src}`, pinning the
link dir to the repo's git-hooks dir so it is worktree-aware:

```make
gitops.hooks.init: assert.tool.required/git
	hd <- git rev-parse --git-path hooks
	if [ -d "${gitops.hooks.src}" ]; then ${make} io.fs.drop_in.install io.fs.drop_in.src=${gitops.hooks.src} io.fs.drop_in.linkdir=$${hd} io.fs.drop_in.runner=${gitops.hooks.dispatch}; fi
```

To split one git hook into independent parts:

```
hooks/
  pre-commit.d/
    10-nbstripout
    20-gitleaks
```

## Portability notes

<hr class="section-rule lvl-3">

- No `run-parts` binary (see above).
- No `readlink -f` (absent on macOS): the runner derives everything from `$0`/git, and `io.fs.drop_in.list`
  uses a `cd`/`pwd -P`/single-hop-`readlink` resolver.
- POSIX-ish shell throughout; the runner is bash (for `mktemp`/`trap` ergonomics) with no GNU-only
  flags.
