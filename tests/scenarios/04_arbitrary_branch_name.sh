#!/bin/bash
# Branch names are not a reliable key: the same sub-version tag gives the same result when it is
# only seen from an arbitrarily named upstream branch.
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
setup_scenario jdk17u

up_build master jdk-17.0.21+9
up_build master jdk-17.0.21.0.2+0
up_push
mirror_ok master

up_branch totally-unrelated-name master
up_build totally-unrelated-name jdk-17.0.21.0.2+1
up_push
mirror_ok totally-unrelated-name

assert_branch_exists release_jdk17.0.21.0.2
assert_tag_on jdk-17.0.21.0.2+1_adopt release_jdk17.0.21.0.2
assert_tag_not_on jdk-17.0.21.0.2+1_adopt release
assert_no_branch release_totally-unrelated-name

echo "OK"
