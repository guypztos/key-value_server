#!/usr/bin/env bash
# Runs inside the dev container (`make check` on the host gets you here).
# Runs quality gates 1-5 from CLAUDE.md and stops at the first failure.
# Gate 6, coverage, is separate: see scripts/coverage.sh and `make coverage`.
set -euo pipefail

cd "$(dirname "$0")/.."

readonly PRESET=check

step() {
  printf '\n==> %s\n' "$*"
}

step "Tool versions"
clang++ --version | head -n 1
clang-format --version
clang-tidy --version | grep --ignore-case 'version'
cmake --version | head -n 1
echo "ninja $(ninja --version)"
dpkg-query --show --showformat='${Package} ${Version}\n' libgtest-dev

step "Gate 2: clang-format, check mode"
scripts/format.sh check

step "Gates 1 and 3: build with -Wall -Wextra -Wpedantic -Werror, clang-tidy on each file"
cmake --preset "$PRESET"
cmake --build --preset "$PRESET"

step "Gates 4 and 5: full test suite under AddressSanitizer and UndefinedBehaviorSanitizer"
ctest --preset "$PRESET" --parallel "$(nproc)"

printf '\nmake check: all gates passed\n'
