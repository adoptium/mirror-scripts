#!/bin/bash
# Smoke test: plain master mirroring with sequential build tags, as in jdk11u to jdk25u.
# Covers: tags are merged in order and each gets an _adopt tag, a re-run is a no-op,
# and a later tag (including a new update version) is picked up.
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
setup_scenario jdk21u

up_build master jdk-21.0.32+7
up_build master jdk-21.0.32+8
up_push

mirror_ok
assert_branch_exists release
assert_branch_exists dev
# A brand new release branch starts at the newest tag, so only that one gets _adopt
assert_no_tag jdk-21.0.32+7_adopt
assert_tag_exists jdk-21.0.32+8_adopt
assert_tag_on jdk-21.0.32+8 release

# Second run with nothing new must succeed and change nothing
mirror_ok

# Next builds, including a new update version, arrive in order
up_build master jdk-21.0.32+9
up_build master jdk-21.0.33+1
up_push
mirror_ok
assert_tag_exists jdk-21.0.32+9_adopt
assert_tag_exists jdk-21.0.33+1_adopt
assert_tag_on jdk-21.0.33+1 release
assert_tag_on jdk-21.0.33+1 dev

echo "OK"
