#!/usr/bin/env bash
# Runs a command inside the dev container, from the host (Mac or CI runner).
#
#   ./scripts/dev.sh scripts/check.sh      run the quality gates
#   ./scripts/dev.sh clang++ --version     run any tool
#   ./scripts/dev.sh                       open an interactive shell
#
# Each call first rebuilds the image so the container sees the current source. Only the
# final COPY layer changes, so this takes about a second once the toolchain is cached.
#
# /work in the container is a Docker named volume holding the synced source and the
# build directory. It survives between runs, which is what makes repeat builds
# incremental. A named volume lives inside the Docker VM, so the macOS restriction on
# mounting ~/Documents does not apply to it.
set -euo pipefail

readonly IMAGE="${KV_IMAGE:-kv-dev}"
readonly WORK_VOLUME="${KV_WORK_VOLUME:-kv-work}"
readonly IMAGE_LABEL="project=kv-server"

cd "$(dirname "$0")/.."

if ! docker info >/dev/null 2>&1; then
  echo "dev.sh: cannot reach Docker. On the Mac, start it with: colima start" >&2
  exit 1
fi

# Quiet on success, full log on failure. KV_VERBOSE_BUILD=1 (used by `make image`) shows
# progress, which is worth having on the first build because it downloads the toolchain.
if [ "${KV_VERBOSE_BUILD:-0}" = "1" ]; then
  docker build --tag "$IMAGE" .
elif ! build_log=$(docker build --tag "$IMAGE" . 2>&1); then
  printf '%s\n' "$build_log" >&2
  echo "dev.sh: docker build failed" >&2
  exit 1
fi

# Every source change leaves the previous snapshot behind as an untagged image. Remove those.
docker image prune --force --filter "label=$IMAGE_LABEL" >/dev/null

# Attach a terminal only when there is one (there is none in CI or in a hook).
tty_flags=()
if [ -t 0 ] && [ -t 1 ]; then
  tty_flags=(--interactive --tty)
fi

# With no arguments the image's default command (an interactive shell) runs.
# The ${array[@]+...} form is needed because macOS ships bash 3.2, where expanding an
# empty array under `set -u` is an error.
exec docker run --rm ${tty_flags[@]+"${tty_flags[@]}"} \
  --volume "$WORK_VOLUME:/work" \
  "$IMAGE" "$@"
