## actions.mk: Populates `actions.*` namespace with tasks on Github-Actions 
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

actions.lint:
	@# Helper for linting all action-yaml
	cmd='-color' ${docker.image.run}/rhysd/actionlint:latest 

actions.clean: mk.require.tool/gh
	@# Cleans all action-runs that are cancelled or failed
	${make} actions.list/failure actions.list/cancelled \
	| ${stream.peek} | ${jq} -r '.[].databaseId' \
	| ${make} flux.each/actions.run.delete

actions.clean.old: mk.require.tool/gh
	@# Cleans actions older than a week
	gh run list --limit 1000 --json databaseId,createdAt \
	| ${jq} '.[] | select(.createdAt | fromdateiso8601 < (now - (60*60*24*7))) | .databaseId' \
	| xargs -I{} gh run delete {}

actions.run.delete/%:
	@# Deletes the given action.
	gh run delete ${*}

actions.list: mk.require.tool/gh
	gh run list --json

actions.list/%:
	@# Filters all action-runs with the given status, returning ID
	gh run list --status ${*} --json databaseId

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
