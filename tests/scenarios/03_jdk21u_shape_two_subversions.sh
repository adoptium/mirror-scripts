#!/bin/bash
# The jdk21u shape: jdk-21.0.13.0.2+1 and jdk-21.0.13.0.3+1 are seen from a branch called
# jdk21.0.13.1, which is merged into master. Each tag gets its own release branch, created from the
# tag itself (not from its +0 tag).
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
setup_scenario jdk21u

up_build master jdk-21.0.13+8
up_build master jdk-21.0.13+9
up_tag jdk-21.0.13.0.2+0 master
up_tag jdk-21.0.13.0.3+0 master
up_push
mirror_ok master
assert_tag_exists jdk-21.0.13+9_adopt

# both sub-version builds hang off the same commit but are not ancestors of each other
up_branch jdk21.0.13.1 master
up_branch side master
up_build jdk21.0.13.1 jdk-21.0.13.0.2+1
up_build side jdk-21.0.13.0.3+1
up_merge jdk21.0.13.1 side
up_build jdk21.0.13.1 jdk-21.0.13.1+1
up_push
mirror_ok jdk21.0.13.1

# the new release_jdk21.0.13.1 is created from the latest tag on the branch
assert_branch_exists release_jdk21.0.13.1
assert_tag_on jdk-21.0.13.1+1_adopt release_jdk21.0.13.1

# the branch is merged into master: the master run mirrors the two sub-version tags
up_merge master jdk21.0.13.1
up_push
mirror_ok master

assert_branch_exists release_jdk21.0.13.0.2
assert_branch_exists release_jdk21.0.13.0.3
assert_branch_exists dev_jdk21.0.13.0.2
assert_branch_exists dev_jdk21.0.13.0.3
assert_tag_on jdk-21.0.13.0.2+1_adopt release_jdk21.0.13.0.2
assert_tag_on jdk-21.0.13.0.3+1_adopt release_jdk21.0.13.0.3
assert_no_tag jdk-21.0.13.0.2+0_adopt
assert_no_tag jdk-21.0.13.0.3+0_adopt
# release is untouched by the sub-version tags
assert_tag_not_on jdk-21.0.13.0.2+1_adopt release
assert_tag_not_on jdk-21.0.13.1+1_adopt release

mirror_ok jdk21.0.13.1
mirror_ok master

echo "OK"
