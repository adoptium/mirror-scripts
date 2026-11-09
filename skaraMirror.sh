#!/bin/bash
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

set -euxo pipefail

# Make sure we're in a valid dir as a workspace
# MIRROR_WORKSPACE and MIRROR_PATCHES are optional overrides, used by the tests/ harness.
# (WORKSPACE itself is not used as the override as Jenkins sets it for its own purposes.)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORKSPACE=${MIRROR_WORKSPACE:-$SCRIPT_DIR/workspace}
mkdir -p "$WORKSPACE"
PATCHES=${MIRROR_PATCHES:-$SCRIPT_DIR/patches}/

# TODO generalise this for the non adoptium build farm case
function checkArgs() {
  if [ "$1" -lt 1 ]; then
     echo Usage: "$0" '[jdk8u|jdk17u]'
     echo "Skara Repo supplied should match a repository in https://github.com/openjdk/"
     echo "For example, to mirror https://github.com/openjdk/jdk17u"
     echo "e.g. $0 jdk17u"
     exit 1
  fi
}

# For jdk8u-based repos, common/autoconf/generated-configure.sh is a build-generated file
# that frequently conflicts during merges/rebases/patches because it is regenerated from
# common/autoconf/*.m4 sources. This function checks if it is the ONLY conflict and if so,
# regenerates it via autogen.sh and stages the result.
# Must be called from within the repo working directory.
# Returns 0 if the conflict was resolved, 1 if there are other conflicts (caller must fail).
function resolveGeneratedConfigureConflict() {
  local GENERATED_CONFIGURE="common/autoconf/generated-configure.sh"
  local AUTOGEN="common/autoconf/autogen.sh"

  # Only applies to jdk8u-based repos that have the autogen script
  if [[ "${VERSION}" != "8" ]]; then
    return 1
  fi

  # Get list of conflicted files
  local conflicts
  conflicts=$(git diff --name-only --diff-filter=U)

  if [[ -z "$conflicts" ]]; then
    return 1
  fi

  # Check if generated-configure.sh is the only conflict
  if [[ "$conflicts" != "$GENERATED_CONFIGURE" ]]; then
    echo "ERROR: Conflicts exist in files other than $GENERATED_CONFIGURE:"
    echo "$conflicts"
    return 1
  fi

  echo "Resolving $GENERATED_CONFIGURE conflict by regenerating via autogen.sh"
  if [ ! -f "$AUTOGEN" ]; then
    echo "ERROR: $AUTOGEN not found — cannot regenerate $GENERATED_CONFIGURE"
    return 1
  fi

  bash "$AUTOGEN" || return 1
  git add "$GENERATED_CONFIGURE" || return 1
  echo "Successfully regenerated and staged $GENERATED_CONFIGURE"
  return 0
}

function cloneGitHubRepo() {
  cd "$WORKSPACE" || exit 1
  # If we don't have a $GITHUB_REPO locally then clone it from adoptium/$GITHUB_REPO.git
  if [ ! -d "$GITHUB_REPO" ] ; then
    git clone "$REPO" "$GITHUB_REPO" || exit 1
  else
    # A workspace left over from a previous run may have been cloned from a different repo (for
    # example the real adoptium repo when this run is for a fork). Everything after this fetches
    # from and pushes to its origin, so never carry on with an origin that is not $REPO.
    local existingOrigin
    existingOrigin=$(git -C "$GITHUB_REPO" remote get-url origin 2>/dev/null) || existingOrigin=""
    if [[ "$existingOrigin" != "$REPO" ]]; then
      echo "ERROR: existing workspace $WORKSPACE/$GITHUB_REPO has origin '${existingOrigin:-<none>}' but this job is mirroring to '$REPO'"
      echo "Delete $WORKSPACE/$GITHUB_REPO (or run the job with CLEAN_MIRROR_WORKSPACE) and run it again"
      exit 1
    fi
  fi
}

function addSkaralUpstream() {
  cd "$WORKSPACE/$GITHUB_REPO" || exit 1

  git fetch --all

  # Ensure the skara remote exists before we need it
  # shellcheck disable=SC2143
  if [ -z "$(git remote -v | grep 'skara')" ] ; then
    echo "Initial setup of $SKARA_REPO"
    git remote add skara "$SKARA_REPO"
  fi

  # Fetch skara so skara/$BRANCH is available for branch creation below
  git fetch skara

  if ! git checkout -f "$BRANCH" ; then
    if ! git rev-parse -q --verify "origin/$BRANCH" ; then
      # Branch does not exist locally or on origin — create it from skara/$BRANCH
      # so it starts at the correct upstream commit, not the current HEAD
      git checkout -b "$BRANCH" "skara/$BRANCH" || exit 1
    else
      git checkout -b "$BRANCH" "origin/$BRANCH" || exit 1
    fi
  else
    # Only reset to origin/$BRANCH if it has been pushed there previously
    if git rev-parse -q --verify "origin/$BRANCH" ; then
      git reset --hard "origin/$BRANCH" || exit 1
    else
      echo "No origin/$BRANCH exists yet, skipping reset"
    fi
  fi
}

# The only way this script pushes to the mirror. With DRY_RUN=true it prints the push and does
# nothing, so no code path can write to the mirror during a dry run.
function gitPush() {
  if [[ "${DRY_RUN:-false}" == true ]]; then
    echo "DRY_RUN: git push $*"
    return 0
  fi
  git push "$@"
}

function performMergeFromSkaraIntoGit() {
  git fetch skara --tags

  if ! git rebase "skara/$BRANCH" "$BRANCH" ; then
    if resolveGeneratedConfigureConflict ; then
      git rebase --continue || exit 1
    else
      git rebase --abort
      exit 1
    fi
  fi

  gitPush -u origin "$BRANCH" || exit 1
  gitPush origin "$BRANCH" --tags || exit 1
}


# ---------------------------------------------------------------------------
# Tag driven mirroring. See TAG_MIRRORING_STRATEGY.md.
#
# Globals used (set in the main section at the bottom):
#   GITHUB_REPO, VERSION ("" for the head repo), BRANCH, SKARA_DEFAULT_BRANCH,
#   RELEASE_BRANCH, FAMILY_REGEX, VISIBLE_REF, jdk_sort_tags_cmd
#
# All functions return 0 unless stated, so they are safe to use under set -e / pipefail.
# ---------------------------------------------------------------------------

# Print the version string of a build tag: jdk-28+3 -> 28, jdk-27.0.1.0.3+5 -> 27.0.1.0.3,
# jdk8u504-b01 (and the aarch32 variant) -> 504. Prints nothing if the tag has no known shape.
function tagVersion() {
  local tag="$1" re
  if [[ "${VERSION}" == "8" ]]; then
    re='^jdk8u([0-9]+)-b[0-9]+'
  else
    re='^jdk-([0-9]+(\.[0-9]+)*)[+][0-9]+$'
  fi
  if [[ "$tag" =~ $re ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
  return 0
}

# Succeeds if the version has the "master shape": the one the default branch uses in this repo.
#   head   jdk-MM+BB          (any single component)
#   jdkMMu jdk-MM.0.V+BB      (exactly three components)
#   jdk8u  jdk8uNN2-bBB       (version ends in 2)
function isMasterShape() {
  local ver="$1" re
  if [[ "${VERSION}" == "8" ]]; then
    [[ "$ver" == *2 ]]
  elif [[ -z "${VERSION}" ]]; then
    return 0
  else
    re='^[0-9]+\.0\.[0-9]+$'
    [[ "$ver" =~ $re ]]
  fi
}

# Print the version an upstream branch name stands for (jdk28 -> 28, jdk27.0.2 -> 27.0.2,
# openjdk8u504 -> 504), or nothing if the branch name is not a version.
function branchVersion() {
  local branch="$1" re
  if [[ "${VERSION}" == "8" ]]; then
    re='^openjdk8u([0-9]+)$'
  elif [[ -z "${VERSION}" ]]; then
    re='^jdk([0-9]+)$'
  else
    re="^jdk(${VERSION}\\.0\\.[0-9]+(\\.[0-9]+)*)\$"
  fi
  if [[ "$branch" =~ $re ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
  return 0
}

# Print the mirror branch a build tag seen from the current upstream branch ($BRANCH) goes to,
# or nothing if this run does not handle it (the default branch run owns it):
#   master shape, default branch                     release
#   master shape, version equals the version of B    release_<B>
#   master shape, any other version                  not handled
#   any other shape                                  release_<tag version>
# where jdk-27.0.1.0.3+5 gives release_jdk27.0.1.0.3 and jdk8u504-b01 gives release_openjdk8u504.
function targetBranchFor() {
  local tag="$1" ver bv
  ver=$(tagVersion "$tag")
  if [[ -z "$ver" ]]; then
    return 0
  fi
  if isMasterShape "$ver"; then
    if [[ "$BRANCH" == "$SKARA_DEFAULT_BRANCH" ]]; then
      echo "release"
    else
      bv=$(branchVersion "$BRANCH")
      if [[ -n "$bv" && "$bv" == "$ver" ]]; then
        echo "release_${BRANCH}"
      fi
    fi
  elif [[ "${VERSION}" == "8" ]]; then
    echo "release_openjdk8u${ver}"
  else
    echo "release_jdk${ver}"
  fi
  return 0
}

# Filter stdin, dropping the tags listed in the optional releaseTagExcludeList env var.
function filterExcluded() {
  local excludeFile
  if [ -z "${releaseTagExcludeList-}" ]; then
    cat
    return 0
  fi
  excludeFile=$(mktemp "${TMPDIR:-/tmp}/skaramirror-exclude.XXXXXX")
  printf '%s\n' $releaseTagExcludeList > "$excludeFile"
  grep -Fvx -f "$excludeFile" || true
  rm -f "$excludeFile"
  return 0
}

# Filter stdin to the tags in the repo's family (an empty result is not an error)
function familyTags() {
  grep -E "$FAMILY_REGEX" || true
}

# Sort the tags on stdin in version/build order, oldest first
function sortTags() {
  eval "$jdk_sort_tags_cmd" || true
}

# Succeeds if the mirror branch $1 exists
function mirrorBranchExists() {
  git rev-parse -q --verify "refs/remotes/origin/$1" > /dev/null
}

# Show the commits of the local branch $1 that are not on origin/$1 yet, as a graph
function showNewCommits() {
  git --no-pager log --graph --abbrev-commit \
    --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' \
    "origin/$1..$1"
  echo
}

# Print the build tags (oldest first) in the repo's family that are merged into the given ref
function listBuildTags() {
  git tag --merged "$1" | familyTags | filterExcluded | sortTags
}

# Print the latest _adopt tag (without the _adopt suffix, in the repo's family) merged into the
# mirror branch $1, or nothing if the branch does not exist or holds no _adopt tag.
function latestAdoptOn() {
  if ! mirrorBranchExists "$1" ; then
    return 0
  fi
  git tag --merged "refs/remotes/origin/$1" | { grep -E '_adopt$' || true; } | sed 's/_adopt$//' \
    | familyTags | sortTags | tail -n 1
}

# Succeeds if build tag $1 is newer (version/build order) than build tag $2
function tagIsNewer() {
  local tag="$1" than="$2"
  [ "$tag" != "$than" ] && [ "$(printf '%s\n%s\n' "$than" "$tag" | sortTags | tail -n 1)" == "$tag" ]
}

# Print the new tags to mirror from the current upstream branch, oldest first, one "<tag> <target>"
# per line. $1 is the floor: the latest _adopt tag on R(B) if it has one, otherwise the latest
# build tag visible from the upstream branch. The candidates are the tags from the floor onwards
# that have no _adopt tag anywhere in the mirror repo and that have a target branch.
function listCandidateTags() {
  local floor="$1" adoptFile sorted tag target

  adoptFile=$(mktemp "${TMPDIR:-/tmp}/skaramirror-adopt.XXXXXX")
  git tag -l '*_adopt' | sed 's/_adopt$//' > "$adoptFile"

  # The floor is added to the sort input explicitly, in case it is not visible from $BRANCH
  sorted=$( { listBuildTags "$VISIBLE_REF"; echo "$floor"; } | sed '/^$/d' | awk '!seen[$0]++' \
              | sortTags | awk -v f="$floor" 'found{print} $0==f{found=1; print}' )

  for tag in $sorted; do
    if grep -Fxq -- "$tag" "$adoptFile" ; then
      continue
    fi
    target=$(targetBranchFor "$tag")
    if [ -n "$target" ]; then
      echo "$tag $target"
    fi
  done
  rm -f "$adoptFile"
  return 0
}

# Print the tags of $2 (newline separated, oldest first) that still need mirroring into the mirror
# branch $1: all of them if $1 does not exist yet, otherwise those newer than its latest _adopt tag.
function tagsNeededFor() {
  local target="$1" tags="$2" latest tag
  latest=$(latestAdoptOn "$target")
  if [ -z "$latest" ]; then
    printf '%s\n' "$tags"
    return 0
  fi
  for tag in $tags; do
    if tagIsNewer "$tag" "$latest"; then
      echo "$tag"
    fi
  done
}

# Create the <tag>_adopt tag on the current branch and add it to NEW_ADOPT_TAGS.
# _adopt tagging is strict: candidates have no _adopt tag anywhere, so finding one here is a bug
# in the tag selection and the job fails.
function tagAdopt() {
  local tag="$1" message="$2"
  local adoptTag="${tag}_adopt"

  if [ -n "$(git tag -l "$adoptTag")" ]; then
    echo "ERROR: ${adoptTag} already exists, so the selection of new tags is wrong"
    echo "Branches containing ${adoptTag}:"
    git branch -r --contains "refs/tags/$adoptTag" || true
    exit 1
  fi
  git tag -a "$adoptTag" -m "$message" || exit 1
  NEW_ADOPT_TAGS="${NEW_ADOPT_TAGS} ${adoptTag}"
}

# Merge a ref into the current branch. A conflict in generated-configure.sh is regenerated,
# any other conflict fails the job.
function mergeRef() {
  local message="$1" ref="$2"
  if ! git merge -m"$message" "$ref" ; then
    if resolveGeneratedConfigureConflict ; then
      git commit --no-edit || exit 1
    else
      git merge --abort
      exit 1
    fi
  fi
}

# Apply one patch with git am. A conflict in generated-configure.sh is regenerated, any other
# conflict fails the job. Empty patches are skipped.
function applyPatch() {
  local patchFile="$1"
  if [[ ! -s "$patchFile" ]]; then
    echo "Skipping empty patch: $(basename "$patchFile")"
    return 0
  fi
  if ! git am --ignore-whitespace -3 "$patchFile" ; then
    if resolveGeneratedConfigureConflict ; then
      git am --continue || exit 1
    else
      git am --abort
      exit 1
    fi
  fi
}

# For JDK 8 repos, regenerate generated-configure.sh after all patches have been applied.
# company_name.patch modifies jdk-options.m4 but does not include the generated file
# (unlike the alpine-jdk8u variant which bundles both). The JDK 8 configure wrapper
# runs the checked-in generated script, so without regeneration --with-company-name
# is unavailable at build time. autogen.sh is idempotent — if the patch already
# included the generated file (e.g. alpine-jdk8u/0002) this produces no diff.
function regenerateConfigureAfterPatches() {
  local AUTOGEN="common/autoconf/autogen.sh"
  local GENERATED="common/autoconf/generated-configure.sh"
  if [ ! -f "$AUTOGEN" ]; then
    echo "WARNING: $AUTOGEN not found — skipping $GENERATED regeneration"
    return 0
  fi
  echo "Regenerating $GENERATED after patch application"
  bash "$AUTOGEN" || exit 1
  if git diff --quiet "$GENERATED" ; then
    echo "$GENERATED already up to date, no commit needed"
  else
    git add "$GENERATED"
    git commit --no-edit -m "Regenerate generated-configure.sh after Adoptium patches" || exit 1
    echo "Committed regenerated $GENERATED"
  fi
}

# Apply the Adoptium patches to the current (release) branch, gated on README.JAVASE not existing
# (README.JAVASE is the Adoptium marker file — its absence means no patches have been applied yet)
function applyAdoptiumPatches() {
  local patchFile patchName
  if [ -f "$WORKSPACE/$GITHUB_REPO/README.JAVASE" ]; then
    echo "README.JAVASE already exists — patches already applied, skipping"
    return 0
  fi
  echo "Applying Adoptium patches for $GITHUB_REPO"

  # Step 1: top-level patches, except those overridden by a patch of the same name in
  # patches/<GITHUB_REPO>/
  for patchFile in "$PATCHES"*.patch; do
    [ -f "$patchFile" ] || continue
    patchName=$(basename "$patchFile")
    if [ -f "$PATCHES$GITHUB_REPO/$patchName" ]; then
      echo "Skipping top-level $patchName (overridden by patches/$GITHUB_REPO/$patchName)"
    else
      echo "Applying top-level patch: $patchName"
      applyPatch "$patchFile"
    fi
  done

  # Step 2: repo-specific patches from patches/<GITHUB_REPO>/ if that folder exists
  if [ -d "$PATCHES$GITHUB_REPO" ]; then
    for patchFile in "$PATCHES$GITHUB_REPO"/*.patch; do
      [ -f "$patchFile" ] || continue
      echo "Applying repo-specific patch: $(basename "$patchFile")"
      applyPatch "$patchFile"
    done
  fi

  if [[ "${VERSION}" == "8" ]]; then
    regenerateConfigureAfterPatches
  fi
}

# If the two newest build tags of the mirror branch $1 are on the same commit and only the older
# one has an _adopt tag, create the other _adopt tag too.
function tagSameCommitBuild() {
  local target="$1" sortedTags prevTag currentTag
  sortedTags=$(listBuildTags "$target")
  currentTag=$(printf '%s\n' "$sortedTags" | tail -n 1)
  prevTag=$(printf '%s\n' "$sortedTags" | tail -n 2 | head -n 1)
  echo "New $target build tag: $currentTag"
  if [ -z "$prevTag" ] || [ -z "$currentTag" ] || [ "$prevTag" == "$currentTag" ]; then
    return 0
  fi
  if [ "$(git rev-list -n 1 "$prevTag")" != "$(git rev-list -n 1 "$currentTag")" ]; then
    return 0
  fi
  echo "Current build tag commit is same as previous build tag commit: ${prevTag} == ${currentTag}"
  if [ -n "$(git tag -l "${prevTag}_adopt")" ] && [ -z "$(git tag -l "${currentTag}_adopt")" ]; then
    echo "Tagging new current $target tag ${currentTag}_adopt which is same commit as the previous ${prevTag}_adopt"
    tagAdopt "$currentTag" "Merged ${currentTag} into $target"
  fi
}

# Mirror the tags $2 (newline separated, oldest first) into the mirror branch $1:
#   $1 exists:        check it out and merge each tag newer than its latest _adopt tag
#   $1 is missing:    create it from the first tag, apply the Adoptium patches and _adopt tag that
#                     tag, then merge the rest
# Then push the branch and the new _adopt tags, and add $1 to TOUCHED_TARGETS.
function processTarget() {
  local target="$1" tags="$2" tag first

  NEW_ADOPT_TAGS=""
  tags=$(tagsNeededFor "$target" "$tags" | sed '/^$/d')
  if [ -z "$tags" ]; then
    echo "Nothing new for $target"
    gitPush origin "$target" || exit 1
    return 0
  fi

  if mirrorBranchExists "$target" ; then
    echo "Target $target exists, merging: $(echo $tags)"
    git checkout -f -B "$target" "origin/$target" || exit 1
  else
    first=$(printf '%s\n' "$tags" | head -n 1)
    tags=$(printf '%s\n' "$tags" | tail -n +2)
    echo "Target $target does not exist, creating it from $first"
    git checkout -f -B "$target" "$first" || exit 1
    CREATED_BASES="${CREATED_BASES}${target} ${first}"$'\n'
    applyAdoptiumPatches
    tagAdopt "$first" "Merged $first into $target"
  fi

  for tag in $tags; do
    echo "Merging build tag $tag into $target branch"
    mergeRef "Merging $tag into $target" "$tag"
    tagAdopt "$tag" "Merged $tag into $target"
  done

  if mirrorBranchExists "$target" ; then
    showNewCommits "$target"
  fi
  tagSameCommitBuild "$target"

  gitPush origin "$target" || exit 1
  # Push the new _adopt tags explicitly, in case no new commits were pushed (tags on the same commit)
  for tag in $NEW_ADOPT_TAGS; do
    echo "Pushing new tag: ${tag}"
    gitPush origin "$tag" || exit 1
  done
  TOUCHED_TARGETS="${TOUCHED_TARGETS} ${target}"
}

# Find the new tags visible from the upstream branch, and mirror them into their target branches.
# Sets TOUCHED_TARGETS to the mirror release branches created or advanced.
function mirrorNewTags() {
  local floor candidates targets target tags

  TOUCHED_TARGETS=""
  CREATED_BASES=""

  # Abort existing merge
  git merge --abort || true
  git reset --hard || true

  git fetch --all --tags

  # The floor is the latest _adopt tag on the release branch. If the release branch does not
  # exist, or holds no _adopt tag, it is the latest build tag on the upstream branch.
  floor=$(latestAdoptOn "$RELEASE_BRANCH")
  if [ -z "$floor" ]; then
    floor=$(listBuildTags "$VISIBLE_REF" | tail -n 1)
  fi
  echo "Floor for $RELEASE_BRANCH: ${floor:-<none>}"
  if [ -z "$floor" ]; then
    echo "No build tags on $BRANCH yet"
    return 0
  fi
  candidates=$(listCandidateTags "$floor")
  if [[ -z "$candidates" ]]; then
    echo "No new build tags to mirror from $BRANCH"
    # Ensure all local merges are pushed, in case an earlier run was interrupted before its push
    if git rev-parse -q --verify "refs/heads/$RELEASE_BRANCH" > /dev/null ; then
      gitPush origin "$RELEASE_BRANCH" || exit 1
    fi
    return 0
  fi

  targets=$(printf '%s\n' "$candidates" | awk '{print $2}' | awk '!seen[$0]++')
  for target in $targets; do
    tags=$(printf '%s\n' "$candidates" | awk -v t="$target" '$2==t{print $1}')
    if [[ "${DRY_RUN:-false}" == true ]]; then
      dryRunTarget "$target" "$tags"
    else
      processTarget "$target" "$tags"
    fi
  done
}

# DRY_RUN: print "tag → target (create|merge)" for each tag that would be mirrored, and change and
# push nothing.
function dryRunTarget() {
  local target="$1" tags="$2" tag first action
  tags=$(tagsNeededFor "$target" "$tags" | sed '/^$/d')
  first=$(printf '%s\n' "$tags" | head -n 1)
  for tag in $tags; do
    action="merge"
    if ! mirrorBranchExists "$target" && [ "$tag" == "$first" ]; then
      action="create from $tag"
    fi
    echo "DRY_RUN: $tag → $target ($action)"
  done
  echo "DRY_RUN: $(devBranchFor "$target") would be advanced from $target"
}

# Print the dev branch that belongs to the mirror release branch $1: dev, or dev_<sfx> for release_<sfx>
function devBranchFor() {
  if [[ "$1" == "release" ]]; then
    echo "dev"
  else
    echo "dev_${1#release_}"
  fi
}

# Create or advance the dev branch that belongs to the mirror release branch $1:
#   release        -> dev, from the upstream default branch
#   release_<sfx>  -> dev_<sfx>, from the upstream branch <sfx> if it exists, otherwise from the
#                     tag the release branch was created from
# and merge the release branch into it.
function advanceDev() {
  local rel="$1" dev upstream="" base

  dev=$(devBranchFor "$rel")
  if [[ "$rel" == "release" ]]; then
    upstream="skara/${SKARA_DEFAULT_BRANCH}"
  elif git rev-parse -q --verify "refs/remotes/skara/${rel#release_}" > /dev/null ; then
    upstream="skara/${rel#release_}"
  fi

  # Abort existing merge
  git merge --abort || true
  git reset --hard || true

  if mirrorBranchExists "$dev" ; then
    git checkout -f -B "$dev" "origin/$dev" || exit 1
  elif [[ -n "$upstream" ]]; then
    git checkout -f -B "$dev" "$upstream" || exit 1
  else
    base=$(printf '%s' "${CREATED_BASES:-}" | awk -v t="$rel" '$1==t{print $2}' | head -n 1)
    git checkout -f -B "$dev" "${base:-origin/$rel}" || exit 1
  fi

  if [[ -n "$upstream" ]]; then
    echo "Merging $upstream HEAD into $dev branch"
    mergeRef "Merging $upstream HEAD into $dev" "$upstream"
  fi
  # Merge latest patches from the release branch
  mergeRef "Merging latest patches from $rel branch" "origin/$rel"

  if mirrorBranchExists "$dev" ; then
    showNewCommits "$dev"
  fi
  gitPush origin "$dev" || exit 1
}

# Advance the dev branch of every release branch touched in this run. dev (or dev_<sfx>) of the
# release branch expected for this upstream branch is also advanced when that release branch
# exists, so the nightly branch follows the upstream head between tags.
function mirrorDevBranches() {
  local rel devList="$TOUCHED_TARGETS"
  if mirrorBranchExists "$RELEASE_BRANCH" ; then
    devList="${devList} ${RELEASE_BRANCH}"
  fi
  for rel in $(printf '%s\n' $devList | awk '!seen[$0]++'); do
    advanceDev "$rel"
  done
}

# When sourced (for example by the tests/ harness) only define the functions above
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  return 0
fi

checkArgs $#

GITHUB_REPO="$1"

# alpine-jdk8u mirrors from the upstream jdk8u Skara repo
# SKARA_REPO_URL is an optional override of the upstream repo location, used by the tests/ harness
if [[ -n "${SKARA_REPO_URL:-}" ]]; then
  SKARA_REPO="${SKARA_REPO_URL}"
elif [[ "${GITHUB_REPO}" == "alpine-jdk8u" ]]; then
  SKARA_REPO="https://github.com/openjdk/jdk8u"
else
  SKARA_REPO="https://github.com/openjdk/${GITHUB_REPO}"
fi

# aarch32-port-jdk8u mirrors to the Adoptium repo named aarch32-jdk8u (without the "port-" prefix)
if [[ "${GITHUB_REPO}" == "aarch32-port-jdk8u" ]]; then
  REPO=${2:-"git@github.com:adoptium/aarch32-jdk8u"}
else
  REPO=${2:-"git@github.com:adoptium/$GITHUB_REPO"}
fi

# Determine the default branch of the upstream Skara repo via git ls-remote (no API token needed)
SKARA_DEFAULT_BRANCH=$(git ls-remote --symref "${SKARA_REPO}" HEAD | grep '^ref:' | sed 's|ref: refs/heads/||;s/[[:space:]].*//' | tr -d '[:space:]')
if [[ -z "${SKARA_DEFAULT_BRANCH}" ]]; then
  echo "ERROR: Could not determine default branch for ${SKARA_REPO} - git ls-remote --symref returned unexpected output"
  exit 1
fi
echo "Upstream default branch: ${SKARA_DEFAULT_BRANCH}"

BRANCH=${BRANCH:=${SKARA_DEFAULT_BRANCH}}

if [[ "${BRANCH}" == "${SKARA_DEFAULT_BRANCH}" ]]; then
  RELEASE_BRANCH="release"
else
  RELEASE_BRANCH="release_${BRANCH}"
fi
VISIBLE_REF="skara/${BRANCH}"

IS_AARCH32=false
if [[ "${GITHUB_REPO}" == "aarch32-port-jdk8u" ]]; then
  IS_AARCH32=true
fi
GITHUB_REPO_REMOVE_aarch32=${GITHUB_REPO#"aarch32"}
VERSION=${GITHUB_REPO_REMOVE_aarch32//[!0-9]/}
# Regex expands aarch32-jdk8u as 328

# The family: the only tags of the repo that are ever mirrored (see TAG_MIRRORING_STRATEGY.md).
if [[ -z "${VERSION}" ]]; then
  FAMILY_REGEX='^jdk-[0-9]+\+[0-9]+$'
elif [[ "${VERSION}" == "8" ]]; then
  if [[ "${IS_AARCH32}" == true ]]; then
    FAMILY_REGEX='^jdk8u[0-9]+-b[0-9]+-aarch32-[0-9]+$'
  else
    FAMILY_REGEX='^jdk8u[0-9]+-b[0-9]+$'
  fi
else
  FAMILY_REGEX="^jdk-${VERSION}\\.0\\.[0-9]+(\\.[0-9]+)*\\+[0-9]+\$"
fi
echo "Upstream branch $BRANCH, mirror release branch $RELEASE_BRANCH, tag family: $FAMILY_REGEX"

# JDK11+ tag sorting:
# We use sort and tail to choose the latest tag in case more than one refers the same commit.
# Versions tags are formatted: jdk-V1[.V2[.V3[.V4[.V5[.V6[.V7]]]]]]+B (up to 7 version digits).
# Transform "-" to "." in tag so we can sort as: "jdk.V1[.V2...]+B"
# Pad with up to 6 zero fields (".0.0.0.0.0.0+") so single-digit versions (e.g. jdk-27)
# align up to 7 version components across fields 2 to 8.
# First, sort on build number (B):
jdk11plus_tag_sort1="sort -t+ -k2,2n"
# Second, (stable) sort on V1 through V7 (fields 2 through 8):
jdk11plus_tag_sort2="sort -t. -k2,2n -k3,3n -k4,4n -k5,5n -k6,6n -k7,7n -k8,8n"
# The sort command for build tags ignores "..+0" branch fork point tags — these mark where the next
# version branched off master and are not real builds.
jdk11plus_sort_core="sed 's/jdk-/jdk./g' | sed 's/+/.0.0.0.0.0.0+/g' | $jdk11plus_tag_sort1 | nl -n rz | $jdk11plus_tag_sort2 | sed 's/\.0\.0\.0\.0\.0\.0+/+/g' | cut -f2- | sed 's/jdk./jdk-/g'"
jdk11plus_sort_tags_cmd="grep -v _adopt | grep -v -- '-ga$' | grep -v '\+0$' | $jdk11plus_sort_core"

# JDK8 tag sorting:
# We use sort and tail to choose the latest tag in case more than one refers the same commit.
# Versions tags are formatted: jdkVu[.W]-bB; with V, W, B being numeric.
# First, sort on build number (B):
jdk8_tag_sort1="sort -tb -k2,2n"
# Second, (stable) sort on (V), (W)
jdk8_tag_sort2="sort -tu -k2,2n"
# Ignore "..-b00" branch fork point tags (same reasoning as jdk11+ above).
# Note: no "$" anchor — aarch32 tags embed -b00 mid-string, e.g. jdk8u504-b00-aarch32-20260731.
jdk8_sort_core="$jdk8_tag_sort1 | nl -n rz | $jdk8_tag_sort2  | cut -f2-"
jdk8_sort_tags_cmd="grep -v _adopt | grep -v -- '-ga$' | grep -v '\-b00' | $jdk8_sort_core"

if [[ "${VERSION}" == "8" ]]; then
  jdk_sort_tags_cmd="${jdk8_sort_tags_cmd}"
else
  jdk_sort_tags_cmd="${jdk11plus_sort_tags_cmd}"
fi

# For aarch32-port-jdk8u, the upstream Skara repo also contains non-aarch32 tags (inherited from
# the parent jdk8u repo). Prepend a filter so only tags containing "aarch32" are considered —
# this prevents non-aarch32 tags from being picked as the branch-point or merged into release/dev.
if [[ "${IS_AARCH32}" == true ]]; then
  jdk_sort_tags_cmd="grep 'aarch32' | ${jdk_sort_tags_cmd}"
fi

cloneGitHubRepo
addSkaralUpstream
performMergeFromSkaraIntoGit
mirrorNewTags
mirrorDevBranches
