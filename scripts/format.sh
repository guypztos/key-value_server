#!/usr/bin/env bash
# Runs inside the dev container.
#
#   format.sh check   exit non-zero if any file is not formatted; changes nothing
#   format.sh fix     format files in place, then write them to stdout as a tar archive.
#                     The container cannot write to the host's files, so `make format`
#                     pipes this archive into `tar -x` on the host to bring them back.
set -euo pipefail

cd "$(dirname "$0")/.."

readonly SOURCE_DIRS=(include src tests)

files=()
while IFS= read -r -d '' file; do
  files+=("$file")
done < <(find "${SOURCE_DIRS[@]}" -type f \( -name '*.hpp' -o -name '*.cpp' \) -print0 | sort -z)

if [ "${#files[@]}" -eq 0 ]; then
  echo "format.sh: no source files found under: ${SOURCE_DIRS[*]}" >&2
  exit 1
fi

case "${1:-}" in
  check)
    clang-format --dry-run --Werror "${files[@]}"
    echo "clang-format: ${#files[@]} files checked, all formatted"
    ;;
  fix)
    clang-format -i "${files[@]}"
    echo "clang-format: ${#files[@]} files formatted" >&2
    tar --create --file=- "${files[@]}"
    ;;
  *)
    echo "usage: format.sh check|fix" >&2
    exit 1
    ;;
esac
