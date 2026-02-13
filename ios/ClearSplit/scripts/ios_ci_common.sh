#!/usr/bin/env bash
set -euo pipefail

IOS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$IOS_ROOT/ClearSplit/ClearSplit.xcodeproj}"
SCHEME="${SCHEME:-ClearSplit}"
CONFIGURATION="${CONFIGURATION:-Debug}"

RESULTS_DIR="${RESULTS_DIR:-$IOS_ROOT/.build/ci-results}"
LOGS_DIR="${LOGS_DIR:-$IOS_ROOT/.build/logs}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$IOS_ROOT/.build/DerivedData}"
CLONED_PACKAGES_DIR="${CLONED_PACKAGES_DIR:-$IOS_ROOT/.build/SourcePackages}"
MODULE_CACHE_PATH="${MODULE_CACHE_PATH:-$IOS_ROOT/.build/ModuleCache.noindex}"

mkdir -p "$RESULTS_DIR" "$LOGS_DIR" "$DERIVED_DATA_PATH" "$CLONED_PACKAGES_DIR" "$MODULE_CACHE_PATH"

# Keep Xcode caches inside the repo so CI artifacts are reproducible and sandbox-friendly.
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_PATH"

XCODE_BASE_ARGS=(
  -project "$PROJECT_PATH"
  -scheme "$SCHEME"
  -derivedDataPath "$DERIVED_DATA_PATH"
  -clonedSourcePackagesDirPath "$CLONED_PACKAGES_DIR"
)

timestamp() {
  date +"%Y%m%d-%H%M%S"
}

new_result_bundle() {
  local name="$1"
  echo "$RESULTS_DIR/${name}-$(timestamp).xcresult"
}

new_log_file() {
  local name="$1"
  echo "$LOGS_DIR/${name}-$(timestamp).log"
}

resolved_destination() {
  if [[ -n "${IOS_DESTINATION:-}" ]]; then
    echo "$IOS_DESTINATION"
    return
  fi
  echo "platform=iOS Simulator,name=iPhone 15"
}

run_xcodebuild() {
  local name="$1"
  shift

  local log_file
  log_file="$(new_log_file "$name")"

  set -o pipefail
  xcodebuild "$@" | tee "$log_file"
  local status=${PIPESTATUS[0]}

  echo "Log file: $log_file"
  return "$status"
}
