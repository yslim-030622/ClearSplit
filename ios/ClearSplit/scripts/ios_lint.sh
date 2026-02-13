#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ios_ci_common.sh"

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "error: swiftlint is required. Install it with: brew install swiftlint"
  exit 1
fi

log_file="$(new_log_file "swiftlint")"
set -o pipefail
swiftlint lint --strict --config "$IOS_ROOT/.swiftlint.yml" --reporter github-actions-logging | tee "$log_file"
status=${PIPESTATUS[0]}

echo "Lint log: $log_file"
exit "$status"
