#!/bin/bash
# Head repo where master has no jdk-27+N build tag: release_jdk27 is created from the first
# jdk-27+N tag on the jdk27 branch. The jdk-27+0 fork point tag is not mirrored or _adopt tagged.
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
setup_scenario jdk

up_build master jdk-27+0
up_branch jdk27 master
up_build master jdk-28+0
up_build master jdk-28+1
up_build jdk27 jdk-27+1
up_push
mirror_ok master
assert_tag_on jdk-28+1_adopt release

mirror_ok jdk27
assert_branch_exists release_jdk27
assert_tag_on jdk-27+0 release_jdk27
assert_tag_on jdk-27+1_adopt release_jdk27
assert_no_tag jdk-27+0_adopt

echo "OK"
