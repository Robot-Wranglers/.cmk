## actions.mk: Populates `actions.*` namespace with tasks on Github-Actions 
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

actions.lint:; cmd='-color' ${docker.image.run}/rhysd/actionlint:latest 
	@# Helper for linting all action-yaml

actions.clean cicd.clean clean.github.actions:
	@# Cleans all action-runs that are cancelled or failed
	@#
	${make} actions.list/failure actions.list/cancelled \
	| ${stream.peek} | ${jq} -r '.[].databaseId' \
	| ${make} flux.each/actions.run.delete

actions.clean.old:
	gh run list --limit 1000 --json databaseId,createdAt \
	| ${jq} '.[] | select(.createdAt | fromdateiso8601 < now - (60*60*24*7)) | .databaseId' \
	| xargs -I{} gh run delete {}

actions.run.delete/%:; gh run delete ${*}
	@# Helper for deleting an action

actions.list/%:; gh run list --status ${*} --json databaseId
	@# Helper for filtering action runs

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
