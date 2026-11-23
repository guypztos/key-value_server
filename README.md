# Key-value server

![check](https://github.com/guypztos/key-value_server/actions/workflows/check.yml/badge.svg)

A small Redis-style in-memory key-value server in C++20. It will speak the Redis wire
protocol (RESP), so the standard `redis-cli` and `redis-benchmark` tools work against it.
Sockets and the epoll event loop are written by hand, with no networking libraries.

## Status

**Milestone 0: toolchain and CI** (milestones 1 to 4 build the server). There is no server yet. What exists is the build,
lint and test pipeline that every later milestone has to pass:

| Gate | Tool |
|---|---|
| Warnings are errors | clang 21, `-Wall -Wextra -Wpedantic -Werror` |
| Formatting | clang-format, check mode |
| Static analysis | clang-tidy, every finding is an error |
| Tests | GoogleTest, run under AddressSanitizer and UndefinedBehaviorSanitizer |
| Coverage | llvm-cov line coverage (`make coverage`) |

The plan, scope and design decisions for the server are in [SPEC.md](SPEC.md).

## Running the checks

Requirements: Docker and `make`. Everything else is inside the dev container.

```sh
make check      # format check, build with clang-tidy, tests under ASan + UBSan
make coverage   # line coverage report
make format     # apply clang-format
make shell      # shell inside the dev container
```

`make check` builds the dev container on first use, which takes a minute or two.
After that a run with no changes takes a few seconds.

## Benchmark

None yet. The first numbers, measured against real Redis on the same machine, arrive
with milestone 2.
