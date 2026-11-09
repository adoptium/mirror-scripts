#!/bin/bash
# A reused workspace has a local release branch that is behind origin/release because another
# workspace mirrored a newer build. The fetch moves the floor to the remote's latest _adopt tag, so
# there is nothing to mirror, and the stale local branch must not be pushed (it would be rejected
# as non-fast-forward and fail an otherwise no-op run).
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
setup_scenario jdk27u

up_build master jdk-27.0.1+7
up_build master jdk-27.0.1+9
up_push
mirror_ok master
assert_tag_on jdk-27.0.1+9_adopt release

# another workspace mirrors a newer build and advances release in the mirror
mirror_plant_adopt_tag jdk-27.0.1+10_adopt release
remote_head=$(git -C "$MIRROR" rev-parse refs/heads/release)

mirror_ok master
[ "$(git -C "$MIRROR" rev-parse refs/heads/release)" == "$remote_head" ] || fail "release in the mirror was changed"

echo "OK"
