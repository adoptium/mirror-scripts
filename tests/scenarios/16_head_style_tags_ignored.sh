#!/bin/bash
# jdk27u also contains head-style tags (jdk-27+35). They are not in the jdkMMu family and are
# ignored: no release_jdk27 and no _adopt tag.
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
setup_scenario jdk27u

up_build master jdk-27.0.1+7
up_push
mirror_ok master

up_build master jdk-27+35
up_build master jdk-27.0.1+8
up_push
mirror_ok master
assert_tag_on jdk-27.0.1+8_adopt release
assert_no_tag jdk-27+35_adopt
assert_no_branch release_jdk27

up_branch jdk27 master
up_build jdk27 jdk-27+36
up_push
mirror_ok jdk27
assert_no_branch release_jdk27
assert_no_tag jdk-27+36_adopt

echo "OK"
