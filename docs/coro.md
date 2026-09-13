# coro.cmk

`coro.cmk` **ships asymmetric coroutines over the reflective virtual machine**: a resume and
yield pair, a status field, and the transfer verbs between them. A library module (no
`__main__`); import it with `import coro`, or `$(call include.plugins, coro.cmk)` from a plain
Makefile.

A coroutine is a set of step targets named for it. Control enters at its `enter` step, and every
transfer names its destination, so there is no manifest and nothing depends on declaration order.
A step reads its own identity off the target name.

## Public API

<hr class="section-rule lvl-3">

| Macro | Role |
| --- | --- |
| `coro.resume(<co>)` | enter a coroutine at its saved label, or at `enter` the first time |
| `coro.resume.then(<co>, <step>)` | resume, and come back to a named step rather than to this one |
| `coro.yield(<val>)` | suspend, publish a value, resume at this same step |
| `coro.yield.to(<step>, <val>)` | suspend, publish, and name where the next resume lands |
| `coro.goto(<step>)` | move to another step of this coroutine, keeping control |
| `coro.exit(<val>)` | retire, publish, hand control back |
| `coro.status(<co>)` | one of `suspended`, `running`, `normal`, `dead` |
| `coro.dead?(<co>)` | predicate, for a driver loop's condition |
| `@coro.step` | mark a step, asserting it belongs to the running coroutine |

## Usage

<hr class="section-rule lvl-3">

An importing program declares the hydration stage and the reflective environment itself, since
both shape that program's own recipes:

```Makefile
import log
import virtual-machine.cmk as vm, flat=1
import coro
$(call vm.reflect, exclude=MAKE CMK MFLAGS kwargs_ CONTROL_STACK)

@coro.step
producer.enter:
    export n="$${n:-1}"
    cmk.coro.yield(item-$${n})
```

The resume label, status, resumer and resume count live in the reflective environment, one slot
family per coroutine. That environment is what survives a transfer, so anything a step needs on
its next resume must be exported rather than held in a shell variable.

`max_resumes` caps resumes per coroutine, default 12. A label that stops advancing would
otherwise spin forever, because an endless loop produces no output rather than wrong output.

## What this takes from Lua

<hr class="section-rule lvl-3">

The API shape: asymmetric `resume` and `yield`, values published in both directions, and an
explicit four-state `status`. Lua's is the smallest widely known coroutine interface, and the
reference implementation is short enough to read:

* [`lcorolib.c`](https://www.lua.org/source/5.4/lcorolib.c.html) is the library itself. The
  `statname` table there is the authority for the status set, and the reason `dead` also covers
  an errored coroutine.
* [`ldo.c`](https://www.lua.org/source/5.4/ldo.c.html) holds the mechanics: `lua_resume` and
  `lua_yieldk`, plus the internal `resume` that separates a first entry from a resumption, and
  the continuation unrolling a yield leaves behind.
* [Reference manual §6.2](https://www.lua.org/manual/5.4/manual.html#6.2) and
  [Programming in Lua ch. 9](https://www.lua.org/pil/9.html) are the prose.

One borrowed semantic is easy to get backwards. Lua's `yield` **resumes in place**: a yield
inside a loop comes back into that loop. That is `coro.yield` here. Advancing to a different step
is `coro.yield.to`, which has no Lua analogue.

## What this takes from protothreads

<hr class="section-rule lvl-3">

The implementation strategy, and nothing else. Protothreads (Dunkels, Schmidt, Voigt and Ali,
SenSys 2006) resume by re-entering a function and dispatching on a saved position, held as a
line number in a two-byte local continuation. That is the same move made here, with a target
standing in for the line number, because a make recipe has no resumable position inside it.

What is **not** borrowed: the `switch`-based expansion built on Duff's device, the wait-until
vocabulary, and the memory-footprint claims. None of that transfers to a language whose
addressable units are targets.

The more useful borrowing is a warning. Section 5.3.1 of that paper records the limitation that
automatic variables are not preserved across a blocking wait, and section 7 calls it the biggest
problem found in two years of production use. Their recommended workaround for reentrant
protothreads is an explicit state object.

**This design does not inherit that limitation, because the reflective environment already is
that state object.** Per-coroutine state survives every suspension by construction. The cost is
that it must be exported to get there, which is the same discipline under a different name, and a
lint rule for it is a promotion-time todo.

## Stackless and stackful

<hr class="section-rule lvl-3">

The distinction decides where a coroutine may suspend.

**Stackful** coroutines own a stack and a position, so a yield can happen at any call depth. Lua
is stackful: its manual notes that a yield may occur inside nested function calls rather than
only in the coroutine's main function. Greenlet is stackful in the same sense, describing a
greenlet as a small stack of frames, and it is worth noting that its switching is not purely
symmetric either: a greenlet has a parent, and the parent is where execution continues when a
greenlet dies. That parent is the same idea as the resumer slot here.

**Stackless** coroutines have no separate stack, so suspension is limited to points the compiler
can see in the top frame. The protothreads paper puts itself in this family, observing that
protothreads are similar to stackless coroutines much as cooperative multithreading is similar to
stackful ones.

This module is stackless, and more restrictively so than either. A suspension point is a whole
step, not a position inside one, because a recipe line cannot be re-entered part way through.
That restriction is what makes the saved label sufficient: there is no intra-step position to
lose.

## Why not async and await

<hr class="section-rule lvl-3">

An event-loop model with `await` points was considered and rejected. The objection is the one Bob
Nystrom sets out in
[What Color is Your Function?](https://journal.stuffwithstuff.com/2015/02/01/what-color-is-your-function/),
whose rule is that you can only call a red function from within another red function. Asynchrony
propagates backwards through every caller, and the codebase splits in two.

Four reasons it fits this setting especially badly:

* **There is no signature to colour.** A target has no type and no declared arity, so the
  compiler has nowhere to record that one target is awaitable and another is not.
* **The rule could not be enforced.** Marking a target would fall to a decorator, and no advice
  kind can learn the name of the target it decorates; the compiler fixes a decorator's argument
  text before the target line is read.
* **The scheduler already exists.** Transfers re-dispatch flat through the supervisor's
  trampoline. An await layer would be a second scheduler over the first.
* **The subject is different.** Async and await exist to multiplex waiting on input and output.
  These coroutines exist for explicit control transfer, and the two goals do not need the same
  machinery.

Nystrom's essay makes the same point from the other side, naming Lua among the languages that
escape the problem by giving each coroutine its own callstack. Since this module is stackless it
cannot claim that escape outright; what it can do is keep the colour out of the call signature,
because a resume is an ordinary macro call from an ordinary recipe.

## See also

<hr class="section-rule lvl-3">

* [`virtual-machine.cmk`](/compose.mk/modules/virtual-machine): the trampoline, the control stack,
  and the reflective environment this builds on.
* [Contracts / AOP](/compose.mk/cmk/compiler/#contracts-aop): the decorator mark that
  `@coro.step` uses.
