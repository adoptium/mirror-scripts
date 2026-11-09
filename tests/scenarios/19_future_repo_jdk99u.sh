#!/bin/bash
# A repo version that does not exist today (jdk99u) must behave like jdk27u with no script change.
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
setup_scenario jdk99u

up_build master jdk-99.0.1+7
up_push
mirror_ok master

up_build master jdk-99.0.2+0
up_branch jdk99.0.2 master
up_build jdk99.0.2 jdk-99.0.2+1
up_build jdk99.0.2 jdk-99.0.2+2
up_build master jdk-99.0.1.0.2+0
up_branch whatever master
up_build whatever jdk-99.0.1.0.2+1
up_push

mirror_ok whatever
assert_tag_on jdk-99.0.1.0.2+1_adopt release_jdk99.0.1.0.2
mirror_ok jdk99.0.2
assert_tag_on jdk-99.0.2+2_adopt release_jdk99.0.2

up_merge master jdk99.0.2
up_push
mirror_ok master
assert_tag_not_on jdk-99.0.2+2_adopt release

mirror_ok jdk99.0.2
mirror_ok whatever
mirror_ok master

echo "OK"
