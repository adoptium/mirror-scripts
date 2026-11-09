#!/bin/bash
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Runs the skaraMirror.sh test scenarios in tests/scenarios/NN_*.sh
#
# Usage: tests/run.sh [name-filter]      e.g. tests/run.sh 10_      or  tests/run.sh cspu
#        KEEP_TEST_DIRS=1 tests/run.sh   keeps the temp dirs of failing scenarios
#
# A scenario that is not expected to pass yet has a header line:  # XFAIL: <reason>
# XFAIL scenarios that fail are reported as XFAIL and do not fail the run.
# XFAIL scenarios that pass are reported as XPASS and DO fail the run, so the marker gets removed.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="${1:-}"

pass=0
xfail=0
failed=0
xpass=0
failed_names=""

for scenario in "$TESTS_DIR"/scenarios/[0-9]*.sh; do
  [ -f "$scenario" ] || continue
  name="$(basename "$scenario" .sh)"
  if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then
    continue
  fi

  xfail_reason="$(grep -m1 '^# XFAIL:' "$scenario" | sed 's/^# XFAIL:[[:space:]]*//' || true)"
  out="$(mktemp "${TMPDIR:-/tmp}/scenario-out.XXXXXX")"

  bash "$scenario" > "$out" 2>&1
  rc=$?

  if [ "$rc" -eq 0 ] && [ -z "$xfail_reason" ]; then
    echo "PASS   $name"
    pass=$((pass + 1))
  elif [ "$rc" -ne 0 ] && [ -n "$xfail_reason" ]; then
    echo "XFAIL  $name  ($xfail_reason)"
    xfail=$((xfail + 1))
  elif [ "$rc" -eq 0 ]; then
    echo "XPASS  $name  (remove the XFAIL marker: $xfail_reason)"
    xpass=$((xpass + 1))
    failed_names="$failed_names $name"
  else
    echo "FAIL   $name"
    sed 's/^/    /' "$out"
    failed=$((failed + 1))
    failed_names="$failed_names $name"
  fi
  rm -f "$out"
done

echo
echo "passed: $pass, expected failures: $xfail, failed: $failed, unexpected passes: $xpass"
if [ "$failed" -ne 0 ] || [ "$xpass" -ne 0 ]; then
  echo "Problem scenarios:$failed_names"
  exit 1
fi
exit 0
