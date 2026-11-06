#!/bin/bash
# (a) A tag that already has a _adopt tag somewhere in the mirror is not a candidate, so the job
#     succeeds and does not tag it again.
# (b) tagAdopt itself is strict: finding an existing _adopt tag at tagging time is a bug and fails.
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

setup_scenario jdk27u
up_build master jdk-27.0.1+7
up_push
mirror_ok master
mirror_plant_adopt_tag jdk-27.0.1+8_adopt some-unrelated-branch
up_build master jdk-27.0.1+8
up_push
mirror_ok master
assert_tag_not_on jdk-27.0.1+8_adopt release

# (b)
W="$T/strict"
git init -q "$W"
git -C "$W" commit -q --allow-empty -m one
git -C "$W" tag -a jdk-27.0.1+9_adopt -m existing
if ( cd "$W" && MIRROR_WORKSPACE="$T/workspace" bash -c "source '$REPO_ROOT/skaraMirror.sh'; tagAdopt jdk-27.0.1+9 msg" ) > "$T/logs/strict.log" 2>&1; then
  fail "tagAdopt should fail when the _adopt tag exists"
fi
grep -q "already exists" "$T/logs/strict.log" || fail "expected the strict tagAdopt error"

echo "OK"
