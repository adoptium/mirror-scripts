#!/bin/bash
# triggerReleasePipeline.sh: upstream puts the next version's +0 fork point tag on the GA commit
# (jdk-21.0.13.0.2+0 next to jdk-21.0.13+9 and jdk-21.0.13-ga). The +0 tag is never _adopt tagged,
# so the trigger must resolve to jdk-21.0.13+9_adopt.
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
setup_scenario jdk21u

# triggerReleasePipeline.sh looks at peeled (^{}) refs, so the tags have to be annotated as upstream's are
up_commit master
git -C "$UPW" tag -a -m t jdk-21.0.13+8 HEAD
up_commit master
git -C "$UPW" tag -a -m t jdk-21.0.13+9 HEAD
git -C "$UPW" tag -a -m t jdk-21.0.13.0.2+0 HEAD
git -C "$UPW" tag -a -m t jdk-21.0.13-ga HEAD
up_push
mirror_ok master
assert_tag_exists jdk-21.0.13+9_adopt

TRIG="$T/trigger"
mkdir -p "$TRIG"
cp "$REPO_ROOT/triggerReleasePipeline.sh" "$REPO_ROOT/common.sh" "$TRIG/"
echo 'jdk21uGA="jdk-21.0.13"' > "$TRIG/releasePlan.cfg"
# the script runs "git clean -fd" in its own directory, so its files must be committed
git init -q "$TRIG"
echo "workspace/" > "$TRIG/.gitignore"
git -C "$TRIG" add -A
git -C "$TRIG" commit -q -m "trigger scripts"
( cd "$TRIG" && bash ./triggerReleasePipeline.sh jdk21u "$MIRROR" ) > "$T/logs/trigger.log" 2>&1 \
  || { tail -20 "$T/logs/trigger.log"; fail "triggerReleasePipeline.sh failed"; }
grep -q "scmReference=jdk-21.0.13+9_adopt" "$TRIG/properties" \
  || { cat "$TRIG/properties" "$T/logs/trigger.log"; fail "expected scmReference=jdk-21.0.13+9_adopt"; }

echo "OK"
