#!/bin/bash
# aarch32-port-jdk8u: same rules as jdk8u with an extra -aarch32-<date> suffix on every tag.
# Only tags with the suffix are mirrored, -b00 fork points and -ga are ignored, and plain
# jdk8u tags inherited from the parent repo are not mirrored.
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
setup_scenario aarch32-port-jdk8u

up_build master jdk8u502-b01
up_build master jdk8u502-b01-aarch32-20260101
up_build master jdk8u502-b02-aarch32-20260102
up_build master jdk8u502-b03
up_build master jdk8u512-b00-aarch32-20260201
up_push
mirror_ok master

assert_tag_on jdk8u502-b02-aarch32-20260102_adopt release
assert_no_tag jdk8u502-b03_adopt
assert_no_tag jdk8u512-b00-aarch32-20260201_adopt

up_build master jdk8u512-b01-aarch32-20260203
up_tag jdk8u512-ga master
up_push
mirror_ok master
assert_tag_on jdk8u512-b01-aarch32-20260203_adopt release
assert_no_tag jdk8u512-ga_adopt

mirror_ok master

echo "OK"
