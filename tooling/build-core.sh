#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=env-toolchain.sh
source "$SCRIPT_DIR/env-toolchain.sh"

cd "$REPO_ROOT"

TARGET="${1:-android-arm64}"
BUN_VERSION="1.4.2"
BUN_ANDROID_ARM64_SHA256="a1c7e2983f1bb65146beb256a4d72449f23042412bc2cf278aa6397ba27e0274"
BUN_MIRROR_URL="https://npmmirror.com/mirrors/bun/bun-v${BUN_VERSION}/bun-linux-aarch64-android.zip"
BUN_GITHUB_URL="https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/bun-linux-aarch64-android.zip"

sha256_file() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    sha256sum "$file" | awk '{print $1}'
  fi
}

download_bun_android_arm64() {
  local cache_dir="$SCRIPT_DIR/.cache"
  local zip_path="$cache_dir/bun-v${BUN_VERSION}-linux-aarch64-android.zip"
  local out_dir="$REPO_ROOT/android/app/src/main/jniLibs/arm64-v8a"
  local out_bin="$out_dir/libbun.so"
  mkdir -p "$cache_dir" "$out_dir"

  local need_download=1
  if [[ -f "$zip_path" ]]; then
    local actual
    actual="$(sha256_file "$zip_path")"
    if [[ "$actual" == "$BUN_ANDROID_ARM64_SHA256" ]]; then
      need_download=0
    else
      echo "Cached Bun archive checksum mismatch ($actual), re-downloading..."
      rm -f "$zip_path"
    fi
  fi

  if [[ "$need_download" -eq 1 ]]; then
    local tmp_zip="${zip_path}.tmp.$$"
    rm -f "$tmp_zip"
    echo "Downloading bun-linux-aarch64-android.zip from npmmirror..."
    if ! curl -fL --retry 3 --connect-timeout 15 --max-time 180 "$BUN_MIRROR_URL" -o "$tmp_zip"; then
      echo "npmmirror download failed; falling back to GitHub release..."
      curl -fL --retry 3 --connect-timeout 15 --max-time 180 "$BUN_GITHUB_URL" -o "$tmp_zip"
    fi
    local actual
    actual="$(sha256_file "$tmp_zip")"
    if [[ "$actual" != "$BUN_ANDROID_ARM64_SHA256" ]]; then
      rm -f "$tmp_zip"
      echo "ERROR: Bun SHA-256 verification failed! expected=$BUN_ANDROID_ARM64_SHA256 actual=$actual" >&2
      exit 1
    fi
    mv -f "$tmp_zip" "$zip_path"
  fi

  local extract_dir
  extract_dir="$(mktemp -d)"
  unzip -q -o "$zip_path" -d "$extract_dir"
  local found_bun
  found_bun="$(find "$extract_dir" -type f -name 'bun' | head -n1)"
  if [[ -z "$found_bun" || ! -f "$found_bun" ]]; then
    rm -rf "$extract_dir"
    echo "ERROR: 'bun' binary not found inside $zip_path" >&2
    exit 1
  fi
  cp -f "$found_bun" "$out_bin"
  rm -rf "$extract_dir"
  chmod 0755 "$out_bin"
  echo "Staged Bun runtime: $out_bin"
}

build_android_arm64() {
  local cc="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android26-clang"
  if [[ ! -x "$cc" ]]; then
    echo "ERROR: Android NDK clang not found at $cc" >&2
    exit 1
  fi
  local out_dir="$REPO_ROOT/android/app/src/main/jniLibs/arm64-v8a"
  mkdir -p "$out_dir"
  local out_bin="$out_dir/libfalcon_core.so"
  echo "Building Go core for android/arm64..."
  CGO_ENABLED=1 GOOS=android GOARCH=arm64 CC="$cc" \
    go -C core build -trimpath -ldflags="-s -w" -o "$out_bin" ./cmd/falcon-core
  chmod 0755 "$out_bin"
  echo "Staged Go core: $out_bin"

  download_bun_android_arm64
}

build_android_x64() {
  local cc="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin/x86_64-linux-android26-clang"
  if [[ ! -x "$cc" ]]; then
    echo "ERROR: Android NDK x86_64 clang not found at $cc" >&2
    exit 1
  fi
  local out_dir="$REPO_ROOT/android/app/src/main/jniLibs/x86_64"
  mkdir -p "$out_dir"
  local out_bin="$out_dir/libfalcon_core.so"
  echo "Building Go core for android/amd64..."
  CGO_ENABLED=1 GOOS=android GOARCH=amd64 CC="$cc" \
    go -C core build -trimpath -ldflags="-s -w" -o "$out_bin" ./cmd/falcon-core
  chmod 0755 "$out_bin"
  echo "Staged Go core: $out_bin"
}

build_ios_archive() {
  local sdk="$1"
  local label="$2"
  local min_flag="$3"
  local cc sdk_path out_dir
  cc="$(xcrun --sdk "$sdk" --find clang)"
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
  out_dir="$REPO_ROOT/core/bin/ios/$label"
  mkdir -p "$out_dir"
  echo "Building Go c-archive for ios/$label ($sdk)..."
  CGO_ENABLED=1 GOOS=ios GOARCH=arm64 \
    CC="$cc" \
    CGO_CFLAGS="-isysroot $sdk_path -arch arm64 $min_flag" \
    CGO_LDFLAGS="-isysroot $sdk_path -arch arm64 $min_flag" \
    go -C core build -trimpath -ldflags="-s -w" -buildmode=c-archive \
      -o "$out_dir/libfalcon_core.a" ./cmd/falcon-bridge
  echo "Built iOS static library: $out_dir/libfalcon_core.a"
}

build_ios_xcframework() {
  build_ios_archive iphoneos arm64 "-miphoneos-version-min=14.0"
  build_ios_archive iphonesimulator sim-arm64 "-mios-simulator-version-min=14.0"
  local xcf="$REPO_ROOT/core/bin/ios/FalconCore.xcframework"
  rm -rf "$xcf"
  mkdir -p "$REPO_ROOT/core/bin/ios/arm64/Headers" "$REPO_ROOT/core/bin/ios/sim-arm64/Headers"
  cp -f "$REPO_ROOT/core/bin/ios/arm64/libfalcon_core.h" "$REPO_ROOT/core/bin/ios/arm64/Headers/"
  cp -f "$REPO_ROOT/core/bin/ios/sim-arm64/libfalcon_core.h" "$REPO_ROOT/core/bin/ios/sim-arm64/Headers/"
  xcodebuild -create-xcframework \
    -library "$REPO_ROOT/core/bin/ios/arm64/libfalcon_core.a" -headers "$REPO_ROOT/core/bin/ios/arm64/Headers" \
    -library "$REPO_ROOT/core/bin/ios/sim-arm64/libfalcon_core.a" -headers "$REPO_ROOT/core/bin/ios/sim-arm64/Headers" \
    -output "$xcf"
  echo "Built iOS XCFramework: $xcf"
}

build_host() {
  mkdir -p "$REPO_ROOT/core/bin"
  go -C core build -trimpath -o bin/falcon-core ./cmd/falcon-core
  echo "Built Go core binary: core/bin/falcon-core"
}

case "$TARGET" in
  android-arm64)
    build_android_arm64
    ;;
  android-x64)
    build_android_x64
    ;;
  ios-arm64)
    build_ios_archive iphoneos arm64 "-miphoneos-version-min=14.0"
    ;;
  ios-sim-arm64)
    build_ios_archive iphonesimulator sim-arm64 "-mios-simulator-version-min=14.0"
    ;;
  ios-xcframework)
    build_ios_xcframework
    ;;
  host)
    build_host
    ;;
  *)
    echo "Usage: $0 [android-arm64|android-x64|ios-arm64|ios-sim-arm64|ios-xcframework|host]" >&2
    exit 1
    ;;
esac
