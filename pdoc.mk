#!/usr/bin/env -S ./compose.mk cmk compile
# pdoc.mk: Provides the `pdoc/<module>` target (+ `pdoc.*` config) for python API docs.
#
# cmk_pragma ::: { "kind": "plugin" } :::
#
# This covers especially things related to markdown, mkdocs, pdoc, and jinja.
# See `docs.mk` for something less about python packages or apis.
#
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

pdoc.args=--no-search -d markdown
pdoc.theme_dir=docs/theme/pdoc/
pdoc.output_dir=docs/api

# Local fallback so `pdoc/%` works standalone (docs.mk defines this too; `?=` yields to it
# when both plugins are loaded, regardless of include order).
mkdocs.site_name ?= `cat mkdocs.yml | ${yq} -r .site_name`

pdoc/%: assert.tool.required/pdoc
	@# Runs `pdoc` for the given python module.
	set -x \
	&& ls ${pdoc.theme_dir} \
	&& export SITE_RELATIVE_URL=/${mkdocs.site_name} \
	&& pdoc ${*} ${pdoc.args} \
		-t ${pdoc.theme_dir} \
		-o ${pdoc.output_dir} \
		--logo "$${PDOCS_LOGO:-$${SITE_RELATIVE_URL}/img/logo.png}"
