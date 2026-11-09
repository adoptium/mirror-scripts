#!/bin/bash
# A workspace left over from a previous run keeps the origin it was cloned with. If a later run
# is for a different mirror repo (for example a fork of the real adoptium repo), the job must
# fail rather than fetch from and push to the stale origin.
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
setup_scenario jdk27u

up_build master jdk-27.0.1+7
up_push
mirror_ok master
assert_tag_exists jdk-27.0.1+7_adopt

# Same workspace, different mirror repo (a fork)
FIRST_MIRROR="$MIRROR"
MIRROR="$T/fork-mirror.git"
git init -q --bare -b master "$MIRROR"

up_build master jdk-27.0.1+8
up_push
mirror_fails master
grep -q "has origin" "$LAST_LOG" || fail "expected the origin mismatch error in the log"

# Nothing was pushed to either repo by the failed run
[ -z "$(git -C "$MIRROR" for-each-ref)" ] || fail "the fork mirror should be untouched"
assert_no_tag jdk-27.0.1+8_adopt
MIRROR="$FIRST_MIRROR"
assert_no_tag jdk-27.0.1+8_adopt

# The original mirror still works with the same workspace
mirror_ok master
assert_tag_exists jdk-27.0.1+8_adopt

echo "OK"
