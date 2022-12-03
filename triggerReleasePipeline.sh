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

# to local supporting functions
# TODO: this should be done for skaraMirror.sh too
source ${WORKSPACE}/common.sh

# pre-check args
checkArgs $#
# cleanup properties if exists from previous run
git clean -fd # same as rm -rf ${WORKSPACE}/properties but might also clean other dirty files
# for first time if does not have repo locally yet
cloneGitHubRepo

# fetch all new refs including tags from origin remote
cd "$WORKSPACE/$GITHUB_REPO"

# take latest -ga tag (sorted by time)
gaTag=$(git tag --sort=-v:refname | grep '\-ga' | head -1)
echo "latest GA tag: ${gaTag}"

# read expectedTag from cfg file (releasePlan.cfg) to see if this is the correct GA tag we want for release
expectedTag=$(readExpectedGATag $1)

# logic here is:
# - set expected version for each jdk version
# - check in to releasePlan.cfg
# - triggerReleasePipeline.sh get that expect version and compare with current GA tag
# - if GA tag (e.g jdk-19.0.2+5-ga) is greater or than expected (e.g jdk-19.0.2) => this is the correct GA we need
# - otherwise, we still need to wait for newer GA tag in repo=> exit till next hour to run job
if [[ $expectedTag > $gaTag ]]; then
  echo "$gaTag is not the GA tag we expect for this release! e.g $expectedTag-ga"
	exit # should not continue trigger logic
else
  echo "we will proceed with $gaTag to trigger build"
fi

# from -ga tag find original commit SHA and list all tags applied onto it, exclude -ga tag and append _adopt
scmReference=$(git rev-list -1 ${gaTag} | xargs git tag --points-at | grep  -v '\-ga')'_adopt'

# loop with 10m sleep if git-mirror has not applied the _adopt tag or if there is a merge conflict in git-mirror that we need to manual resolve
for i in {1..5}
do
  if [ $(git tag -l "${scmReference}") ]; then
    echo "Found tag: ${scmReference}"
    # write into properties file for release pipeline to get input from
    # existence of this properties file will be used in the jenkins job
    echo scmReference=$scmReference > ${WORKSPACE}/properties
    break # should continue trigger logic
  else
    echo "No ${scmReference} tag found yet, will sleep 10 minutes"
    sleep 10m
    git fetch --all --tags
  fi
done
