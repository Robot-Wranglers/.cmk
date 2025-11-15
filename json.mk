# json.mk: Populates `json.*` namespace with JSON-related helpers.
#
# This includes basic stuff for validation and conversion.  Nothing fancy 
# here, but left out of `compose.mk` standard-library just to avoid the clutter
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

json.validate/%:
	@# Validates the given JSON file, or if a directory, validates all JSON files
	ls ${*} > /dev/null\
	|| ( $(call log.target, ${*} ${sep} ${red} does not exist) \
		; exit 23 ) 
	test -d ${*} \
	&& ( $(call log.target, ${*} ${sep} is a directory) \
		&& find ${*} -type f | grep .json$$ \
		| ${flux.each}/json.validate ) \
	|| ( \
		$(call log.target.part1, json.validate ${sep} ${ital}${*}) \
		&& cat ${*} | ${jq} -c . > /dev/null \
		&& $(call log.target.part2, ok))

# Conversion helpers, leveraging `stream.nushell` directly or indirectly
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

json.from_cols: stream.nushell.parse_cols
	@# Attempts to create JSON by autodetecting column headers and column width.  
	@# See the docs for `stream.nushell.parse_cols`

json.parse: stream.nushell.parse
	@# Parse JSON from line-oriented input, using a given pattern.
	@# See the docs for `stream.nushell.parse`

json.to_yaml: stream.nushell/from_json,to_yaml
	@# Converts JSON to yaml (via nushell)