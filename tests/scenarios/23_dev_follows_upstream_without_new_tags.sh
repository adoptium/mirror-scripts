#!/bin/bash
# dev follows the upstream default branch with its latest commits even when there is no new tag,
# and so does dev_<sfx> for an existing release_<sfx> (from the matching upstream branch).
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
setup_scenario jdk27u

up_build master jdk-27.0.1+7
up_build master jdk-27.0.1+9
up_push
mirror_ok master
assert_branch_exists dev

# plain commits, no new tag
up_commit master
up_commit master
up_push
head=$(git -C "$UPW" rev-parse master)
mirror_ok master
git -C "$MIRROR" merge-base --is-ancestor "$head" refs/heads/dev || fail "dev does not contain the latest master commit"
assert_no_tag jdk-27.0.1+10_adopt

# the same for a versioned branch that already has a release branch
up_build master jdk-27.0.2+0
up_branch jdk27.0.2 master
up_build jdk27.0.2 jdk-27.0.2+1
up_build jdk27.0.2 jdk-27.0.2+2
up_push
mirror_ok jdk27.0.2
assert_branch_exists release_jdk27.0.2
assert_branch_exists dev_jdk27.0.2

up_commit jdk27.0.2
up_push
head=$(git -C "$UPW" rev-parse jdk27.0.2)
mirror_ok jdk27.0.2
git -C "$MIRROR" merge-base --is-ancestor "$head" refs/heads/dev_jdk27.0.2 || fail "dev_jdk27.0.2 does not contain the latest jdk27.0.2 commit"

echo "OK"
