#!/usr/bin/env bash
# Job-started hook for the PROD runner scale set `arc-runner-prod` (HOMELAB-29).
#
# The runner deploys to services-prod with its own ServiceAccount (arc-runners/arc-deployer-prod),
# not with a GitHub secret, so GitHub Environment approvals and branch rules cannot stop a job that
# lands on it. On the GitHub Free plan the org has only the Default runner group, so the runner
# cannot be limited to certain repositories or workflows either. This hook is that limit: the
# runner runs it before every job (ACTIONS_RUNNER_HOOK_JOB_STARTED, set only in
# helm/arc-runner-prod-values.yaml), and a non-zero exit fails the job before any of its steps run.
#
# A job may run only if all of these hold:
#   * the run was triggered by a push (a release is the push of a develop -> main merge commit);
#   * the ref is refs/heads/main, both in the runner's GITHUB_REF and in the event payload;
#   * the repository is listed in PROD_RUNNER_ALLOWED_REPOS (space-separated owner/name, set in the
#     Helm values; adding a service = edit the values and helm upgrade).
# A feature branch, a pull request (including one from a fork), a manual dispatch or another
# repository is refused. Workflows cannot override GITHUB_* variables, and the event payload is
# written by GitHub.
#
# The image sets nothing: the shared [arc-runner] uses the same image without this hook.
set -euo pipefail
set -f  # the allowlist is split on spaces below; never expand it as a glob

refuse() {
  echo "::error title=PROD runner refused this job::$1"
  echo "arc-runner-prod only runs the deploy-prod job of the shared pipeline, for a push to main of an allowlisted service repository (lego-server-configuration github-runner/README.md)." >&2
  exit 1
}

repo=${GITHUB_REPOSITORY:-}
event=${GITHUB_EVENT_NAME:-}
ref=${GITHUB_REF:-}
allowed=${PROD_RUNNER_ALLOWED_REPOS:-}

[ -n "$allowed" ] || refuse "PROD_RUNNER_ALLOWED_REPOS is empty, so no repository may use this runner."

match=false
for candidate in $allowed; do
  if [ "$candidate" = "$repo" ]; then match=true; fi
done
[ "$match" = true ] || refuse "Repository '$repo' is not allowed to use the PROD runner."

[ "$event" = push ] || refuse "Event '$event' in $repo: only a push to main may deploy to PROD."
[ "$ref" = refs/heads/main ] || refuse "Ref '$ref' in $repo: only refs/heads/main may deploy to PROD."

payload_ref=$(jq -r '.ref // empty' "${GITHUB_EVENT_PATH:-/dev/null}" 2>/dev/null || true)
[ "$payload_ref" = refs/heads/main ] || refuse "The event payload's ref is '$payload_ref', not refs/heads/main."

echo "PROD runner guard: allowed $repo, $event of $ref (${GITHUB_SHA:-unknown sha}), job ${GITHUB_JOB:-unknown}."
