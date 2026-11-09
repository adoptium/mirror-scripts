#!/bin/bash
# No candidates is not an error. A branch that only has its +0 tag, or no tags at all, exits 0
# and creates no release or dev branch.
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
setup_scenario jdk27u

up_build master jdk-27.0.1+8
up_build master jdk-27.0.1+9
up_push
mirror_ok master

up_branch jdk27.0.1.1 master
up_build jdk27.0.1.1 jdk-27.0.1.1+0
up_branch jdk27.0.2 master
up_push

mirror_ok jdk27.0.1.1
mirror_ok jdk27.0.2
assert_branch_exists jdk27.0.1.1
assert_branch_exists jdk27.0.2
assert_no_branch release_jdk27.0.1.1
assert_no_branch release_jdk27.0.2
assert_no_branch dev_jdk27.0.1.1
assert_no_branch dev_jdk27.0.2
assert_no_tag jdk-27.0.1.1+0_adopt

echo "OK"
