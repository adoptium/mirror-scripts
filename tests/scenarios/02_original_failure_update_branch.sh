#!/bin/bash
# The original failure: jdk-27.0.1+9 is tagged on the upstream update branch jdk27.0.1, which is
# later merged into master. The Jenkinsfile mirrors the update branch first, then master.
#
# release_jdk27.0.1 does not exist yet, so it is created from the latest tag on jdk27.0.1
# (jdk-27.0.1+9) and that tag is _adopt tagged. When master is mirrored afterwards, +9 already has
# its _adopt tag and is not tagged a second time. The older +8 is picked up by the master run.
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
setup_scenario jdk27u

up_build master jdk-27.0.1+0
up_build master jdk-27.0.1+7
up_push
mirror_ok master
assert_tag_on jdk-27.0.1+7_adopt release

up_branch jdk27.0.1 master
up_build jdk27.0.1 jdk-27.0.1+8
up_build jdk27.0.1 jdk-27.0.1+9
up_push
mirror_ok jdk27.0.1
assert_branch_exists release_jdk27.0.1
assert_branch_exists dev_jdk27.0.1
assert_tag_on jdk-27.0.1+9_adopt release_jdk27.0.1
assert_no_tag jdk-27.0.1+0_adopt

# Oracle merges the update branch into master
up_merge master jdk27.0.1
up_push
mirror_ok master
assert_tag_on jdk-27.0.1+8_adopt release
# +9 has exactly one _adopt tag, on release_jdk27.0.1 only, and is not merged into release by tag
assert_tag_not_on jdk-27.0.1+9_adopt release
assert_tag_on jdk-27.0.1+9_adopt release_jdk27.0.1

# Further runs are no-ops
mirror_ok jdk27.0.1
mirror_ok master

echo "OK"
