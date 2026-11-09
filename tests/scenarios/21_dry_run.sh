#!/bin/bash
# DRY_RUN=true prints "tag → target (create|merge)" for each tag and changes and pushes nothing.
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
setup_scenario jdk21u

up_build master jdk-21.0.13+9
up_push
mirror_ok master

up_branch jdk21.0.13.1 master
up_build jdk21.0.13.1 jdk-21.0.13.0.2+1
up_push

before=$(git -C "$MIRROR" for-each-ref)
export DRY_RUN=true
mirror_ok jdk21.0.13.1
grep -q "DRY_RUN: jdk-21.0.13.0.2+1 → release_jdk21.0.13.0.2 (create from jdk-21.0.13.0.2+1)" "$LAST_LOG" \
  || fail "expected the DRY_RUN plan line in the log"
grep -q "DRY_RUN: dev_jdk21.0.13.0.2 would be advanced" "$LAST_LOG" || fail "expected the DRY_RUN dev line"
# the default branch has a release branch, so its dev branch is advanced locally and only the push is printed
up_commit master
up_push
mirror_ok master
grep -q "DRY_RUN: git push origin dev" "$LAST_LOG" || fail "expected DRY_RUN to reach the dev branch push"
unset DRY_RUN
after=$(git -C "$MIRROR" for-each-ref)
[ "$before" == "$after" ] || fail "DRY_RUN changed the mirror repo"

# the same run for real now creates it
mirror_ok jdk21.0.13.1
assert_tag_on jdk-21.0.13.0.2+1_adopt release_jdk21.0.13.0.2

echo "OK"
