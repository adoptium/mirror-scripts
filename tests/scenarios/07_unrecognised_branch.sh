#!/bin/bash
# An upstream branch whose name is not a version (a port, a project) is still rebased and pushed.
# Master-shape tags seen from it belong to the default-branch run, so nothing is created for it.
# The job does not fail.
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
setup_scenario jdk21u

up_build master jdk-21.0.32+7
up_push
mirror_ok master

up_branch some-project master
up_build some-project jdk-21.0.32+8
up_push
mirror_ok some-project

assert_branch_exists some-project
assert_no_branch release_some-project
assert_no_branch dev_some-project
assert_no_tag jdk-21.0.32+8_adopt

echo "OK"
