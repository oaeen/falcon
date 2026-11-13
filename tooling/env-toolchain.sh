#!/usr/bin/env bash
# Shared toolchain environment setup for Falcon builds.
# Source this script: source tooling/env-toolchain.sh

export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-/Users/az/Library/Android/sdk}"
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk/28.2.13676358}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"

FLUTTER_BIN="${FLUTTER_BIN:-/Users/az/dev/flutter/bin}"
export PATH="/opt/homebrew/bin:$JAVA_HOME/bin:$FLUTTER_BIN:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
