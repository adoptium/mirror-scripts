# TODO generalise this for the non adoptium build farm case
function checkArgs() {
  if [ "$1" -lt 1 ]; then
     echo Usage: "$0" '[jdk8u|jdk11u|jdk17u|jdk19u|...]'
     echo "Skara Repo supplied should match a repository in https://github.com/openjdk/"
     echo "For example, to mirror https://github.com/openjdk/jdk17u"
     echo "e.g. $0 jdk17u"
     exit 1
  fi
}

function cloneGitHubRepo() {
  cd "$WORKSPACE" || exit 1
  GITHUB_REPO=$1 # https://github.com/adoptium/adoptium/jdk17u.git
  if [ ! -d "$JDKVERSION" ] ; then
    echo "First time clone repo $GITHUB_REPO"
    git clone -q "$GITHUB_REPO" || exit 1
  else
    cd "$JDKVERSION" && git clean -fd && git fetch --all --tags
  fi
}

function readExpectedGATag() {
    source ${SCRIPT_DIR}/releasePlan.cfg
    jdkVersion=$1  # e.g jdk17u
    gaTagVariable="${jdkVersion}GA" # set gaTagVariable=jdk17uGA match releasePlan.cfg
    expectedTag=${!gaTagVariable} # get value, e.g: expectedTag=jdk-17.0.6
    echo ${expectedTag}
}

# this function is not in use, due to agent does not have "jq" to parse json payload
function queryGHAPI(){
  repo=$1 # adoptium/jdk8u, openjdk/jdk8u
  tag=$2 # jdk8u362-b05_adopt, jdk8u362-ga
  exist="$(curl -s -o /dev/null -w "%{http_code}" "https://api.github.com/repos/${repo}/git/refs/tags/${tag}")"
  if [ $exist == "200" ]; then
    echo "Found tag: ${tag} in ${repo}"
  else
    echo "Cannot find tag: ${tag} in ${repo}"
  fi
  echo ${exist}
}

# to check if the same _adopt scmReference tag has been used to trigger a release pipeline in the past
# if yes, wont trigger; if not, do the first time trigger
function checkPrevious() {
  if [ -f ${WORKSPACE}/tracking ]; then # already have tracking from previous
    local scmRef=$1 # _adopt scmReference tag we have found
    local trackerTag="$(cut -d '=' -f 2 ${WORKSPACE}/tracking)" # previousSCM=jdk-17.0.5+8_adopt

    if [[ "${scmRef}" == "${trackerTag}" ]]; then
        echo "Release tag ${trackerTag} has triggered a release pipeline build already in the current release"
        echo "Will not continue job"
        exit 0
    fi
  fi  
}
