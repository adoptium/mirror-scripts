#!/bin/bash
# A legacy _adopt tag of any shape on release (here jdk-17.0.21.0.3+1_adopt) raises the floor:
# older tags that were never mirrored stay untouched, newer ones are picked up.
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
setup_scenario jdk17u

up_build master jdk-17.0.20+5
up_build master jdk-17.0.21+1
up_push
mirror_ok master
assert_tag_on jdk-17.0.21+1_adopt release

mirror_plant_adopt_tag jdk-17.0.21.0.3+1_adopt release

up_build master jdk-17.0.21+2
up_build master jdk-17.0.22+1
up_push
mirror_ok master

assert_no_tag jdk-17.0.21+2_adopt
assert_tag_exists jdk-17.0.22+1_adopt
assert_tag_on jdk-17.0.22+1_adopt release

echo "OK"
