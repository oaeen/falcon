#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=env-toolchain.sh
source "$SCRIPT_DIR/env-toolchain.sh"

cd "$REPO_ROOT"

"$SCRIPT_DIR/build-core.sh" android-arm64

flutter pub get
flutter gen-l10n

# UTC+8 minute versionCode: (year - 2026) * 100000000 + MMDDHHMM
read -r YEAR_STR MMDDHHMM_STR <<<"$(TZ=Asia/Shanghai date +"%Y %m%d%H%M")"
VERSION_CODE=$(( (10#$YEAR_STR - 2026) * 100000000 + 10#$MMDDHHMM_STR ))

HAS_MODE=0
for arg in "$@"; do
  case "$arg" in
    --release|--debug|--profile)
      HAS_MODE=1
      ;;
  esac
done

ARGS=("--build-number=${VERSION_CODE}")
if [[ "$HAS_MODE" -eq 0 ]]; then
  ARGS=("--release" "${ARGS[@]}")
fi

echo "Building Falcon APK (versionCode=$VERSION_CODE)..."
flutter build apk "${ARGS[@]}" "$@"
