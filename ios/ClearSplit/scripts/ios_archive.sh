#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ios_ci_common.sh"

archive_path="$RESULTS_DIR/ClearSplit-$(timestamp).xcarchive"
result_bundle="$(new_result_bundle "archive")"

run_xcodebuild "archive" \
  "${XCODE_BASE_ARGS[@]}" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$archive_path" \
  -resultBundlePath "$result_bundle" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  DEVELOPMENT_TEAM= \
  clean archive

echo "Archive path: $archive_path"
echo "Archive result bundle: $result_bundle"
