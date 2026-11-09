#!/bin/bash
# A late patch branch, created after master has moved on, gets its own release_... branch from
# the first tag on it, and release is not touched.
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
setup_scenario jdk17u

up_build master jdk-17.0.21+1
up_build master jdk-17.0.21+2
up_build master jdk-17.0.21.1+0
up_branch jdk17.0.21.1 master
up_build master jdk-17.0.22+1
up_build jdk17.0.21.1 jdk-17.0.21.1+1
up_push
mirror_ok master
assert_tag_on jdk-17.0.22+1_adopt release

mirror_ok jdk17.0.21.1
assert_branch_exists release_jdk17.0.21.1
assert_tag_on jdk-17.0.21.1+1_adopt release_jdk17.0.21.1
assert_tag_not_on jdk-17.0.21.1+1_adopt release
assert_tag_not_on jdk-17.0.22+1 release_jdk17.0.21.1

mirror_ok jdk17.0.21.1
mirror_ok master

echo "OK"
