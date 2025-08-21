## docs.mk: Populates `docs.*` namespace with documentation-related tasks.
##
## This covers especially things related to markdown, mkdocs, and jinja.  
## See `pdoc.mk` for something more centric to docs on python packages or apis.
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

## CSS Support
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

define Dockerfile.css.min
FROM node:18-alpine
RUN npm install -g clean-css-cli
WORKDIR /workspace
ENTRYPOINT ["cleancss"]
endef
css.min/%: Dockerfile.build/css.min
	@# CSS Minify
	img=css.min cmd="--output ${*} ${*}" ${make} mk.docker

define Dockerfile.css.pretty
FROM node:18-alpine
RUN npm install -g prettier
WORKDIR /workspace
ENTRYPOINT ["prettier", "--write"]
endef
css.pretty/%: Dockerfile.build/css.pretty
	@# CSS Pretty / Un-minify
	img=css.pretty cmd="--write ${*}" ${make} mk.docker

# Diagramming Support
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

mmd.config=.cmk/.mmd.config
# mmd.config=${CMK_PLUGINS_DIR}

define Dockerfile.mermaid 
FROM ghcr.io/mermaid-js/mermaid-cli/mermaid-cli:11.4.1
USER root 
RUN apk add -q --update --no-cache coreutils build-base bash procps-ng
RUN ln -s /home/mermaidcli/node_modules/.bin/mmdc /usr/local/bin/mmd
endef

docs.mmd.stat: docs.mmd.build
	${jb} version=`${make} docs.mmd.version|tr -d '\r'`
docs.mmd.version:; cmd="--version" ${make} mk.docker/mermaid
docs.mmd.build: Dockerfile.build/mermaid
docs.mmd/%:; ${make} self.mmd.render/${*}
	
docs.mermaid docs.mmd: docs.mmd.build
	@# Renders all diagrams for use with the documentation 
	$(call log.target, rendering all mermaid diagrams)
	find ${docs.root} | grep '[.]mmd$$' | ${stream.peek} | ${flux.each}/self.mmd.render
	$(call log.target, ${dim}rendering all mermaid diagrams ${sep} ${green}${bold}${GLYPH_CHECK})
docs.mmd.shell:; entrypoint=bash ${make} mk.docker/mermaid
self.mmd.render/%:
	@# Renders the given mermaid file,
	@# including some post-processing that does trim-to-content
	@#
	output=`dirname ${*}`/`basename -s.mmd ${*}`.png \
	&& mmd_config=`ls ${mmd.config}2>/dev/null && echo '--configFile ${mmd.config}' || echo ''`\
	&& cmd="-i ${*} $${mmd_config} -o $${output} $${mmd_args:--b transparent }" \
		img=mermaid ${make} mk.docker \
	&& set -x && docker run --rm -v `pwd`:/workspace -w /workspace dpokidov/imagemagick $${output} -flatten -fuzz 1% -trim +repage tmp.png && mv tmp.png $${output} \
	&& cat $${output} | ${stream.img}

## Top-level Docs Support
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

docs.root=docs

docs.render.mirror/%:
	@# USAGE:
	@#  .PHONY: README.md
	@#   README.md:; ${make} docs.render.mirror/${@}
	@#
	dest="${*}" \
	&& src="${docs.root}/${*}.j2" \
	&& $(call log.io, docs.render.mirror ${sep} ${no_ansi}${bold}$${dest} ${cyan_flow_left} ${dim}$${src}) \
	&& ${make} docs.pynchon.render.io/$${src},$${dest} \
	&& cat $${dest} | ${stream.glow}
docs.render.mirror=${make} docs.render.mirror/${@}

docs.init: docs.pynchon.build

docs.footnotes:; python -c '\
import json,pathlib;\
skip_list = ["README"]; tmp = { p.stem.split(".")[0]:p \
      for p in pathlib.Path("docs/").iterdir() if str(p).endswith(".md.j2") }; \
tmp={ p:open(f"docs/{p}.md.j2","r").readlines() for p in tmp }; \
tmp={ \
  p:[":".join(l.split(":")[1:]).strip() for l in lines if l.startswith("[^")] \
  for p,lines in tmp.items() }; \
tmp={ k:v for k,v in tmp.items() if v and k not in skip_list}; \
tmp={k:tmp[k] for k in sorted(tmp.keys())}; \
print(json.dumps(tmp,indent=2)) \
'

docs.serve:
	@# Like `mkdocs.serve` but runs via a container, with port-forwarding.
	@#
	docker_args="-p $${MKDOCS_LISTEN_PORT:-8000}:$${MKDOCS_LISTEN_PORT:-8000}" \
		${make} docs.pynchon.dispatch/mkdocs.serve

## Mkdocs Support
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

mkdocs.site_name=`cat mkdocs.yml|${yq} -r .site_name`

mkdocs: mkdocs.build mkdocs.serve

mkdocs.get/%:
	@# Gets a single value from a mkdocs.yml file with `yq`
	cat mkdocs.yml|${yq} -r .${*}

mkdocs.build: 
	@# Runs mkdocs build
	$(call log.target, building..)
	mkdocs build

mkdocs.open:
	@# Opens (local) mkdocs webpage in browser.  (Assumes mkdocs.serve)
	$(call log.target, opening page in browser)
	set -x && $${BROWSER:-firefox} http://$${MKDOCS_LISTEN_HOST:-0.0.0.0}:$${MKDOCS_LISTEN_PORT:-8000}

.mkdocs.build: docs/schema
	$(call log.target, building)
	set -x && (make docs && mkdocs build --clean --verbose && tree site) \
	; find site docs | xargs chmod o+rw; ls site/index.html

mkdocs.serve:
	@# Runs `mkdocs serve` in the working directory, 
	@# respecting MKDOCS_LISTEN_HOST and MKDOCS_LISTEN_PORT
	$(call log.target, serving)
	mkdocs serve --dev-addr $${MKDOCS_LISTEN_HOST:-0.0.0.0}:$${MKDOCS_LISTEN_PORT:-8000}

## Jinja Support
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

define Dockerfile.pynchon
FROM python:3.9-bookworm
RUN pip3 install --break-system-packages pynchon==2025.3.20.17.28 mkdocs==1.5.3 mkdocs-autolinks-plugin==0.7.1 mkdocs-autorefs==1.0.1 mkdocs-material==9.5.3 mkdocs-material-extensions==1.3.1 mkdocstrings==0.25.2 mkdocs-redirects==1.2.2 tox==4.6.4
RUN apt-get update && apt-get install -y tree jq make procps
endef
$(call docker.import.def, def=pynchon namespace=docs.pynchon)

docs.pynchon.render/%:; ${make} docs.pynchon.dispatch/self.docs.jinja/${*}
	@# Render a single file, fuzzy matching input and automatically determining output

docs.pynchon.render.io/%:
	@# Render a single file, with explicit comma-delimited input/output
	entrypoint=sh \
	cmd='-x -c "pynchon jinja render $(call mk.unpack.arg, 1) -o $(call mk.unpack.arg, 2)"' \
	${make} docs.pynchon

docs.jinja_templates:; find ${docs.root} | grep .j2 | sort  | grep -v ${docs.root}/macros/
	@# Find all templates under docs root.
docs.jinja: docs.pynchon.dispatch/self.docs.jinja
	@# Render all templates under docs-root
self.docs.jinja:
	@# Render all templates under docs-root
	@# (Runs inside the pynchon container)
	pynchon --version
	${make} docs.jinja_templates \
	| xargs -I% sh -x -c "make self.docs.jinja/% || exit 255"
docs.jinja/%:; ${make} docs.pynchon.dispatch/self.docs.jinja/${*}
	@# (Runs inside the pynchon container)
self.docs.jinja/%:
	@# Render the named docs twice (once to use includes, then to get the ToC)
	ls ${*}/*.j2 2>/dev/null >/dev/null \
	&& ( \
		$(call log,is dir); ls ${*}/*.j2 \
			| xargs -I% sh -x -c "${make} j/%") \
	|| case ${*} in \
		*.md.j2) ${make} .self.docs.jinja/${*};; \
		*.bib.j2) ${make} .self.docs.jinja/${*};; \
		*.md) ${make} .self.docs.jinja/${*}.j2;; \
		*) ${make} .self.docs.jinja/${*}.md.j2;; \
	esac
.self.docs.jinja/%:
	@#
	ls ${*} ${stream.obliviate} || ($(call log,${red} no such file ${*}); exit 39)
	$(call io.mktemp) && first=$${tmpf} \
	&& set -x && pynchon jinja render ${*} -o $${tmpf} --print \
	&& set +x && dest="`dirname ${*}`/`basename -s .j2 ${*}`" \
	&& set -x && mv $${tmpf} $${dest}
