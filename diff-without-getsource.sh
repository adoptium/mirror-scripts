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

################################################################################
# diff-without-getsource
#
# For finding the diff between an AdoptOpenJDK Git repo and the OpenJDK Mercurial
# Repo for Java versions >= jdk10
#
# 1. Clones the AdoptOpenJDK Git repo for a particular version
# 2. Clones the OpenJDK Mercurial repo for that same version
# 3. Runs a diff between the two
#
###########################

set -euo pipefail

function checkArgs() {
  if [ $# -lt 3 ]; then
     echo Usage: "$0" '[Adoptium Git Repo Version] [OpenJDK Mercurial Root Forest] [OpenJDK Mercurial Version]'
     echo ""
     echo "e.g. ./diff-without-getsource.sh jdk10u jdk-updates jdk10u"
     echo ""
     exit 1
  fi
}

checkArgs $@

git_repo_version=$1
hg_root_forest=$2
hg_repo_version=$3

function cleanUp() {
  rm -rf openjdk-git openjdk-hg || true
}

function cloneRepos() {
  echo "Adoptium Git Repo Version: ${git_repo_version}"
  echo "OpenJDK Mercurial Repo Version: ${hg_root_forest}/${hg_repo_version}"

  git clone -b master "https://github.com/adoptium/${git_repo_version}.git" openjdk-git || exit 1
  hg clone "https://hg.openjdk.java.net/${hg_root_forest}/${hg_repo_version}" openjdk-hg || exit 1
}

function runDiff() {
  diffNum=$(diff -rq openjdk-git openjdk-hg -x '.git' -x '.hg' -x '.hgtags' | wc -l)

  if [ "$diffNum" -gt 0 ]; then
    echo "ERROR - THE DIFF HAS DETECTED UNKNOWN FILES"
    diff -rq openjdk-git openjdk-hg -x '.git' -x '.hg' -x '.hgtags' | grep 'only in' || exit 1
    exit 1
  fi
}

function checkTags() {

  cd openjdk-git || exit 1
  gitTag=$(git describe --tags "$(git rev-list --tags --max-count=1)") || exit 1
  cd - || exit 1

  cd openjdk-hg || exit 1
  hgTag=$(hg log -r "." --template "{latesttag}\n") || exit 1
  cd - || exit 1

  if [ "$gitTag" == "$hgTag" ]; then
    echo "Tags are in sync"
  else
    echo "ERROR - THE TAGS ARE NOT IN SYNC"
    exit 1
  fi
}

cleanUp
cloneRepos
runDiff
checkTags