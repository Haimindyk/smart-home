#!/bin/bash
# Runs the simulator UI tests in parallel: builds once, then spreads the tests over N simulators.
# Usage: ios/scripts/run-ui-tests.sh [workers=3] [TestName ...]   (default: every test in WellnessUITests.swift)
set -uo pipefail
cd "$(dirname "$0")/../App"
WORKERS="${1:-3}"; shift || true
SCHEME="$(xcodebuild -list 2>/dev/null | awk '/Schemes:/{f=1;next} f{print $1; exit}')"
BASE="${TMPDIR:-/tmp}/ui-tests-$$"; mkdir -p "$BASE"
xcodegen generate >/dev/null 2>&1

if [ "$#" -gt 0 ]; then TESTS=("$@"); else
  TESTS=($(grep -o "func test[A-Za-z0-9_]*" UITests/WellnessUITests.swift | sed 's/func //'))
fi

# One simulator per worker (created once, reused).
RUNTIME="$(xcrun simctl list runtimes | grep -o 'com.apple.CoreSimulator.SimRuntime.iOS-[0-9-]*' | tail -1)"
DEVTYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
IDS=()
for i in $(seq 1 "$WORKERS"); do
  NAME="UITest-$i"
  ID="$(xcrun simctl list devices | grep -F "$NAME (" | head -1 | grep -o '[0-9A-F-]\{36\}')"
  [ -z "$ID" ] && ID="$(xcrun simctl create "$NAME" "$DEVTYPE" "$RUNTIME")"
  xcrun simctl boot "$ID" 2>/dev/null || true
  IDS+=("$ID")
done

echo "Building once…"
xcodebuild build-for-testing -scheme "$SCHEME" -destination "platform=iOS Simulator,id=${IDS[0]}" -derivedDataPath "$BASE/dd" CODE_SIGNING_ALLOWED=NO >"$BASE/build.log" 2>&1 \
  || { tail -30 "$BASE/build.log"; echo "BUILD FAILED"; exit 1; }

# Round-robin the tests over the workers.
for i in $(seq 0 $((WORKERS-1))); do
  ARGS=(); n=0
  for t in "${TESTS[@]}"; do
    [ $((n % WORKERS)) -eq "$i" ] && ARGS+=("-only-testing:SmartHomeWellnessUITests/WellnessUITests/$t"); n=$((n+1))
  done
  [ "${#ARGS[@]}" -eq 0 ] && continue
  ( xcodebuild test-without-building -scheme "$SCHEME" -destination "platform=iOS Simulator,id=${IDS[$i]}" -derivedDataPath "$BASE/dd" \
      -resultBundlePath "$BASE/result-$i.xcresult" "${ARGS[@]}" CODE_SIGNING_ALLOWED=NO >"$BASE/run-$i.log" 2>&1; echo $? >"$BASE/exit-$i" ) &
done
wait

FAIL=0
for i in $(seq 0 $((WORKERS-1))); do
  [ -f "$BASE/run-$i.log" ] || continue
  grep -E "Test Case.*failed|error:" "$BASE/run-$i.log" | cut -c1-220
  [ "$(cat "$BASE/exit-$i" 2>/dev/null || echo 1)" != "0" ] && FAIL=1
done
grep -h "Executed [0-9]* tests" "$BASE"/run-*.log | sort -u
echo "Results: $BASE"
exit $FAIL
