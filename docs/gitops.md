# gitops.cmk

Git-flavored project automation: a pure-CMK plugin/module providing a release orchestrator
(`gitops.release`) and a registry-free git-hook installer (`gitops.hooks.*`).

It is a LIBRARY (no `__main__`): the shebang compiles it as a parse check; import it to use it:

```make
$(call include.plugins, gitops.cmk)
```

## Usage

<hr class="section-rule lvl-3">

```sh
version=1.2.3 make gitops.release           # cut a release (LIVE: tags + pushes)
version=1.2.3 make gitops.rerelease         # re-tag + force-push an existing version
make gitops.help                            # list the gitops.* namespace (auto-generated at import)
version=1.2.3 make gitops.preflight         # just the checks (non-destructive)

# declare gitops.hooks.<type>/<name> targets in your Makefile, then:
make gitops.hooks.init                      # wire the managed git hooks (run by `init`)
make gitops.hooks.list                      # per type: registered targets + wired state
make gitops.hooks.uninstall                 # remove the managed scripts (hand-written hooks stay)
make flux.gitops.hook/gitleaks              # run one registered hook by bare name
make gitops.hooks.fire/precommit            # dry-fire every registered pre-commit target
```

## Release orchestrator

<hr class="section-rule lvl-3">

`gitops.release` is a generic, project-agnostic release ORCHESTRATOR. It runs a preflight, then
every `gitops.release.*` HELPER (defined here or in any other included file/plugin) in lexical
order, then creates and pushes the release tag, then watches any configured GitHub-Actions
workflows to completion.

There is no registry to maintain: the live make target-table IS the registry, so adding a release
step from anywhere is just defining a `gitops.release.<name>:` target (see `py.mk`'s
`gitops.release.py`). Discovery/sort/run of the helpers is delegated to the stdlib's `flux.star`,
which enumerates matching targets across includes, emits them lexically sorted, and runs each. The
orchestrator's own phases are PRIVATE (`_gitops.release.*`) so they are NOT discovered as helpers.

`gitops.release` is FULLY LIVE: it creates and PUSHES a real annotated tag and triggers CI.
`gitops.rerelease` OVERWRITES an existing tag (force) -- intentionally a separate, explicit verb,
because tags should be immutable; reach for it only to recover a botched release.

### Lifecycle hooks (`release/OK`, `release/FAIL`)

After the chain runs, `gitops.release` fires a **reflection-gated** lifecycle hook: `release/OK` on
full success, `release/FAIL` on any failure (the original failure code is preserved, so the release
still exits non-zero). Opt in by declaring the target -- same registry-free convention as everything
else:

```make
gitops.hooks.release/OK:;   @./notify.sh "released $(gitops.tag)"
gitops.hooks.release/FAIL:; @./notify.sh "release FAILED"
```

`release` is a *lifecycle* pseudo-type, not a git hook, so it is deliberately absent from
[`gitops.hooks.types`](#config): `gitops.hooks.init` never wires it, and it fires only from the
release flow. Dispatch always logs -- a green check `✔ registered` when the hook exists (then it
runs), or a yellow `no hook found` when nothing is registered (a no-op). The generic dispatcher is
`make gitops.hooks.try/<type>/<name>` (e.g. `gitops.hooks.try/release/OK`), reusable for any
reflection-gated hook point.

## Hooks manager

<hr class="section-rule lvl-3">

`gitops.hooks.*` is a **reflection-based** git-hook manager: the live make target-table is the
registry, so there are no hook files to author. Declaring a target named `gitops.hooks.<type>/<name>`
registers it -- exactly the pattern `gitops.release` uses for its `gitops.release.*` helpers. The
`<type>` segment names a git hook (see [`gitops.hooks.types`](#config)): `precommit` -> `pre-commit`,
`prepush` -> `pre-push`, and so on.

```make
# in your project Makefile -- declaring the target IS the registration:
gitops.hooks.precommit/gitleaks: gitops.gitleaks           # reuse the shipped secret-scan
gitops.hooks.precommit/lint:; @echo linting && ./lint.sh   # or an inline recipe
gitops.hooks.prepush/test: test                            # a prereq onto an existing target
```

`make gitops.hooks.init` reflects over those declarations and, for every hook type that has at least
one registration, writes a small **managed** script at `.git/hooks/<git-hook>` (resolved via `git
rev-parse --git-path hooks`, so worktrees work too). When git fires the hook the script re-enters
`make gitops.hooks.fire/<type>`, which runs each registered target in lexical order, **fail-fast** (a
non-zero target aborts the git action). It is safe to re-run: a type whose registrations were all
removed has its stale managed script cleaned up, and a hand-written hook of the same name is never
touched. Adding another target of an *existing* type needs no re-init (the fired hook reflects live);
re-run `init` only to wire up a *new* hook type.

* `make gitops.hooks.init` -- wire/refresh the managed git hooks (idempotent; run from `init`).
* `make gitops.hooks.uninstall` -- remove the managed scripts (only ours; hand-written hooks stay).
* `make gitops.hooks.list` -- per type, the registered targets and whether the hook is wired.
* `make flux.gitops.hook/<name>` -- run one registered hook by bare name (the first
  `gitops.hooks.<type>/<name>` found, precommit preferred); a `flux` verb contributed via `open flux`,
  handy to fire a hook by hand. `make gitops.hooks.fire/<type>` runs a whole type.

### `gitops.gitleaks`

A reusable pre-commit body: it scans staged changes for secrets with
[gitleaks](https://github.com/gitleaks/gitleaks) in docker (`protect --staged`), delegating the run
to the stdlib's `docker.run.sh`. It **requires docker** (asserted via `assert.tool.required` with a
failure *hint* pointing at the `git commit --no-verify` bypass), so a docker-less machine must skip
the scan that way. Override the image with `gitops.gitleaks.image` (a `GITLEAKS_IMAGE` env var still
wins at runtime). Register it as above with `gitops.hooks.precommit/gitleaks: gitops.gitleaks`.

(`assert.tool.required` / `assert.tool.available` take an optional 2nd **hint** arg via the macro /
callform form -- `cmk.assert.tool.required(<tool>, <hint>)` -- shown as a `hint:` line when the tool
is missing. The `/%` prereq form can't carry one, since a prereq is a single whitespace-split word.)

### Hand-authored parts (`io.fs.drop_in`)

Alongside the reflected hooks, a `${gitops.hooks.src}` dir (default `hooks/`) of hand-authored parts
is still installed when present -- a thin instantiation of the generic **drop-in dir**
([`io.fs.drop_in`](io.fs.drop_in.md), the `<prefix>.d` engine): a `hooks/<name>.d/` drop-in dir
installs the shared runner. Use this for file-based parts you would rather not express as targets;
keep a given git hook name to *one* mechanism (reflection or files), not both. If you set a
non-default `gitops.hooks.src`, also export `DROP_IN_SRC` to the same value so the runner finds the
parts when git fires the hook.

## Config

<hr class="section-rule lvl-3">

Override from the client project.

| variable                | meaning                                       | default            |
| ----------------------- | --------------------------------------------- | ------------------ |
| `gitops.remote`         | remote to push to                             | `origin`           |
| `gitops.tag_prefix`     | tag = `<prefix><VERSION>`                      | `v`                |
| `gitops.watch`          | space-separated CI workflow files to poll     | (none)             |
| `gitops.watch.attempts` | poll attempts for a run to register           | `12`               |
| `gitops.version_check`  | `0` disables the semver sanity check          | `1`                |
| `gitops.force`          | `1` overwrites an existing tag (set by rerelease) | `0`            |
| `gitops.hooks.types`    | `<segment>:<git-hook>` map reflection scans    | `precommit:pre-commit ...` |
| `gitops.hooks.make`     | make entrypoint the managed git-hook script re-enters | `make`      |
| `gitops.gitleaks.image` | docker image `gitops.gitleaks` runs           | `zricethezav/gitleaks:v8.18.4` |
| `gitops.hooks.src`      | optional dir of hand-authored `io.fs.drop_in` parts to also install | `hooks` |
| `gitops.hooks.dispatch` | the `drop_in` runner `<name>.d/` hooks link at (alias for `io.fs.drop_in.runner`) | `.cmk/drop_in` |
| `gitops.env_file`       | optional dotenv sourced by `gh`-shelling recipes | (unset)         |

`VERSION=` and `version=` are both accepted (a case-insensitive alias for the release version).

`gitops.env_file`: recipes that shell out to `gh` do not manage its auth. A project pointing at a
private repo typically keeps a scoped `GH_TOKEN` in a gitignored `.env`; without it `gh` falls back
to the host keyring account, which may lack repo access and make a live CI run look absent ("no run
found"). Unset by default; opt in with `gitops.env_file := .env`. It is sourced INSIDE the recipe
shell (`set -a` exports each assignment) so the token never enters make's variable space.
