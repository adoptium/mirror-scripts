#!/bin/bash
# aarch32-port-jdk8u: tags carry a date suffix (jdk8u504-b01-aarch32-<date>). The dated -b00 fork
# point tag is ignored, and release_openjdk8u504 is created from the first dated build tag.
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
setup_scenario aarch32-port-jdk8u

up_build master jdk8u502-b01-aarch32-20260101
up_push
mirror_ok master
assert_tag_on jdk8u502-b01-aarch32-20260101_adopt release

up_branch openjdk8u504 master
up_build openjdk8u504 jdk8u504-b00-aarch32-20260105
up_build openjdk8u504 jdk8u504-b01-aarch32-20260106
up_build openjdk8u504 jdk8u504-b02-aarch32-20260107
up_push
mirror_ok openjdk8u504

assert_branch_exists release_openjdk8u504
assert_tag_on jdk8u504-b00-aarch32-20260105 release_openjdk8u504
assert_tag_on jdk8u504-b02-aarch32-20260107_adopt release_openjdk8u504
assert_no_tag jdk8u504-b00-aarch32-20260105_adopt

echo "OK"
