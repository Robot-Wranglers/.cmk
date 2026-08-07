# beam.loader.mk -- the trampoline=beam takeover target (@file:goal).

# Core selects trampoline=beam by execing the beam.super.tramp target,

# forwarding __argv__ (goals) and CMK_TRAMP_MK (the compiled program

# make command). Nesting is handled upstream by core's

# CMK_TRAMPOLINE_ACTIVE guard, so this target is always a takeover:

# run the Elixir beam-tramp loop when elixir present, else JIT-build

# beam.node and re-exec the run inside it (container elixir drives).

_bt_dir := $(dir $(lastword $(MAKEFILE_LIST)))

beam.super.tramp:
	@if command -v elixir >/dev/null 2>&1; then \
	  CMK_TRAMP_MK='$(CMK_TRAMP_MK)' exec elixir '$(_bt_dir)beam-tramp.exs' $(__argv__); \
	else \
	  CMK_SUPERVISOR=0 CMK_INTERNAL=1 $(CMK_TRAMP_MK) beam.node.build >&2 || { printf 'beam: cannot build beam.node (does the program import platform.beam?)\n' >&2; exit 1; }; \
	  _src="$$(cd '$(_bt_dir)' && pwd)"; \
	  exec docker run --rm -e CMK_PLUGINS_DIR=.cmk -e CMK_TRAMPOLINE_ACTIVE=1 -e CMK_TRAMP_CHOOSE -e CMK_TRAMP_TRACE \
	    -v "$$_src/beam-tramp.exs":/cmk-beam-tramp.exs:ro \
	    -v "$${DOCKER_HOST_WORKSPACE:-$$(pwd)}":/workspace -w /workspace compose.mk:beam.node \
	    bash -c "CMK_TRAMP_MK='$(CMK_TRAMP_MK)' elixir /cmk-beam-tramp.exs $(__argv__)"; \
	fi
