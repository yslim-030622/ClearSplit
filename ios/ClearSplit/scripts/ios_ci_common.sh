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

first_simulator_id_from_destinations() {
  local destinations="$1"
  local preferred_pattern="${2:-}"

  printf "%s\n" "$destinations" | awk -v preferred_pattern="$preferred_pattern" '
    /platform:iOS Simulator/ {
      if ($0 ~ /name:Any iOS Simulator Device/) next
      if ($0 ~ /id:dvtdevice-/) next
      if (preferred_pattern != "" && $0 !~ preferred_pattern) next

      if (match($0, /id:[^,}]+/)) {
        id = substr($0, RSTART + 3, RLENGTH - 3)
        gsub(/^[[:space:]]+/, "", id)
        gsub(/[[:space:]}]+$/, "", id)
        if (id != "") {
          print id
          exit
        }
      }
    }
  '
}

first_simulator_id_from_simctl() {
  local preferred_pattern="${1:-}"
  local devices
  devices="$(xcrun simctl list devices available 2>/dev/null || true)"

  printf "%s\n" "$devices" | awk -v preferred_pattern="$preferred_pattern" '
    /^-- iOS / { in_ios = 1; next }
    /^-- / { in_ios = 0 }
    !in_ios { next }

    {
      if (preferred_pattern != "" && $0 !~ preferred_pattern) next
      if (!match($0, /\([0-9A-Fa-f-]+\)/)) next

      id = substr($0, RSTART + 1, RLENGTH - 2)
      gsub(/^[[:space:]]+/, "", id)
      gsub(/[[:space:]]+$/, "", id)
      if (id != "") {
        print id
        exit
      }
    }
  '
}

resolved_destination() {
  if [[ -n "${IOS_DESTINATION:-}" ]]; then
    echo "$IOS_DESTINATION"
    return
  fi

  if [[ -n "${IOS_SIMULATOR_ID:-}" ]]; then
    echo "platform=iOS Simulator,id=$IOS_SIMULATOR_ID"
    return
  fi

  if [[ -n "${IOS_SIMULATOR_NAME:-}" ]]; then
    echo "platform=iOS Simulator,name=$IOS_SIMULATOR_NAME"
    return
  fi

  # Discover an available simulator from xcodebuild output first.
  local destinations
  destinations="$(xcodebuild "${XCODE_BASE_ARGS[@]}" -showdestinations 2>&1 || true)"
  local simulator_id
  simulator_id="$(first_simulator_id_from_destinations "$destinations" "name:iPhone")"
  if [[ -z "$simulator_id" ]]; then
    simulator_id="$(first_simulator_id_from_destinations "$destinations")"
  fi

  # Fallback to simctl when xcodebuild output is sparse on some runner images.
  if [[ -z "$simulator_id" ]]; then
    simulator_id="$(first_simulator_id_from_simctl "iPhone")"
  fi
  if [[ -z "$simulator_id" ]]; then
    simulator_id="$(first_simulator_id_from_simctl)"
  fi

  if [[ -n "$simulator_id" ]]; then
    echo "platform=iOS Simulator,id=$simulator_id"
    return
  fi

  echo "error: unable to resolve an available iOS simulator destination for scheme '$SCHEME'" >&2
  if [[ -n "$destinations" ]]; then
    echo "xcodebuild -showdestinations output:" >&2
    echo "$destinations" >&2
  fi
  return 1
}

resolved_build_destination() {
  if [[ -n "${IOS_BUILD_DESTINATION:-}" ]]; then
    echo "$IOS_BUILD_DESTINATION"
    return
  fi

  local destination
  destination="$(resolved_destination)"

  # Xcode 26 runners can expose only the generic simulator placeholder for build.
  # In that case, xcodebuild requires the explicit generic destination form.
  if [[ "$destination" == "platform=iOS Simulator" ]]; then
    echo "generic/platform=iOS Simulator"
    return
  fi

  echo "$destination"
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
