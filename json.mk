
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