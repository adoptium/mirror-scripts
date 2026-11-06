#!/bin/bash
# jdk27u: jdk-27.0.2+BB tags are first seen from master (they go to release). When the jdk27.0.2
# branch is run later, tags that already have an _adopt tag are skipped and no second one is made.
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
setup_scenario jdk27u

up_build master jdk-27.0.1+9
up_push
mirror_ok master

up_build master jdk-27.0.2+0
up_build master jdk-27.0.2+1
up_build master jdk-27.0.2+2
up_push
mirror_ok master
assert_tag_on jdk-27.0.2+1_adopt release
assert_tag_on jdk-27.0.2+2_adopt release
assert_no_tag jdk-27.0.2+0_adopt

up_branch jdk27.0.2 master
up_build jdk27.0.2 jdk-27.0.2+3
up_push
mirror_ok jdk27.0.2
assert_branch_exists release_jdk27.0.2
assert_branch_exists dev_jdk27.0.2
assert_tag_on jdk-27.0.2+3_adopt release_jdk27.0.2
assert_tag_on jdk-27.0.2+2 release_jdk27.0.2
assert_tag_not_on jdk-27.0.2+3_adopt release

# Later the branch is merged into master: +3 already has its _adopt tag, nothing more happens
up_merge master jdk27.0.2
up_push
mirror_ok jdk27.0.2
mirror_ok master
assert_tag_not_on jdk-27.0.2+3_adopt release

echo "OK"
