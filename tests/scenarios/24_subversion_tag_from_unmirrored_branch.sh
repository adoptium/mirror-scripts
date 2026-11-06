#!/bin/bash
# B=jdk27.0.2 has no release branch yet and release has no _adopt tag (jdk27u today). The floor is
# the latest tag on jdk27.0.2, here the sub-version tag jdk-27.0.2.1+1. It is processed and goes to
# release_jdk27.0.2.1 (not release_jdk27.0.2), which is created from the tag itself.
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
setup_scenario jdk27u

up_build master jdk-27.0.1+9
up_push

up_branch jdk27.0.2 master
up_build jdk27.0.2 jdk-27.0.2+1
up_build jdk27.0.2 jdk-27.0.2.1+1
up_push

mirror_ok jdk27.0.2

assert_branch_exists release_jdk27.0.2.1
assert_branch_exists dev_jdk27.0.2.1
assert_tag_on jdk-27.0.2.1+1_adopt release_jdk27.0.2.1
assert_no_branch release_jdk27.0.2
assert_no_tag jdk-27.0.2+1_adopt

mirror_ok jdk27.0.2

echo "OK"
