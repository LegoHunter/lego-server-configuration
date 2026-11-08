# ARC runner image: GitHub's actions-runner plus kubectl, for the deploy jobs.
#
# Built and pushed by .github/workflows/arc-runner-image.yml whenever this file changes. The tag is
# the image: line in helm/arc-runner-values.yaml.
#
# There is no RUN step, so the arm64 image builds on GitHub's amd64 runners without emulation, the
# same way the service images are built. The base image already has curl, jq, unzip and git.
# kubectl is copied from the official image and kept within one minor version of the cluster.
#
# hooks/prod-job-guard.sh is the PROD runner's job-started guard (HOMELAB-29). It is in every image
# but only runs where the Helm values set ACTIONS_RUNNER_HOOK_JOB_STARTED (arc-runner-prod). It
# lives outside /home/runner because GitHub requires hook scripts outside the runner application
# directory.
#
# GitHub deprecates old runner versions every few months. Deploy jobs then stay queued while ARC
# runners show the state "Outdated". To fix: bump the actions-runner version here, bump the tag in
# helm/arc-runner-values.yaml, push, and run the helm upgrade from README.md.
FROM registry.k8s.io/kubectl:v1.32.8 AS kubectl

FROM ghcr.io/actions/actions-runner:2.338.2
COPY --from=kubectl /bin/kubectl /usr/local/bin/kubectl
COPY --chmod=0755 hooks/prod-job-guard.sh /opt/lcms/hooks/prod-job-guard.sh
