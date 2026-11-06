#!/bin/bash
# Two build tags on the same commit: both get an _adopt tag.
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
setup_scenario jdk17u

up_build master jdk-17.0.21+1
up_push
mirror_ok master

up_build master jdk-17.0.21+2
up_tag jdk-17.0.21+3 master
up_push
mirror_ok master
assert_tag_on jdk-17.0.21+2_adopt release
assert_tag_on jdk-17.0.21+3_adopt release

mirror_ok master

echo "OK"
