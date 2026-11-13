# Falcon

Falcon is a cross-platform Flutter client paired with a Go core module (`core/`).

## Repository Layout

- `lib/` — Flutter application source and localization resources (`lib/l10n/`)
- `android/`, `ios/`, `macos/` — Platform runner configurations
- `core/` — Go core module (`github.com/falcon-gateway/falcon/core`)
- `tooling/` — Toolchain environment and build scripts (`env-toolchain.sh`, `build-core.sh`, `build-apk.sh`)

## Quick Start

```bash
source tooling/env-toolchain.sh
flutter pub get
flutter gen-l10n
go -C core build ./...
```
