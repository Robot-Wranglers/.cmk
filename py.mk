## py.mk: Populates `py.*` namespace with python-related automation.
##
## This covers especially things related to pip, tox, and twine.  
## See `pdoc.mk` for something more centric to python docs.
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# What will be installed by py.init 
py.pkg_optional_extras?=dev,testing,publish

py.done.glyph=${no_ansi}${bold}${green}${GLYPH_CHECK}

pip.install=pip install \
	-q --disable-pip-version-check $${pip_args:-} \
	$(shell [ "$${verbose:-0}" = "0" ] && echo "--quiet" || echo ) -e
py.pkg.install/%:
	@# Treats argument as 
pip.install.build:; $(call log.target, installing build module with pip); pip install build
pip.install/%: mk.require.tool/pip
	@# NB: Pass `verbose=1` to avoid pip --quiet
	$(call log.target, verbose=$${verbose:-0} ${sep} ${dim}pip_args=$${pip_args:-})
	$(call log.target.pad_bottom, ${pip.install} .[${*}] ${sep} ${cyan_flow_right} ) 
	set -x && ${pip.install} .[${*}]
	$(call log.target.pad_top, ${dim}${pip.install} .[${*}] ${sep} ${py.done.glyph})
py.pkg.extra.install/%:; ${make} pip.install/.[${*}]
	@#
pip.install.many/%:
	@#
	echo ${*} | ${stream.comma.to.nl} | ${make} flux.each/pip.install
py.pkg.extra.install.many/%:
	@#
	echo ${*} | ${stream.comma.to.nl} | ${make} flux.each/py.pkg.extra.install
pip.release pypi.release: mk.require.tool/twine mk.assert/PYPI_USER,PYPI_TOKEN
	@#
	PYPI_RELEASE=1 ${make} py.build \
	&& twine upload \
		--user $${PYPI_USER} \
		--password $${PYPI_TOKEN} \
		dist/*

## Generic Support
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

py.init: pip.install.build pip.install.many/$(strip ${py.pkg_optional_extras})
	@# Runs pip.install.build and install dev/testing/publish for this package

py.stat:
	@# Show details about the python version / platform
	_version=`python --version | awk -F' ' '{print $$2}'` \
	&& _bin=`which python` \
	&& $(call log.target, $${_version} ${sep} $${_bin}) 

py.build py.pkg.build: py.clean
	@# Build python package in working directory
	export version=`python setup.py --version` \
	&& $(call log.target, extracted details ${sep} package=${py.pkg_name} version=$${version}) \
	&& (git tag $${version} \
	|| ( $(call log.target, ${yellow}WARNING: Failed to git-tag with release-tag; normal if tag already exists )) \
	&& printf "# WARNING: file is maintained by automation\n\n__version__ = \"$${version}\"\n\n" \
	| tee src/${py.pkg_name}/_version.py \
	&& pip install build && set -x && python -m build

py.clean: tox.clean
	@# Clean working directory
	$(call log.target.part1, cleaning eggs/build/dist)
	$(call log.target.part2, ${GLYPH_CHECK})
	rm -rf tmp.pypi* dist/* build/* 
	rm -rf src/*.egg-info/
	rm -rf .ruff_cache
	$(call log.target.part1, cleaning pycs/cache)
	$(call log.target.part2, ${GLYPH_CHECK})
	find . -name '*.tmp.*' -delete
	find . -name '*.pyc' -delete
	rm -rf .mypy_cache
	find . -name  __pycache__ -delete
	rmdir build 2>/dev/null || true
	$(call log.target, done cleaning python tmp files)

py.version py.pkg.version:; python setup.py --version
	@# Answer version info for the current project.
	@# Relies on (python setup.py --version)

## Tox Support 
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

_tox.force=case $${force:-0} in \
		1) force="--recreate";; \
		*) force="";; \
	esac

tox.clean:
	@# Clean working directory
	$(call log.target.part1,cleaning)
	rm -rf .tox
	# find . -type d -name .tox | xargs -I% bash -x -c "rm -rf %"
	$(call log.target.part2,${GLYPH_CHECK})
tox/%: mk.require.tool/tox 
	@# Runs the named tox environment.
	@#
	@# USAGE: tox/<tox_env_name>
	${_tox.force} \
	&& filler="-" label="tox/env=${*} " && ${io.print.banner}  \
	&& $(call log.target.part1, env=${*} ${sep} ${cyan_flow_right} ) \
	&& tox $${force:-} -e ${*} $${tox_args:-} \
	; exit_code="$$?" \
	&& case $${exit_code} in \
		0) label="${py.done.glyph} tox/env=${*}";; \
		*) label="${red}failed!${no_ansi} tox/env=${*} exit=$${exit_code}";;  \
	esac \
	&& filler="-" ${io.print.banner}  \
	&& exit $${exit_code}

tox.dispatch/%:
	@# Dispatches the given make target in the given tox-environment
	@#
	@# USAGE: tox.dispatch/<tox_env_name>,<target_name>
	export target=$(strip $(shell echo ${*} | cut -d, -f2-)) \
	&& _tox_env="$(strip $(shell echo ${*} | cut -d, -f1))" \
	&& ${_tox.force}  \
	&& $(call log.target, env=${ital}${bold}$${_tox_env} ${sep} $${tox_args:-} $${force}) \
	&& set -x && tox $${force} -e $${_tox_env}

# MACRO: tox.import
#   Import several tox environments to targets
# USAGE: 
#   $(call tox.import,env1 env2) =>
#     env1: tox/env1
#     env2: tox/env1
#     env2.dispatch/%: tox.dispatch/env2,%
tox.import=$(eval $(call _tox.import,${1}))
define _tox.import
$(eval __code_blocks__:=$(shell echo "${1}"))
$(foreach codeblock, ${__code_blocks__},\
	$(call _tox.import.env, ${codeblock}))
endef
define _tox.import.env
${nl}
$(call mk.unpack.kwargs, ${1}, tox_env, ${1})
${kwargs_tox_env}: tox/${kwargs_tox_env}
tox.${kwargs_tox_env}.dispatch/%:  
	${make} tox.dispatch/${kwargs_tox_env},$${*}
endef
