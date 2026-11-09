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
# Helpers for the skaraMirror.sh test scenarios. Source this from a scenario:
#
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
#
# A scenario builds a synthetic upstream ("Skara") repo, runs skaraMirror.sh against
# it once per branch (as the Jenkinsfile does) and asserts on the resulting Adoptium
# mirror repo. Everything is local (file paths), so no network or SSH is needed.
#
# Requires bash 3.2+ (macOS default) and git 2.32+ (GIT_CONFIG_GLOBAL).

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

T=""            # scenario temp dir
REPO=""         # repo name passed to skaraMirror.sh, for example jdk27u
UP=""           # bare upstream repo (stands in for https://github.com/openjdk/$REPO)
UPW=""          # working clone used to author upstream history
MIRROR=""       # bare mirror repo (stands in for git@github.com:adoptium/$REPO)
PATCHES_DIR=""  # test patch dir (contains only the README.JAVASE marker patch)
LAST_LOG=""
MIRROR_RC=0
MIRROR_RUNS=0
COUNTER=0

fail() {
  echo "ASSERTION FAILED: $*" >&2
  exit 1
}

_cleanup() {
  local rc=$?
  if [ "$rc" -ne 0 ] && [ -n "$LAST_LOG" ] && [ -f "$LAST_LOG" ]; then
    echo "---- last 60 lines of $(basename "$LAST_LOG") ----" >&2
    tail -n 60 "$LAST_LOG" >&2 || true
  fi
  if [ -n "$T" ] && [ -d "$T" ]; then
    if [ -n "${KEEP_TEST_DIRS:-}" ]; then
      echo "Keeping test dir: $T" >&2
    else
      rm -rf "$T"
    fi
  fi
  return "$rc"
}
trap _cleanup EXIT

# setup_scenario <repo-name>
# Creates the temp dir, isolated git config, bare upstream + mirror, and the test patch dir.
setup_scenario() {
  REPO="$1"
  T="$(mktemp -d "${TMPDIR:-/tmp}/mirrortest.XXXXXX")"
  T="$(cd "$T" && pwd -P)"
  mkdir -p "$T/logs"

  # Isolate from the developer's git configuration
  export GIT_CONFIG_GLOBAL="$T/gitconfig"
  export GIT_CONFIG_NOSYSTEM=1
  cat > "$GIT_CONFIG_GLOBAL" <<'EOF'
[user]
	name = Mirror Test
	email = mirror-test@example.com
[init]
	defaultBranch = master
[commit]
	gpgsign = false
[tag]
	gpgsign = false
[protocol "file"]
	allow = always
[advice]
	detachedHead = false
EOF

  UP="$T/upstream.git"
  UPW="$T/upstream-work"
  MIRROR="$T/mirror.git"
  PATCHES_DIR="$T/patches"

  git init -q --bare -b master "$UP"
  git init -q --bare -b master "$MIRROR"

  git init -q -b master "$UPW"
  git -C "$UPW" remote add origin "$UP"
  echo "initial" > "$UPW/README"
  git -C "$UPW" add README
  git -C "$UPW" commit -q -m "Initial commit"
  git -C "$UPW" push -q origin master

  # The mirror applies the patches in $PATCHES_DIR to a new release branch, and uses the
  # presence of README.JAVASE to know that it has done so. Provide just that marker patch.
  mkdir -p "$PATCHES_DIR"
  local scratch="$T/patch-scratch"
  git init -q -b master "$scratch"
  echo base > "$scratch/base"
  git -C "$scratch" add base
  git -C "$scratch" commit -q -m "base"
  echo "Adoptium test marker" > "$scratch/README.JAVASE"
  git -C "$scratch" add README.JAVASE
  git -C "$scratch" commit -q -m "Add README.JAVASE (test patch)"
  git -C "$scratch" format-patch -1 --stdout > "$PATCHES_DIR/readme-javase.patch"
}

# ---------------------------------------------------------------------------
# Upstream (Skara) side
# ---------------------------------------------------------------------------

# up_commit <branch>   add a unique commit to <branch>
up_commit() {
  COUNTER=$((COUNTER + 1))
  git -C "$UPW" checkout -q "$1"
  echo "$COUNTER" > "$UPW/file-$COUNTER"
  git -C "$UPW" add "file-$COUNTER"
  git -C "$UPW" commit -q -m "commit $COUNTER on $1"
}

# up_tag <tag> <branch>   lightweight tag at the head of <branch>
up_tag() {
  git -C "$UPW" tag "$1" "$2"
}

# up_branch <new-branch> <from-branch>
up_branch() {
  git -C "$UPW" branch "$1" "$2"
}

# up_merge <into-branch> <from-branch>   (always a merge commit)
up_merge() {
  git -C "$UPW" checkout -q "$1"
  git -C "$UPW" merge -q --no-ff -m "Merge $2 into $1" "$2"
}

# up_build <branch> <tag>   a new commit on <branch> tagged <tag>
up_build() {
  up_commit "$1"
  up_tag "$2" "$1"
}

# up_push   publish all branches and tags to the bare upstream
up_push() {
  git -C "$UPW" push -q origin --all
  git -C "$UPW" push -q origin --tags
}

# ---------------------------------------------------------------------------
# Running skaraMirror.sh
# ---------------------------------------------------------------------------

# run_mirror [branch]   run skaraMirror.sh for <branch> (default: the upstream default branch)
# Sets MIRROR_RC and LAST_LOG. Never aborts the scenario itself.
run_mirror() {
  local branch="${1:-}"
  MIRROR_RUNS=$((MIRROR_RUNS + 1))
  LAST_LOG="$T/logs/run-$MIRROR_RUNS-$(printf '%s' "${branch:-default}" | tr '/' '_').log"
  set +e
  (
    cd "$T"
    unset BRANCH
    if [ -n "$branch" ]; then
      export BRANCH="$branch"
    fi
    export MIRROR_WORKSPACE="$T/workspace"
    export MIRROR_PATCHES="$PATCHES_DIR"
    export SKARA_REPO_URL="$UP"
    bash "$REPO_ROOT/skaraMirror.sh" "$REPO" "$MIRROR"
  ) > "$LAST_LOG" 2>&1
  MIRROR_RC=$?
  set -e
}

# mirror_ok [branch]      run and require exit 0
mirror_ok() {
  run_mirror "$@"
  [ "$MIRROR_RC" -eq 0 ] || fail "skaraMirror.sh ${1:-<default branch>} exited $MIRROR_RC, expected 0"
}

# mirror_fails [branch]   run and require a non-zero exit
mirror_fails() {
  run_mirror "$@"
  [ "$MIRROR_RC" -ne 0 ] || fail "skaraMirror.sh ${1:-<default branch>} exited 0, expected a failure"
}

# ---------------------------------------------------------------------------
# Mirror (Adoptium) side
# ---------------------------------------------------------------------------

# mirror_plant_adopt_tag <tag> <branch>
# Creates (or extends) <branch> in the mirror with a new commit and puts the annotated <tag> on it.
# Used to simulate an _adopt tag that already exists somewhere.
mirror_plant_adopt_tag() {
  local tag="$1" branch="$2"
  local w="$T/mirror-plant"
  rm -rf "$w"
  git clone -q "$MIRROR" "$w" 2> /dev/null
  if git -C "$w" rev-parse -q --verify "origin/$branch" > /dev/null; then
    git -C "$w" checkout -q -b "$branch" "origin/$branch"
  else
    git -C "$w" checkout -q -b "$branch" "origin/master"
  fi
  COUNTER=$((COUNTER + 1))
  echo "$COUNTER" > "$w/planted-$COUNTER"
  git -C "$w" add "planted-$COUNTER"
  git -C "$w" commit -q -m "planted commit for $tag"
  git -C "$w" tag -a "$tag" -m "planted $tag"
  git -C "$w" push -q origin "$branch"
  git -C "$w" push -q origin "$tag"
}

assert_tag_exists() {
  git -C "$MIRROR" rev-parse -q --verify "refs/tags/$1" > /dev/null \
    || fail "tag $1 does not exist in the mirror"
}

assert_no_tag() {
  if git -C "$MIRROR" rev-parse -q --verify "refs/tags/$1" > /dev/null; then
    fail "tag $1 exists in the mirror but should not"
  fi
}

assert_branch_exists() {
  git -C "$MIRROR" rev-parse -q --verify "refs/heads/$1" > /dev/null \
    || fail "branch $1 does not exist in the mirror"
}

assert_no_branch() {
  if git -C "$MIRROR" rev-parse -q --verify "refs/heads/$1" > /dev/null; then
    fail "branch $1 exists in the mirror but should not"
  fi
}

# assert_tag_on <tag> <branch>   the tag's commit is reachable from the mirror branch
assert_tag_on() {
  assert_tag_exists "$1"
  assert_branch_exists "$2"
  git -C "$MIRROR" merge-base --is-ancestor "refs/tags/$1^{commit}" "refs/heads/$2" \
    || fail "tag $1 is not reachable from mirror branch $2"
}

# assert_tag_not_on <tag> <branch>   the tag exists but is not reachable from the mirror branch
assert_tag_not_on() {
  assert_tag_exists "$1"
  assert_branch_exists "$2"
  if git -C "$MIRROR" merge-base --is-ancestor "refs/tags/$1^{commit}" "refs/heads/$2"; then
    fail "tag $1 is reachable from mirror branch $2 but should not be"
  fi
}
