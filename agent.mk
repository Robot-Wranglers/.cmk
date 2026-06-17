# agent.mk: the `declare.agent` actor layer, extracted from core as an opt-in plugin.
#
# An AGENT is a channel taken to its logical conclusion (Elixir-style Agent): a named
# JSON-array datastore with a lifecycle (start/cast/stop), query/transform/drain, and an
# actor run-loop.  Agents build ON channels, so this plugin needs the core channel layer
# (`declare.channel`, which stays in compose.mk) -- load it AFTER `include compose.mk`:
#
#   include compose.mk
#   $(call include.plugins, agent.mk)
#   $(call declare.agent, namespace=<ns>)
#
# Surface: see `$(call declare.agent, [namespace=<ns>] [chan_init_data=<def>])` below.
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# AGENTS -- a channel taken to its logical conclusion (Elixir-style Agent).  An agent
# IS a channel (which IS a stack), so `declare.agent` just constructs the channel and
# adds Elixir-flavored lifecycle aliases on top: <n>.start (== initialize), <n>.cast
# (fire-and-forget emit), <n>.stop (== purge).  Query/transform (filter/count/update)
# and consume (drain) already exist on the channel.
#
# An agent has its own NAMESPACE; the other knobs derive from it (`namespace=` is the one
# declaration kwarg -- the backing channel is always `<namespace>.inbox`):
#   namespace       the agent's namespace                       (default: `self`)
#   chan_init_data  a JSON-array `define` to seed the channel   (default: `<namespace>.inbox.state`)
# The seed is OPTIONAL: a missing `<chan>.state` def is skipped (logged), not an error.
# USAGE: $(call declare.agent, [namespace=<ns>] [chan_init_data=<def>]).
io.agent.namespace=$(or $(patsubst namespace=%,%,$(filter namespace=%,$(1))),self)
io.agent.chan=$(call io.agent.namespace,$(1)).inbox
io.agent.chan_init_data=$(or $(patsubst chan_init_data=%,%,$(filter chan_init_data=%,$(1))),$(call io.agent.chan,$(1)).state)
declare.agent=$(call declare.channel,namespace=$(call io.agent.chan,$(1)) init_data=$(call io.agent.chan_init_data,$(1)))$(eval $(call _declare.agent,$(call io.agent.namespace,$(1)),$(call io.agent.chan,$(1))))
# _declare.agent($(1)=namespace, $(2)=chan): the ACTOR layer.  Adds lifecycle
# (start/stop/cast) + the run-LOOP step (the actor heartbeat -- NOT a channel op:
# a bare channel is a passive bus, an agent is the active actor), then lifts the WHOLE
# interface up from `<chan>.<op>` to the bare namespace `<ns>.<op>`.
define _declare.agent
$(2).start: $(2).initialize
	@# Agent.start_link: seed the agent's state (alias of `$(2).initialize`).
$(2).stop: $(2).purge
	@# Agent.stop: drop the agent's backing store (alias of `$(2).purge`).
$(2).cast:
	@# Agent.cast: fire-and-forget append of one event (kwargs on stdin) -- emit.
	$$(call $(2).emit, `$${stream.stdin.maybe}`)
$(2).loop/%:
	@# Actor step: run the named target with stdin detached (e.g. `<ns>.loop(<ns>.drain)`).
	@# Timing is the CALLER's job -- prepend a `flux.after/<secs>,<target>` preamble for a
	@# blocking tick (or `flux.delay` to fire it in the background).
	$$(call log.trace, $${@})
	$${make} $${*} </dev/null
# Inherit the channel interface -- `$(1).<op>` forwards to `$(2).<op>` (so e.g.
# `<ns>.filter(..)`/`<ns>.cast[..]`/`<ns>.count`/`<ns>.start` work with no `.inbox.`).
# PER-OP aliases (not a `$(1).%` catch-all: that would also match the channel's own
# `$(2).*` targets -- supplying bogus recipes to their prereq-only rules -> recursion).
# NO-ARG / inline-stdin ops:
$(foreach _aop,start stop count cast drain emit push pop filter update dispatch.by_type,$(1).$(_aop):; $${make} $(2).$(_aop)${nl})
# PARAMETRIC ops -- one slash-bearing pattern per op (a slash-LESS pattern would get
# dir-stripped by make and never match `<ns>.filter/a,b`):
$(foreach _aop,filter filter.jq filter.in_place update jq loop emit.type dispatch.drain,$(1).$(_aop)/%:; $${make} $(2).$(_aop)/$${*}${nl})
# pool: run <size> concurrent `$(1).drain` workers through the bounded `flux.pool`.  NOT
# a channel-op forward (so not in the foreach above).  Worker count is dynamic, so the
# list is shell-built and dispatched via the flux.pool TARGET form.
# CAVEAT: LOSSY under concurrency -- multiple drains pop the same backing stack with no
# mutual exclusion (per-stack locking is deferred); the runtime `log` warns.
$(1).pool/%:; $$(call log, ${yellow}$(1).pool${no_ansi} ${sep} ${dim}concurrent drain is ${red}lossy${no_ansi_dim} until per-stack locking lands) ; size="$${*}" && workers=`yes $(1).drain | head -n $$$${size} | $${stream.nl.to.comma}` && $${make} flux.pool/$$$${size},$$$${workers}
# Inherit dispatch routing: events drained to `$(2)/<type>` forward to handlers the
# user defines at the bare `$(1)/<type>` (an explicit `$(2)/<type>:` still wins).
$(2)/%:; $${make} $(1)/$${*} </dev/null
endef
