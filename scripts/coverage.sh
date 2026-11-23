#!/usr/bin/env bash
# Runs inside the dev container (`make coverage` on the host gets you here).
# Quality gate 6: builds with clang's source-based coverage, runs the tests, and reports
# line coverage for our own code. It reports only; it does not fail below a threshold.
set -euo pipefail

cd "$(dirname "$0")/.."

readonly PRESET=coverage
readonly BUILD_DIR="build/$PRESET"
readonly PROFILE_DIR="$BUILD_DIR/profiles"
readonly MERGED_PROFILE="$BUILD_DIR/coverage.profdata"
readonly TEST_BINARY="$BUILD_DIR/tests/kv_tests"
# Leave out the tests themselves and anything from system headers.
readonly IGNORE_REGEX='(^/usr/|/tests/)'

step() {
  printf '\n==> %s\n' "$*"
}

step "Build with coverage instrumentation"
cmake --preset "$PRESET"
cmake --build --preset "$PRESET"

step "Run tests"
# Each test process writes its own raw profile (%p is the process id). Old ones are
# removed first so the report reflects this run only.
rm -rf "$PROFILE_DIR"
LLVM_PROFILE_FILE="$PWD/$PROFILE_DIR/%p.profraw" ctest --preset "$PRESET" --parallel "$(nproc)"

step "Line coverage (include/ and src/)"
llvm-profdata merge --sparse "$PROFILE_DIR"/*.profraw --output="$MERGED_PROFILE"
llvm-cov report "$TEST_BINARY" \
  --instr-profile="$MERGED_PROFILE" \
  --ignore-filename-regex="$IGNORE_REGEX"

step "Uncovered lines"
# The lcov export has one "SF:<file>" record per source file, followed by one
# "DA:<line>,<count>" record per executable line. A count of 0 is a line that never ran.
# The awk program prints those lines as file:first-last ranges.
uncovered=$(llvm-cov export "$TEST_BINARY" \
  --instr-profile="$MERGED_PROFILE" \
  --ignore-filename-regex="$IGNORE_REGEX" \
  --format=lcov \
  | awk -v root="$PWD/" '
      function print_range() {
        if (first != "") {
          printf "%s:%s\n", file, (first == last ? first : first "-" last)
          first = ""
        }
      }
      /^SF:/ {
        print_range()
        file = substr($0, 4)
        sub("^" root, "", file)
      }
      /^DA:/ {
        split(substr($0, 4), record, ",")
        line = record[1]
        count = record[2]
        if (count != 0 || (first != "" && line != last + 1)) {
          print_range()
        }
        if (count == 0) {
          if (first == "") {
            first = line
          }
          last = line
        }
      }
      END { print_range() }
    ')
if [ -z "$uncovered" ]; then
  echo "none"
else
  printf '%s\n' "$uncovered"
fi
