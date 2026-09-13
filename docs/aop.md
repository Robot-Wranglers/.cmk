# aop.cmk

`aop.cmk` **ships the reusable aspects for target advice**: the lifecycle loggers and the catch
that every decorated target would otherwise hand-roll.  A library module (no `__main__`); import
it with `import aop`, or `$(call include.plugins, aop.cmk)` from a plain Makefile.

The compiler supplies the mechanism, and this module supplies the parts.  For the advice kinds
themselves, the decorator mark, and the worked demo, see
[Contracts / AOP](/compose.mk/cmk/compiler/#contracts-aop).

## Public API

<hr class="section-rule lvl-3">

| Macro | Kind | Role |
| --- | --- | --- |
| `aop.enter` | `before` | the target is starting |
| `aop.returned` | `after_return` | the body succeeded |
| `aop.finally` | `after` | the body finished either way |
| `aop.caught` | `after_throw` | the body failed, reported with its exit code |
| `aop.tag(<label>)` | any | a labeled marker, for naming the concern at the use site |

## Usage

<hr class="section-rule lvl-3">

Write the mark at the use site.  A companion `<name>.advice := <kind>` assignment is read from
the source text of the file being compiled, so a default declared inside this module is not seen
while your file compiles: a bare decorator on an imported aspect is `before` advice.

```Makefile
import log, aop

@aop.enter
@aop.caught ::: after_throw
@aop.finally ::: after
charge:
    risky-command
```

Two cautions.  `aop.caught` returns cleanly, so it **swallows** the failure it catches; pair it
with [`fault.guarded`](/compose.mk/plugins/faults) instead when the failure should be re-thrown as
a typed fault.  And `aop.finally` is the recipe's last command, so it supplies the target's exit
code and a failing body it follows is reported as a success.

## See also

<hr class="section-rule lvl-3">

* [Contracts / AOP](/compose.mk/cmk/compiler/#contracts-aop): the decorator mark and advice kinds.
* [Concepts: Contracts / AOP](/compose.mk/cmk/concepts/#contracts-aop): where advice sits among the other CMK constructs.
* [Faults](/compose.mk/plugins/faults): typed exceptions, and the re-throwing catch.
