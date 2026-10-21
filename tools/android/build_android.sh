#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo"
bash tools/android/build_cpu.sh
bash tools/android/build_deps.sh
bash tools/android/build_gpu.sh
