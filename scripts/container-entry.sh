#!/usr/bin/env bash
# Entry point of the dev container. Brings /work up to date with the source snapshot
# baked into the image at /src, then runs the requested command in /work.
#
# Why not build straight from /src? Ninja decides what to rebuild by comparing file
# times. Files in /src carry the host's clock; build outputs carry the Docker VM's
# clock. If the two clocks drift apart (VM clocks do, for example after the laptop
# sleeps), a freshly edited file can look older than its stale object file, and the
# build would silently skip it.
#
# rsync --checksum rewrites a file in /work only when its content differs, and stamps it
# with the VM's current time. So every timestamp Ninja sees comes from one clock, and a
# file's time changes exactly when its content changes.
set -euo pipefail

readonly SNAPSHOT_DIR=/src
readonly WORK_DIR=/work

rsync --recursive --links --perms --checksum --delete \
  --exclude=/build/ \
  "$SNAPSHOT_DIR/" "$WORK_DIR/"

cd "$WORK_DIR"
exec "$@"
