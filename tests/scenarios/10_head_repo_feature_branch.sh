#!/bin/bash
# jdk (head) repo. jdk-28+N on master goes to release; once jdk27 exists, jdk-27+N tags seen from
# jdk27 go to release_jdk27, created from the first of those tags.
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
setup_scenario jdk

up_build master jdk-27+0
up_build master jdk-27+24
up_push
mirror_ok master
up_build master jdk-27+25
up_push
mirror_ok master
assert_tag_on jdk-27+25_adopt release

up_branch jdk27 master
up_build master jdk-28+0
up_build master jdk-28+1
up_build master jdk-28+2
up_push
mirror_ok master
assert_tag_on jdk-28+2_adopt release
assert_tag_on jdk-28+1_adopt release

# nothing to do for the new feature branch yet
mirror_ok jdk27
assert_no_branch release_jdk27

up_build jdk27 jdk-27+26
up_push
mirror_ok jdk27
assert_branch_exists release_jdk27
assert_branch_exists dev_jdk27
assert_tag_on jdk-27+25 release_jdk27
assert_tag_on jdk-27+26_adopt release_jdk27
assert_tag_not_on jdk-27+26_adopt release
assert_tag_not_on jdk-28+2 release_jdk27
assert_no_tag jdk-28+0_adopt
assert_no_tag jdk-27+0_adopt

mirror_ok master
mirror_ok jdk27

echo "OK"
