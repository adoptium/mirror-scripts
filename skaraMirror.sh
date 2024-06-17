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
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
mkdir -p $SCRIPT_DIR/workspace
WORKSPACE=$SCRIPT_DIR/workspace
PATCHES=$SCRIPT_DIR/patches/

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

function cloneGitHubRepo() {
  cd "$WORKSPACE" || exit 1
  # If we don't have a $GITHUB_REPO locally then clone it from adoptium/$GITHUB_REPO.git
  if [ ! -d "$GITHUB_REPO" ] ; then
    git clone "$REPO" "$GITHUB_REPO" || exit 1
  fi
}

function addSkaralUpstream() {
  cd "$WORKSPACE/$GITHUB_REPO" || exit 1

  git fetch --all
  if ! git checkout -f "$BRANCH" ; then
    if ! git rev-parse -q --verify "origin/$BRANCH" ; then
      git checkout -b "$BRANCH" || exit 1
    else
      git checkout -b "$BRANCH" origin/"$BRANCH" || exit 1
    fi
  else
    git reset --hard origin/"$BRANCH" || echo "Not resetting as no upstream exists"
  fi

  # shellcheck disable=SC2143
  if [ -z "$(git remote -v | grep 'skara')" ] ; then
    echo "Initial setup of $SKARA_REPO"
    git remote add skara "$SKARA_REPO"
  fi
}

function performMergeFromSkaraIntoGit() {
  git fetch skara --tags

  git rebase "skara/$BRANCH" "$BRANCH"

  git push -u origin "$BRANCH" || exit 1
  git push origin "$BRANCH" --tags || exit 1
}

# Merge master(New tagged builds only) into release branch as we build
# off release branch at the Adoptium JDK Build farm for release builds
# release branch contains patches that Adoptium JDK has beyond upstream OpenJDK tagged builds
function performMergeIntoReleaseFromMaster() {

  # Abort existing merge
  git merge --abort || true
  git reset --hard || true

  # Fetch latest and get latest master build tag
  git fetch --all --tags

  buildTags=$(git tag --merged origin/"$BRANCH" $TAG_SEARCH || exit 1)
  sortedBuildTags=$(echo "$buildTags" | eval "$jdk_sort_tags_cmd" || exit 1)

  if ! git checkout -f "$RELEASE_BRANCH" ; then
    if ! git rev-parse -q --verify "origin/$RELEASE_BRANCH" ; then
      currentBuildTag=$(echo "$buildTags" | eval "$jdk_sort_tags_cmd" | tail -1 || exit 1)
      git checkout -b "$RELEASE_BRANCH" $currentBuildTag || exit 1
    else
      git checkout -b "$RELEASE_BRANCH" "origin/$RELEASE_BRANCH" || exit 1
    fi
  else
    git reset --hard "origin/$RELEASE_BRANCH" || echo "Not resetting as no upstream exists"
  fi

  # Apply our patches to release branch
  echo "Checking if patches need to be applied for $GITHUB_REPO"

  # actions ignore branch patch is for > jdk11u
  if [[ "$GITHUB_REPO" != "jdk8u" ]] && [[ "$GITHUB_REPO" != "aarch32-port-jdk8u" ]] && [[ "$GITHUB_REPO" != "jdk11u" ]]; then
    # check to see if patch has already been applied
    if ! grep -q "\\- dev" "$WORKSPACE/$GITHUB_REPO/.github/workflows/main.yml"; then
      echo "Applying actions-ignore-branches.patch"
      git am $PATCHES/actions-ignore-branches.patch
    fi
  fi

  # README.JAVASE patch needed for all repos
  if [ ! -f "$WORKSPACE/$GITHUB_REPO/README.JAVASE" ]; then
    echo "Applying README.JAVASE.patch"
    git am $PATCHES/readme-javase.patch
  fi

  # Find the latest release tag that is not in releaseTagExcludeList
  releaseTags=$(git tag --merged "$RELEASE_BRANCH" $TAG_SEARCH || exit 1)
  sortedReleaseTags=$(echo "$releaseTags" | eval "$jdk_sort_tags_cmd" || exit 1)
  currentReleaseTag=""
  for tag in $sortedReleaseTags; do
    skipThisTag=false
    # Check if tag is in the releaseTagExcludeList, if so it can't be the current tag
    if [ -n "${releaseTagExcludeList-}" ] ; then
      for skipTag in $releaseTagExcludeList; do
        if [ "x$tag" == "x$skipTag" ]; then
          echo "Skipping excluded tag $tag from current list"
          skipThisTag=true
        fi
      done
    fi
    if [[ "$skipThisTag" == false ]]; then
      currentReleaseTag="$tag"
    fi
  done

  echo "Current $RELEASE_BRANCH build tag: $currentReleaseTag"

  # Merge any new builds since current release build tag
  foundCurrentReleaseTag=false
  newAdoptTags=""
  for tag in $sortedBuildTags; do
    if [[ "$foundCurrentReleaseTag" == false ]]; then
      if [ "x$tag" == "x$currentReleaseTag" ]; then
        foundCurrentReleaseTag=true
      fi
    else
      mergeTag=true
      # Check if tag is in the releaseTagExcludeList, if so do not bring it into the release branch
      # and do not create an _adopt tag
      if [ -n "${releaseTagExcludeList-}" ] ; then
        for skipTag in $releaseTagExcludeList; do
          if [ "x$tag" == "x$skipTag" ]; then
           mergeTag=false
           echo "Skipping merge of excluded tag $tag"
          fi
        done
      fi
      if [[ "$mergeTag" == true ]]; then
        echo "Merging build tag $tag into $RELEASE_BRANCH branch"
        git merge -m"Merging $tag into $RELEASE_BRANCH" $tag || exit 1
        git tag -a "${tag}_adopt" -m "Merged $tag into $RELEASE_BRANCH" || exit 1
        newAdoptTags="${newAdoptTags} ${tag}_adopt"
      fi
    fi
  done

  if git rev-parse -q --verify "origin/$RELEASE_BRANCH" ; then
    git --no-pager log --oneline "origin/$RELEASE_BRANCH..$RELEASE_BRANCH"
  fi

  # Find the latest and previous release tags that is not in releaseTagExcludeList
  releaseTags=$(git tag --merged "$RELEASE_BRANCH" $TAG_SEARCH || exit 1)
  sortedReleaseTags=$(echo "$releaseTags" | eval "$jdk_sort_tags_cmd" || exit 1)
  prevReleaseTag=""
  currentReleaseTag=""
  for tag in $sortedReleaseTags; do
    skipThisTag=false
    # Check if tag is in the releaseTagExcludeList, if so it can't be the current tag
    if [ -n "${releaseTagExcludeList-}" ] ; then
      for skipTag in $releaseTagExcludeList; do
        if [ "x$tag" == "x$skipTag" ]; then
          echo "Skipping excluded tag $tag from current list"
          skipThisTag=true
        fi
      done
    fi
    if [[ "$skipThisTag" == false ]]; then
      prevReleaseTag="${currentReleaseTag}"
      currentReleaseTag="$tag"
    fi
  done
  echo "New $RELEASE_BRANCH build tag: $currentReleaseTag"

  git push --tags origin "$RELEASE_BRANCH" || exit 1

  # Check if the last two build tags are the same commit, and ensure we have tagged both _adopt tags
  if [ "x$prevReleaseTag" != "x" ]; then
    prevCommit=$(git rev-list -n 1 ${prevReleaseTag})
    currentCommit=$(git rev-list -n 1 ${currentReleaseTag})
    if [ "${prevCommit}" == "${currentCommit}" ] ; then
      echo "Current build tag commit is same as previous build tag commit: ${prevReleaseTag} == ${currentReleaseTag}"
      prevReleaseAdoptTag="${prevReleaseTag}_adopt"
      currentReleaseAdoptTag="${currentReleaseTag}_adopt"
      if [ "$(git tag -l "$prevReleaseAdoptTag")" != "" ]; then
        if [ "$(git tag -l "$currentReleaseAdoptTag")" == "" ]; then
          echo "Tagging new current $RELEASE_BRANCH tag ${currentReleaseAdoptTag} which is same commit as the previous ${prevReleaseAdoptTag}"
          git tag -a "${currentReleaseAdoptTag}" -m "Merged ${currentReleaseTag} into $RELEASE_BRANCH" || exit 1
          newAdoptTags="${newAdoptTags} ${currentReleaseAdoptTag}"
        fi
      fi
    fi
  fi

  # Ensure all new _adopt tags are pushed in case no new commits were pushed, eg.multiple tags on same commit
  for tag in $newAdoptTags; do
    echo "Pushing new tag: ${tag}"
    git push origin ${tag} || exit 1
  done
}

# Merge master(HEAD) into dev as we build off dev at the Adoptium JDK Build farm for Nightlies
# dev contains patches that Adoptium JDK has beyond upstream OpenJDK
function performMergeIntoDevFromMaster() {

  # Abort existing merge
  git merge --abort || true
  git reset --hard || true

  # Fetch latest and get latest master build tag
  git fetch --all --tags

  if ! git checkout -f "$DEV_BRANCH" ; then
    if ! git rev-parse -q --verify "origin/$DEV_BRANCH" ; then
      git checkout -b "$DEV_BRANCH" || exit 1
    else
      git checkout -b "$DEV_BRANCH" "origin/$DEV_BRANCH" || exit 1
    fi
  else
    git reset --hard "origin/$DEV_BRANCH" || echo "Not resetting as no upstream exists"
  fi

  devTags=$(git tag --merged "$DEV_BRANCH" $TAG_SEARCH || exit 1)
  currentDevTag=$(echo "$devTags" | eval "$jdk_sort_tags_cmd" | tail -1 || exit 1)
  echo "Current $DEV_BRANCH build tag: $currentDevTag"

  # Merge master "HEAD"
  echo "Merging origin/$BRANCH HEAD into $DEV_BRANCH branch"
  git merge -m"Merging origin/$BRANCH HEAD into $DEV_BRANCH" origin/"$BRANCH" || exit 1

  # Merge latest patches from "release" branch
  git merge -m"Merging latest patches from $RELEASE_BRANCH branch" "origin/$RELEASE_BRANCH" || exit 1

  if git rev-parse -q --verify "origin/$DEV_BRANCH" ; then
    git --no-pager log --oneline "origin/$DEV_BRANCH..$DEV_BRANCH"
  fi

  devTags=$(git tag --merged "$DEV_BRANCH" $TAG_SEARCH || exit 1)
  currentDevTag=$(echo "$devTags" | eval "$jdk_sort_tags_cmd" | tail -1 || exit 1)
  echo "New $DEV_BRANCH build tag: $currentDevTag"

  git push origin "$DEV_BRANCH" || exit 1
}

checkArgs $#

SKARA_REPO="https://github.com/openjdk/$1"
GITHUB_REPO="$1"
REPO=${2:-"git@github.com:adoptium/$GITHUB_REPO"}
BRANCH=${BRANCH:=master}

# Does this OpenJDK repo support version branching?
VERSION_BRANCHING=false

# jdk(head) is only repository currently supporting version branches
if [[ "${GITHUB_REPO}" == "jdk" ]]; then
  VERSION_BRANCHING=true
fi

if [[ "${VERSION_BRANCHING}" == false ]] || [[ "${BRANCH}" == "master" ]]; then
  RELEASE_BRANCH="release"
  DEV_BRANCH="dev"
else
  RELEASE_BRANCH="release_${BRANCH}"
  DEV_BRANCH="dev_${BRANCH}"
fi

GITHUB_REPO_REMOVE_aarch32=${GITHUB_REPO#"aarch32"}
VERSION=${GITHUB_REPO_REMOVE_aarch32//[!0-9]/}
# Regex expands aarch32-jdk8u as 328
if [[ "${VERSION}" == "8" ]]; then
  TAG_SEARCH="jdk${VERSION}*-*"
elif [[ -n "${VERSION}" ]]; then
  TAG_SEARCH="jdk-${VERSION}*+*"
else
  # jdk(head) repo tag sort finds latest tag for this repo & branch, note jdk(head) contains multiple versions
  TAG_SEARCH="jdk-*+*"
fi

# JDK11+ tag sorting:
# We use sort and tail to choose the latest tag in case more than one refers the same commit.
# Versions tags are formatted: jdk-V[.W[.X[.P]]]+B; with V, W, X, P, B being numeric.
# Transform "-" to "." in tag so we can sort as: "jdk.V[.W[.X[.P]]]+B"
# Transform "+" to ".0.+" during the sort so that .P (patch) is defaulted to "0" for those
# that don't have one, and the trailing "." to terminate the 5th field from the +
# First, sort on build number (B):
jdk11plus_tag_sort1="sort -t+ -k2,2n"
# Second, (stable) sort on (V), (W), (X), (P): P(Patch) is optional and defaulted to "0"
jdk11plus_tag_sort2="sort -t. -k2,2n -k3,3n -k4,4n -k5,5n"
# Ignore "..+0" branch fork point tags 
jdk11plus_sort_tags_cmd="grep -v _adopt | grep -v '\+0$' | sed 's/jdk-/jdk./g' | sed 's/+/.0.0+/g' | $jdk11plus_tag_sort1 | nl -n rz | $jdk11plus_tag_sort2 | sed 's/\.0\.0+/+/g' | cut -f2- | sed 's/jdk./jdk-/g'"

# JDK8 tag sorting:
# We use sort and tail to choose the latest tag in case more than one refers the same commit.
# Versions tags are formatted: jdkVu[.W]-bB; with V, W, B being numeric.
# First, sort on build number (B):
jdk8_tag_sort1="sort -tb -k2,2n"
# Second, (stable) sort on (V), (W)
jdk8_tag_sort2="sort -tu -k2,2n"
# Ignore "..-b00" branch fork point tags
jdk8_sort_tags_cmd="grep -v _adopt | grep -v '\-b00$' | $jdk8_tag_sort1 | nl -n rz | $jdk8_tag_sort2  | cut -f2-"


if [[ "${VERSION}" == "8" ]]; then
  jdk_sort_tags_cmd="${jdk8_sort_tags_cmd}"
else
  jdk_sort_tags_cmd="${jdk11plus_sort_tags_cmd}"
fi

cloneGitHubRepo
addSkaralUpstream
performMergeFromSkaraIntoGit
performMergeIntoReleaseFromMaster
performMergeIntoDevFromMaster
