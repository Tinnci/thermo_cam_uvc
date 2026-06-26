#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

make clean
make package

echo "Wrote dist/ThermoCamUVC-macos-$(uname -m)-adhoc.zip"
echo "Wrote dist/SHA256SUMS.txt"
