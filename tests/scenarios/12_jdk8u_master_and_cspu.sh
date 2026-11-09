#!/bin/bash
# jdk8u master: mainline versions end in 2 (502, 512, ...), builds are jdk8uNNN-bBB.
# -ga and -b00 fork point tags are never mirrored or _adopt tagged.
# A CSPU branch (openjdk8u504, version not ending in 2) is merged into master after its builds
# are tagged on the branch; those tags belong to release_openjdk8u504 only.
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
setup_scenario jdk8u

up_build master jdk8u502-b01
up_build master jdk8u502-b02
up_tag jdk8u502-ga master
up_push
mirror_ok master
assert_tag_on jdk8u502-b02_adopt release
assert_no_tag jdk8u502-ga_adopt

up_branch openjdk8u504 master
up_build openjdk8u504 jdk8u504-b00
up_build openjdk8u504 jdk8u504-b01
up_build openjdk8u504 jdk8u504-b02
up_tag jdk8u504-ga openjdk8u504
up_push
mirror_ok openjdk8u504

up_merge master openjdk8u504
up_build master jdk8u512-b01
up_build master jdk8u512-b02
up_tag jdk8u512-ga master
up_push
mirror_ok master

assert_tag_on jdk8u504-b02_adopt release_openjdk8u504
assert_tag_not_on jdk8u504-b02_adopt release
assert_no_tag jdk8u504-b00_adopt
assert_no_tag jdk8u504-ga_adopt
assert_tag_on jdk8u512-b02_adopt release
assert_no_tag jdk8u512-b00_adopt
assert_no_tag jdk8u512-ga_adopt

mirror_ok openjdk8u504
mirror_ok master

echo "OK"
