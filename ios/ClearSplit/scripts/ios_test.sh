#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ios_ci_common.sh"

mode="${1:-all}"
destination="$(resolved_destination)"

run_tests() {
  local suite="$1"
  shift

  local result_bundle
  result_bundle="$(new_result_bundle "$suite")"

  run_xcodebuild "$suite" \
    "${XCODE_BASE_ARGS[@]}" \
    -configuration "$CONFIGURATION" \
    -destination "$destination" \
    -resultBundlePath "$result_bundle" \
    -parallel-testing-enabled NO \
    -maximum-parallel-testing-workers 1 \
    -enableCodeCoverage YES \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    "$@"

  echo "Test result bundle: $result_bundle"
}

case "$mode" in
  unit)
    run_tests "unit-tests" test -only-testing:ClearSplitTests
    ;;
  ui)
    run_tests "ui-tests" test -only-testing:ClearSplitUITests -retry-tests-on-failure -test-iterations 2
    ;;
  all)
    run_tests "unit-tests" test -only-testing:ClearSplitTests
    run_tests "ui-tests" test -only-testing:ClearSplitUITests -retry-tests-on-failure -test-iterations 2
    ;;
  *)
    echo "Usage: $0 [unit|ui|all]"
    exit 2
    ;;
esac
