#!/bin/bash

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

#The -e flag causes the script to exit immediately if a command returns a non-zero exit status, 
#The -u flag causes the script to exit if it tries to use an undeclared variable, 
#The -o pipefail flag causes the script to exit if any command in a pipeline returns a non-zero exit status. 
set -euo pipefail

### Context (example):
### upstream skara creats tags jdk8u352-b08, then add jdk8u352-ga onto the same SHA on GA day
### skaraMirror merge jdk8u352-b08 onto release branch and tag it as jdk8u352-b08_adopt
### official release use jdk8u352-b08_adopt
### Input args: $jdkversion <adoptium_repo_url> <feature_branch_name>

JDKVERSION="$1"
ADOPTIUM_REPO=${2:-"https://github.com/adoptium/$JDKVERSION.git"}
BRANCH=${3:-"master"}

# Since we have "jdk8u" in the code, we need to create another lever of "workspace"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
mkdir -p $SCRIPT_DIR/workspace
WORKSPACE=$SCRIPT_DIR/workspace

# load local supporting functions
# TODO: this should be done for skaraMirror.sh too
source ${SCRIPT_DIR}/common.sh

# pre-check args
checkArgs $#

# cleanup properties if exists from previous run
git clean -fd # same as rm -rf ${SCRIPT_DIR}/properties but wont touch ${WORKSPACE}/tracking file

# for first time if does not have repo locally yet
cloneGitHubRepo $ADOPTIUM_REPO

# read expectedTag from cfg file (releasePlan.cfg) to see if this is the correct GA tag we want for release
expectedTag=$(readExpectedGATag $JDKVERSION)
echo "Expected release tag: ${expectedTag}"

# fetch all new refs including tags from origin remote
cd "$WORKSPACE/$JDKVERSION"

# get latest -ga tag (sorted by time) in repo
latestGaTag=$(git tag --sort=-v:refname | grep '\-ga' | sort -V -r| head -1)
echo "Latest GA tag: ${latestGaTag}"

# from -ga tag find original commit SHA then list all tags point to the this SHA(exclude -ga tag) => orignal tag(s) from skara
# in rare case, there might be more tags than the one we want
# convert from multiple line string into Array and use the first one from the list which is supposed to have _adopt tag
scmReferenceString="$(git rev-list -1 ${latestGaTag} | xargs git tag --points-at  | grep  -v '\-ga')"
scmReferenceList=($scmReferenceString)
# append _adopt => release tag we use in adoptium
scmReference="${scmReferenceList[0]}_adopt"

# check if we need to proceed when scmReference has already triggered release pipeline in the past
checkPrevious ${scmReference}

# get the older tag name between the latest GA tag and expected tag
olderTag="$(echo -e "${expectedTag}\n${latestGaTag}" | sort -V | head -n1)"

# if GA tag (e.g jdk-19.0.2+5-ga) is greater or equal than expected (e.g jdk-19.0.2) => this is the correct GA we need
if [[ "${expectedTag}" == "${olderTag}" || "${expectedTag}" == "${latestGaTag}" ]]; then
  echo "We will proceed with ${latestGaTag} to trigger build"
else
  echo "${latestGaTag} is not the GA tag we expect for this release! We want e.g ${expectedTag}-ga or a higher GA tag"
  exit 0 # should not continue trigger logic
fi

# loop with 10m sleep if git-mirror has not applied the _adopt tag or if there is a merge conflict in git-mirror that we need to manual resolve
for i in {1..5}
do
  if [ $(git tag -l "${scmReference}") ]; then
    echo "Found tag: ${scmReference}"
    # write into properties file for release pipeline to get input from
    # existence of this file will be used in jenkins job as if should continue trigger logic
    echo scmReference=$scmReference > ${SCRIPT_DIR}/properties
    # also write into a tracking file which can avoid mulitple triggering to release pipeline
    echo previousSCM=$scmReference > ${WORKSPACE}/tracking
    break # should continue trigger logic
  else
    echo "No ${scmReference} tag found yet, will sleep 10 minutes and check again"
    sleep 10m
    git fetch --all --tags
  fi
done
