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


SKARA_REPO="https://github.com/openjdk/$1"
GITHUB_REPO="$1"
REPO=${2:-"https://github.com/adoptium/$GITHUB_REPO.git"}
BRANCH="master"

# to loal supporting functions
# TODO: this should be done for skaraMirror.sh too
source "$WORKSPACE"/common.sh


# TODO: jdk8 aarch32 case
# GITHUB_REPO_REMOVE_aarch32=${GITHUB_REPO#"aarch32"}
# VERSION=${GITHUB_REPO_REMOVE_aarch32//[!0-9]/}
# Regex expands aarch32-jdk8u as 328
# if [[ "${VERSION}" == "8" ]]; then
#   TAG_SEARCH="jdk${VERSION}*-*"
# else
#   TAG_SEARCH="jdk-${VERSION}*+*"
# fi

# pre-check args
checkArgs $#
# for first time if does not have repo locally yet
cloneGitHubRepo

# fetch all new refs including tags from origin remote
cd "$WORKSPACE/$GITHUB_REPO"

# take latest -ga tag (sorted by time)
gaTag=$(git tag --sort=-v:refname | grep '\-ga' | head -1)

# from -ga tag find original commit SHA and list all tags applied onto it , exclude -ga tag and append _adopt
scmReference=$(git rev-list -1 ${gaTag} | xargs git tag --points-at  | grep  -v '\-ga')'_adopt'

# loop with 10m sleep if git-mirror has not apply _adopt tag or merge conflict in git-mirror need to manual resolve
for i in {1..5}
do
  if [ $(git tag -l "${scmReference}") ]; then
    echo "Found tag: ${scmReference}"
    # write into properties file for release pipeline to get input from
    echo scmReference=$scmReference > properties
    break
  else
    echo "No ${scmReference} tag found yet, will sleep 10 minutes"
    sleep 10m
    git fetch --all --tags
  fi
done

# no need proceed next step in the build for trigger release pipeline
exit 128
