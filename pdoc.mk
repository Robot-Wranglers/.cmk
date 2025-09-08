# pdoc.mk: Populates `pdocs.*` namespace with python documentation tools.
#
# This covers especially things related to markdown, mkdocs, pdoc, and jinja.
# See `docs.mk` for something less about python packages or apis.
#
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

pdocs.args=--no-search -d markdown 
pdocs.theme_dir=docs/theme/pdoc/
pdocs.output_dir=docs/api

pdoc/%: mk.require.tool/pdoc
	@# Runs `pdoc` for the given python module.
	set -x \
	&& ls ${pdocs.theme_dir} \
	&& export SITE_RELATIVE_URL=/${mkdocs.site_name} \
	&& pdoc ${*} ${pdocs.args} \
		-t ${pdocs.theme_dir} \
		-o ${pdocs.output_dir} \
		--logo "$${PDOCS_LOGO:-$${SITE_RELATIVE_URL}/img/logo.png}"
