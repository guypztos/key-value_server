# Key-value server (portfolio project)

## What this is
A Redis-style in-memory key-value server in C++, built by a third-year CS student
as a portfolio project for student systems/backend job applications.
The owner must be able to explain and defend every design decision in an interview.

## Stack
- C++20, CMake, GoogleTest
- Linux only (epoll). Development happens inside Docker on a Mac host.
- Wire protocol: RESP (the Redis protocol), so redis-cli and redis-benchmark work against it.
- No third-party networking libraries. Sockets and the event loop are written by hand.
- Docker on the Mac is Colima (`colima start` after a reboot; it does not start at login).
  Containers cannot mount this folder (macOS blocks the VM from ~/Documents), so builds
  copy the source into the image with `docker build`. Do not rely on `docker run -v`.

## Milestones (do one at a time, in order)
Full requirements and acceptance criteria for each milestone are in SPEC.md.

0. Toolchain and CI: dev container, CMake skeleton, `make check`, GitHub Actions.
1. Single-client TCP server: GET, SET, DEL over RESP, in-memory hash map.
2. Many clients: epoll event loop, non-blocking sockets.
3. Persistence: append-only log, replayed on startup.
4. Expiry and polish: key TTLs, graceful shutdown, README design notes, benchmark.
5. Stretch, only after milestone 4: hand-written hash table behind the Store interface,
   benchmarked against std::unordered_map.

The README and its benchmark table are updated at the end of every milestone, so the
repository is worth showing at each stopping point.

Later stages, out of scope for now: Python test/automation layer with CI, replication.

## How to work with me
- Work on the current milestone only. Do not start the next one unasked.
- Before writing code for a milestone, propose a short plan and wait for approval.
- Explain non-obvious design choices briefly, including the alternative you rejected.
- Keep changes small enough to review. Prefer several small commits over one large one.
- Every feature needs a test. A milestone is done when the build is clean with
  -Wall -Wextra -Werror, all tests pass, and it has been run under AddressSanitizer.
- Verify claims by running things. Do not say something works without having run it.
- If I ask "why", teach rather than just patch.

## Quality gates (run after every code change, before saying a step is done)
1. Build with -Wall -Wextra -Wpedantic -Werror. In C++ the compiler is the type checker; zero warnings allowed.
2. clang-format on changed files (config in .clang-format).
3. clang-tidy with the repo's .clang-tidy config; fix findings, do not suppress them without asking.
4. Run the full test suite. New code comes with tests in the same step.
5. Run tests under AddressSanitizer and UndefinedBehaviorSanitizer.
6. Coverage: report line coverage (gcov/llvm-cov) at the end of each milestone. Target 80%+ on src/,
   and say which uncovered lines are left and why.
Show the actual command output as evidence. If a gate fails, fix it before moving on.
All gates must be runnable with one command (e.g. `make check`) and run in CI on every push.

## Code style
- RAII for every resource (sockets, file descriptors). No raw owning pointers.
- Headers in include/, sources in src/, tests in tests/.
- No magic numbers. Named constants.
- Errors from system calls are always checked and reported with errno context.

## Commands
Run these on the Mac from the repo root. Each one copies the current source into the dev
container image and does its work inside a container. Docker must be running (`colima start`).
- Build and test, gates 1-5: `make check`
  (clang-format check, -Werror build with clang-tidy, all tests under ASan and UBSan).
- Coverage, gate 6: `make coverage` (report only; not part of `make check`).
- Apply formatting to the source files: `make format`
- One test by name, after a `make check`: `./scripts/dev.sh ctest --preset check -R <name>`
- Any other command in the container: `./scripts/dev.sh <command...>`
- Open dev container: `make shell`
- Rebuild the image showing progress: `make image`. Start from scratch: `make clean`.
- Run server: not available yet (milestone 1).

A Claude Code Stop hook (`.claude/settings.json`) runs `make check` whenever Claude tries
to end a turn and blocks the turn from ending while it fails.

The container keeps the synced source and the build tree in a Docker named volume
(`kv-work`). Named volumes are fine; mounting the host folder is what does not work.

## Current status
Milestone 0 (toolchain and CI) built on 2026-11-23: dev container, CMake skeleton with one
trivial source file and test, `make check`, `make coverage`, GitHub Actions workflow, Stop
hook. Pinned tool versions are in SPEC.md section 7. No server code exists yet.
Next: milestone 1, which needs a plan and the owner's approval before any code.
