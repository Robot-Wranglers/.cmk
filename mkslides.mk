# Markdown slides support via mkslides and revealjs 
# See also: https://github.com/MartenBE/mkslides and https://revealjs.com/
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

mkslides.output_dir?=${docs.root}/slides
mkslides.input_dir?=slides
mkslides.config?=mkslides.yml

export MKSLIDES_PORT?=9010

define Dockerfile.mkslides
FROM python:3.12-bookworm
RUN pip install --break-system-packages mkslides
endef

$(call docker.import.def, def=mkslides namespace=docs._slides)

# FIXME: promote to compose.mk?
define _mk.require.file_from_var
$(call log.part1, ${GLYPH_MK} ${@} ${sep} ${1}) \
&& ls ${$(strip ${1})} ${stream.obliviate} \
&& ( $(call log.part2, ${green}${$(strip ${1})}) && $(strip $(if $(filter undefined,$(origin 2)),true,${2})) ) \
|| ( $(call log.part2, ${red}${$(strip ${1})} missing); exit 42) 
endef

docs.slides.init: docs._slides.build
	@# Initialize mkdocs container if necessary
docs.slides.serve: mkslides.serve
	@# Starts containerized mkslides server on given MKSLIDES_PORT
	
docs.slides docs.slides.build:; quiet=1 ${make} docs.slides.init docs._slides.dispatch/mkslides.build
	@#

mkslides.require.conf:
	@# Assert that mkslides configuration is available
	$(call _mk.require.file_from_var, mkslides.config)

mkslides.build: mkslides.build/${mkslides.input_dir}
	@# Build slides from markdown using default `mkslides.input_dir`

mkslides.build/%: mkslides.require.conf
	@# Build slides from markdown in the file or folder
	$(call _mk.require.file_from_var, \
		mkslides.input_dir, \
		set -x && mkslides build -f ${mkslides.config} --site-dir ${mkslides.output_dir} ${*})

mkslides.serve: mkslides.require.conf
	@# Starts mkslides server on given MKSLIDES_PORT
	$(call log.target, serving ${sep} port=$${MKSLIDES_PORT})
	docker_args="-p $${MKSLIDES_PORT}:$${MKSLIDES_PORT}" entrypoint=mkslides \
	cmd="serve ${mkslides.input_dir} -f mkslides.yml --dev-addr 0.0.0.0:$${MKSLIDES_PORT}" \
	${make} docs._slides