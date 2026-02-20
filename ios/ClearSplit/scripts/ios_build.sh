#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ios_ci_common.sh"

destination="$(resolved_build_destination)"
result_bundle="$(new_result_bundle "build")"

run_xcodebuild "build" \
  "${XCODE_BASE_ARGS[@]}" \
  -configuration "$CONFIGURATION" \
  -destination "$destination" \
  -resultBundlePath "$result_bundle" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

echo "Build result bundle: $result_bundle"
