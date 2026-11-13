#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=env-toolchain.sh
source "$SCRIPT_DIR/env-toolchain.sh"

MODE="no-codesign"

usage() {
  cat <<'EOF'
Usage: tooling/build-ios.sh [--no-codesign | --simulator | --archive]

Options:
  --no-codesign   Build Go iOS static core and unsigned .ipa (default)
  --simulator     Build Go iOS simulator core and Debug simulator .app
  --archive       Build Go iOS static core and signed release .ipa archive
  -h, --help      Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-codesign)
      MODE="no-codesign"
      shift
      ;;
    --simulator)
      MODE="simulator"
      shift
      ;;
    --archive)
      MODE="archive"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option '$1'" >&2
      usage >&2
      exit 2
      ;;
  esac
done

cd "$REPO_ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: iOS builds require macOS (Darwin) with Xcode installed." >&2
  exit 1
fi

DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
if ! xcodebuild -version >/dev/null 2>&1; then
  cat >&2 <<EOF
Error: Full Xcode.app is not active on this Mac; cannot run iOS builds.
  Active developer directory: ${DEV_DIR:-<none>}

To enable iOS / .ipa builds:
  1. Install Xcode from the Mac App Store or developer.apple.com.
  2. Select Xcode as the active developer directory:
       sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  3. Complete first-launch setup and install the iOS platform SDK:
       sudo xcodebuild -runFirstLaunch
       xcodebuild -downloadPlatform iOS
  4. Re-run:
       ./tooling/build-ios.sh --${MODE}
EOF
  exit 1
fi

TARGET_SDK="iphoneos"
if [[ "$MODE" == "simulator" ]]; then
  TARGET_SDK="iphonesimulator"
fi

if ! xcrun --sdk "$TARGET_SDK" --show-sdk-path >/dev/null 2>&1; then
  cat >&2 <<EOF
Error: Apple SDK '$TARGET_SDK' could not be located by xcrun.
  Active developer directory: ${DEV_DIR:-<none>}
  Xcode version: $(xcodebuild -version | tr '\n' ' ')

Install the iOS SDK via:
  xcodebuild -downloadPlatform iOS
and re-run: ./tooling/build-ios.sh --${MODE}
EOF
  exit 1
fi

echo "==> Building Go core static archives for iOS..."
"$SCRIPT_DIR/build-core.sh" ios-arm64
"$SCRIPT_DIR/build-core.sh" ios-sim-arm64

if grep -q "ios-xcframework" "$SCRIPT_DIR/build-core.sh" 2>/dev/null; then
  "$SCRIPT_DIR/build-core.sh" ios-xcframework
fi

FOUND_CORE_ARTIFACT=""
for candidate in \
  "ios/Frameworks/FalconCore.xcframework" \
  "core/bin/FalconCore.xcframework" \
  "core/bin/ios-arm64/libfalcon_bridge.a" \
  "core/bin/libfalcon_bridge_ios_arm64.a" \
  "core/bin/libfalcon_bridge.a"; do
  if [[ -e "$candidate" ]]; then
    FOUND_CORE_ARTIFACT="$candidate"
    break
  fi
done

if [[ -n "$FOUND_CORE_ARTIFACT" ]]; then
  echo "==> Verified iOS Go core artifact: $FOUND_CORE_ARTIFACT"
else
  echo "Warning: No compiled FalconCore.xcframework / libfalcon_bridge.a found under ios/Frameworks or core/bin." >&2
  echo "         Xcode will link against weak symbols in ios/Runner/FalconBridgeStub.c." >&2
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "Error: 'flutter' CLI not found on PATH (check tooling/env-toolchain.sh)." >&2
  exit 1
fi

case "$MODE" in
  no-codesign)
    echo "==> Building unsigned iOS IPA (flutter build ipa --no-codesign)..."
    flutter build ipa --no-codesign
    ;;
  simulator)
    echo "==> Building iOS Simulator app (flutter build ios --simulator)..."
    flutter build ios --simulator
    ;;
  archive)
    echo "==> Building signed iOS IPA archive (flutter build ipa)..."
    flutter build ipa
    ;;
esac
