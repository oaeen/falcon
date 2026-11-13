#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=env-toolchain.sh
source "$SCRIPT_DIR/env-toolchain.sh"

cd "$REPO_ROOT"

mkdir -p core/bin
go -C core build -o bin/falcon-core ./cmd/falcon-core
echo "Built Go core binary: core/bin/falcon-core"
