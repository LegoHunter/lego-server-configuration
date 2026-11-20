#!/usr/bin/env bash
# Creates the Git tag and GitHub Release for one PROD release of an LCMS service (HOMELAB-127).
#
# Called by the prod-release job of ../workflows/k8s-service-pipeline.yml after deploy-prod and its
# smoke check succeeded. Can also be run by hand from a full clone of the service repository, for
# example to give an earlier PROD release its Release, or with DRY_RUN=true to preview the notes.
#
# The Release page has, in this order:
#   1. "Tickets in this release": every Jira key found in the SUBJECTS of the commits since the
#      previous release tag, with the ticket's type, summary and status, read from Jira. Commit
#      bodies are ignored on purpose: they may name keys only as examples.
#   2. "Image": the Quay image and digest that PROD runs.
#   3. GitHub's generated notes: every pull request merged since the previous release tag.
#
# Tag scheme: vYYYY.MM.DD (America/New_York date), then vYYYY.MM.DD.2, .3 for more releases that day.
# The tag is created on the develop -> main merge commit. Nothing is committed to any branch:
# prod-promote refuses a main whose tree differs from develop, so a commit to main (for example a
# CHANGELOG.md) would block the next release.
#
# Jira problems never stop the Release: with no token, a refused token or Jira unreachable, the
# Release is created without the ticket section and the run shows a warning.
#
# Environment:
#   REPO               owner/name of the service repository (required)
#   APP                service name, also the Quay repository name (required)
#   MAIN_SHA           the develop -> main merge commit being released (required)
#   IMAGE_DIGEST       sha256:... digest PROD runs (optional; looked up from Quay prod-<MAIN_SHA> if empty)
#   GH_TOKEN           token with contents:write on REPO (required unless DRY_RUN)
#   JIRA_SITE          Jira site, default https://vattima.atlassian.net
#   JIRA_PROJECT_KEY   default HOMELAB
#   JIRA_USER_EMAIL    the Atlassian account the API token belongs to
#   JIRA_API_TOKEN     read-only (scoped) Atlassian API token; never printed
#   DRY_RUN            true: print the tag and notes, create nothing

set -euo pipefail

: "${REPO:?REPO is required}"
: "${APP:?APP is required}"
: "${MAIN_SHA:?MAIN_SHA is required}"
JIRA_SITE="${JIRA_SITE:-https://vattima.atlassian.net}"
JIRA_PROJECT_KEY="${JIRA_PROJECT_KEY:-HOMELAB}"
DRY_RUN="${DRY_RUN:-false}"
IMAGE_DIGEST="${IMAGE_DIGEST:-}"

warn() { echo "::warning title=Release notes::$*"; }
summary() { [ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "$*" >> "$GITHUB_STEP_SUMMARY" || true; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

git cat-file -e "$MAIN_SHA^{commit}" 2>/dev/null || { echo "::error::$MAIN_SHA is not in this clone (fetch the full history and tags first)."; exit 1; }

tag_pattern='^v[0-9]{4}\.[0-9]{2}\.[0-9]{2}(\.[0-9]+)?$'

# A re-run of the job for a release that already has its tag and Release: nothing to do.
existing=$(git tag --points-at "$MAIN_SHA" | grep -E "$tag_pattern" | head -n1 || true)
if [ -n "$existing" ] && [ "$DRY_RUN" != true ] && gh release view "$existing" --repo "$REPO" >/dev/null 2>&1; then
  echo "$MAIN_SHA already has the Release $existing; nothing to do."
  summary "Release: $existing (already existed)"
  exit 0
fi

# Previous release: the newest release tag reachable from main before this merge (first parent).
prev_tag=""
if git rev-parse -q --verify "$MAIN_SHA^1" >/dev/null; then
  prev_tag=$(git describe --tags --abbrev=0 --match 'v[0-9]*' "$MAIN_SHA^1" 2>/dev/null || true)
  [[ "$prev_tag" =~ $tag_pattern ]] || prev_tag=""
fi

# This release's tag.
if [ -n "$existing" ]; then
  tag="$existing"   # tag exists but its Release does not (an earlier run stopped half-way)
else
  base="v$(TZ=America/New_York date +%Y.%m.%d)"
  tag="$base"; n=1
  while git rev-parse -q --verify "refs/tags/$tag" >/dev/null \
        || git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; do
    n=$((n + 1)); tag="$base.$n"
  done
fi

# The develop commit DEV built: the merge commit's second parent.
develop_sha=$(git rev-parse -q --verify "$MAIN_SHA^2" 2>/dev/null || true)

if [ -z "$IMAGE_DIGEST" ]; then
  IMAGE_DIGEST=$(curl -fsS --max-time 15 \
    "https://quay.io/api/v1/repository/tvattima/$APP/tag/?specificTag=prod-$MAIN_SHA&onlyActiveTags=true" \
    | jq -r '.tags[0].manifest_digest // empty' 2>/dev/null || true)
fi

# ---- 1. Tickets in this release ------------------------------------------------------------
range="$MAIN_SHA"; [ -n "$prev_tag" ] && range="$prev_tag..$MAIN_SHA"
git log --format=%s "$range" \
  | grep -oE "(^|[^A-Za-z0-9])${JIRA_PROJECT_KEY}-[0-9]+" \
  | grep -oE "${JIRA_PROJECT_KEY}-[0-9]+" \
  | sort -t- -k2,2n -u > "$work/keys" || true
key_count=$(wc -l < "$work/keys" | tr -d ' ')

tickets_md="$work/tickets.md"
: > "$tickets_md"
jira_ok=false
if [ "$key_count" -gt 0 ]; then
  if [ -z "${JIRA_API_TOKEN:-}" ] || [ -z "${JIRA_USER_EMAIL:-}" ]; then
    warn "No Jira credentials (JIRA_API_TOKEN secret / JIRA_USER_EMAIL), so the Release has no ticket section."
  else
    cloud_id=$(curl -fsS --max-time 15 "$JIRA_SITE/_edge/tenant_info" | jq -r '.cloudId // empty' 2>/dev/null || true)
    if [ -z "$cloud_id" ]; then
      warn "Could not reach Jira ($JIRA_SITE), so the Release has no ticket section."
    else
      api="https://api.atlassian.com/ex/jira/$cloud_id/rest/api/3"
      # The token goes to curl through a config file on stdin, never on a command line.
      jira_get() {
        printf 'user = "%s:%s"\n' "$JIRA_USER_EMAIL" "$JIRA_API_TOKEN" \
          | curl -sS --max-time 15 -K - -o "$2" -w '%{http_code}' -H 'Accept: application/json' "$api/$1" 2>/dev/null || echo 000
      }
      code=$(jira_get "project/$JIRA_PROJECT_KEY" "$work/project.json")
      if [ "$code" != 200 ]; then
        warn "Jira refused the token or the project $JIRA_PROJECT_KEY (HTTP $code), so the Release has no ticket section."
      else
        jira_ok=true
        : > "$work/rows"
        while read -r key; do
          code=$(jira_get "issue/$key?fields=summary,issuetype,status" "$work/issue.json")
          if [ "$code" = 200 ]; then
            jq -r --arg key "$key" \
              '[.fields.issuetype.name, $key, .fields.summary, .fields.status.name] | @tsv' \
              "$work/issue.json" >> "$work/rows"
          else
            printf '%s\t%s\t%s\t%s\n' "Not found" "$key" "(HTTP $code)" "-" >> "$work/rows"
          fi
        done < "$work/keys"
        {
          echo "## Tickets in this release"
          echo
          # One section per Jira work type, in a fixed order, then any other type.
          for type in Epic Story Task Defect Bug Spike Sub-task; do
            awk -F'\t' -v t="$type" '$1 == t' "$work/rows" > "$work/type"
            [ -s "$work/type" ] || continue
            echo "### $type"
            awk -F'\t' '{ printf "- %s: %s (%s)\n", $2, $3, $4 }' "$work/type"
            echo
          done
          awk -F'\t' '$1 !~ /^(Epic|Story|Task|Defect|Bug|Spike|Sub-task|Not found)$/' "$work/rows" > "$work/type"
          if [ -s "$work/type" ]; then
            echo "### Other"
            awk -F'\t' '{ printf "- %s: %s (%s, %s)\n", $2, $3, $1, $4 }' "$work/type"
            echo
          fi
          awk -F'\t' '$1 == "Not found"' "$work/rows" > "$work/type"
          if [ -s "$work/type" ]; then
            echo "### Not readable in Jira"
            awk -F'\t' '{ printf "- %s %s\n", $2, $3 }' "$work/type"
            echo
          fi
          echo "_Keys taken from the commit subjects since ${prev_tag:-the first commit}; status as of this release._"
          echo
        } > "$tickets_md"
      fi
    fi
  fi
fi

if [ "$jira_ok" != true ] && [ "$key_count" -gt 0 ]; then
  {
    echo "## Tickets in this release"
    echo
    echo "Jira could not be read for this release. Keys in the commit subjects:"
    echo
    tr '\n' ' ' < "$work/keys" | sed 's/ $//; s/ /, /g'
    echo
    echo
  } > "$tickets_md"
fi

# ---- 2. Image --------------------------------------------------------------------------------
notes="$work/notes.md"
{
  cat "$tickets_md"
  echo "## Image"
  echo
  echo "- \`quay.io/tvattima/$APP:prod-$MAIN_SHA\`"
  [ -n "$IMAGE_DIGEST" ] && echo "- Digest \`$IMAGE_DIGEST\` (the image DEV ran; PROD does not rebuild)"
  [ -n "$develop_sha" ] && echo "- Released \`develop\` commit \`$develop_sha\` as \`main\` merge commit \`$MAIN_SHA\`"
  echo
} > "$notes"

echo "Release $tag for $REPO at $MAIN_SHA (previous release: ${prev_tag:-none}; $key_count Jira key(s))."

if [ "$DRY_RUN" = true ]; then
  echo "----- notes (our part; GitHub appends the pull request list) -----"
  cat "$notes"
  exit 0
fi

# ---- 3. Create the tag and Release, with GitHub's generated pull request list appended -------
args=(release create "$tag" --repo "$REPO" --target "$MAIN_SHA" --title "$APP $tag"
      --notes-file "$notes" --generate-notes --latest)
[ -n "$prev_tag" ] && args+=(--notes-start-tag "$prev_tag")
gh "${args[@]}"

url=$(gh release view "$tag" --repo "$REPO" --json url --jq .url)
echo "Created $url"
summary "Release: [$tag]($url)"
