# SPEC: Redis-style key-value server

Last updated: 2026-11-23. Status: draft, awaiting owner approval.

This document says what the server does and how we will know each milestone is done.
CLAUDE.md says how we work (plans, quality gates, code style). Where the two disagree,
CLAUDE.md wins until the owner changes it. Section 12 lists the three changes this spec
made to CLAUDE.md.

## 1. Purpose

A small in-memory key-value server in C++20 that speaks the Redis wire protocol (RESP),
so the standard `redis-cli` and `redis-benchmark` tools work against it unmodified.

It is a portfolio project for student systems and backend applications (large product
companies, plus low-level C/C++ employers such as Mobileye and Intel). It should show:

1. Systems fundamentals: sockets, non-blocking I/O, an epoll event loop, fsync and durability.
2. Engineering discipline: tests, sanitizers, static analysis, CI, small reviewed commits.
3. Performance work: measured throughput and latency, compared honestly against real Redis.
4. Data structures: a hand-written hash table, benchmarked against the standard one (stretch).

The governing rule: the owner must be able to explain every design decision and the
alternative that was rejected. A smaller server that is fully understood beats a larger
one that is not. Each milestone therefore ends with a list of questions the owner should
be able to answer aloud (section 7).

## 2. Owner background and time budget

- Third-year CS student. C++ from coursework only; no prior multi-file CMake project.
- Has taken an OS course; taking networking now. Socket and epoll experience: treat as none.
- About 10 hours a week, varying with coursework. Wants a CV-ready result in 2-3 weeks.

That is a budget of roughly 20-30 hours. My estimate for all four milestones, including
the time to understand the code well enough to defend it, is 35-45 hours:

| Milestone | Estimate |
|---|---|
| 0. Toolchain and CI | 3-4 h |
| 1. Single-client server | 8-10 h |
| 2. epoll event loop | 8-10 h |
| 3. Persistence | 7-9 h |
| 4. Expiry and polish | 8-10 h |

These are estimates, not measurements. The plan handles the gap this way: every
milestone leaves the repository in a state worth showing. The README and benchmark
numbers are updated at the end of each milestone, not saved for the end. If time runs
out after milestone 2, the CV line is still true and defensible: "epoll-based RESP
server in C++20, benchmarked against Redis". Milestones 3 and 4 then follow at whatever
pace coursework allows.

## 3. Scope

### In scope

- RESP2 protocol, requests as arrays of bulk strings (what redis-cli and redis-benchmark send).
- Commands: PING, GET, SET, DEL, EXISTS (milestone 1); EXPIRE, TTL, SET with EX (milestone 4).
- Small stubs so the Redis tools connect cleanly: COMMAND and CONFIG GET.
- String values only. Keys and values are binary-safe (any bytes, including `\r\n` and NUL).
- Pipelining: several commands arriving in one read are all answered, in order.
- Single-threaded epoll event loop serving many clients.
- Append-only log with a configurable fsync policy; replay on startup.
- Key expiry: checked on access, plus a periodic background sweep.
- Graceful shutdown on SIGINT and SIGTERM.
- Benchmark against real Redis on the same machine, published in the README.

### Out of scope (each is named in the README as a known limitation)

- Log compaction. The append-only log grows without bound.
- Memory limit and eviction. The server grows until the OS stops it.
- Other value types (lists, hashes, sets), transactions, pub/sub, scripting.
- RESP3, inline (telnet-style) commands, AUTH, TLS.
- Multi-threading, replication, clustering.
- Platforms other than Linux.
- The Python test layer (a later stage, per CLAUDE.md).

## 4. Commands

Command names are case-insensitive. Replies match Redis so the standard tools behave.

| Command | Reply | Milestone |
|---|---|---|
| `PING` | simple string `PONG` | 1 |
| `PING msg` | bulk string `msg` | 1 |
| `GET key` | bulk string, or null bulk string if the key is absent | 1 |
| `SET key value` | simple string `OK`; overwrites; clears any existing TTL | 1 |
| `DEL key [key ...]` | integer: number of keys actually removed | 1 |
| `EXISTS key [key ...]` | integer: number of the named keys that exist | 1 |
| `COMMAND ...` | empty array (stub) | 1 |
| `CONFIG GET name` | empty array (stub) | 1 |
| `SET key value EX seconds` | `OK`; key expires after `seconds` | 4 |
| `EXPIRE key seconds` | integer 1 if the TTL was set, 0 if the key is absent | 4 |
| `TTL key` | integer seconds left; -1 if no TTL; -2 if the key is absent | 4 |

Errors:

| Situation | Reply |
|---|---|
| Unknown command | `-ERR unknown command 'NAME'` |
| Wrong number of arguments | `-ERR wrong number of arguments for 'name' command` |
| Unsupported SET option (NX, PX, ...) | `-ERR syntax error` |
| Non-integer seconds | `-ERR value is not an integer or out of range` |
| `SET ... EX` with seconds <= 0 | `-ERR invalid expire time in 'set' command` |
| Malformed RESP, or a size over a limit | `-ERR Protocol error: ...`, then the connection is closed |

`EXPIRE` with zero or negative seconds deletes the key at once and replies 1, as Redis does.

The exact stubs the tools need will be checked against the real `redis-cli` and
`redis-benchmark` versions in the dev container during milestone 1, not assumed.

## 5. Architecture

One process, one thread. Modules, each with its own header, source and test file:

| Module | Responsibility | Does I/O? |
|---|---|---|
| `fd` | RAII owner for a file descriptor; closes on destruction, move-only | yes |
| `resp` | Parse request bytes into commands; serialize replies | no |
| `store` | `Store` interface: get, set, del, exists, expiry. First implementation wraps `std::unordered_map` | no |
| `command` | Table of name, arity, write-or-read flag and handler; runs a parsed command against the store | no |
| `clock` | Interface for "now", so tests can control time without sleeping | no |
| `aof` | Append writes to the log; replay the log at startup | yes |
| `connection` | One client: socket, read buffer, write buffer | yes |
| `server` | Listening socket, epoll loop, timers, signals | yes |

The parser, store and command modules do no I/O. That is deliberate: they can be unit
tested with plain bytes and no sockets, and it is where most of the logic lives.

The parser is incremental. It is handed whatever bytes have arrived and answers one of:
a complete command (and how many bytes it used), "need more bytes", or "protocol error".
TCP delivers a byte stream, not messages, so a command can arrive split across reads or
glued to the next one; the parser must be correct for every split.

### Limits (named constants; values are starting points to confirm in each milestone plan)

| Limit | Default | On breach |
|---|---|---|
| Largest single bulk string (key or value) | 1 MiB | protocol error, close |
| Most arguments in one command | 1024 | protocol error, close |
| Simultaneous clients | 1000 | new connection is closed straight away |
| Unsent reply bytes buffered for one client | 16 MiB | that client is closed |

### Configuration (command-line flags)

| Flag | Default | Milestone |
|---|---|---|
| `--port N` | 6379 | 1 |
| `--bind ADDR` | 127.0.0.1 (there is no authentication, so not exposed by default) | 1 |
| `--aof-path PATH` | `./appendonly.aof` | 3 |
| `--appendfsync always\|everysec` | `everysec` | 3 |
| `--no-persistence` | off | 3 |

## 6. Design decisions and rejected alternatives

| Decision | Why | Rejected alternative |
|---|---|---|
| Single-threaded event loop | No locks, no data races; the work per command is tiny, so one core goes a long way. Redis made the same choice | Thread per client: simple to write, but needs locking on the store and does not scale to thousands of clients |
| Level-triggered epoll (the kernel keeps reporting a socket while it has data) | Forgiving: if we do not drain a socket, we are told again | Edge-triggered: fewer wakeups, but one missed drain hangs a client forever |
| RESP2 arrays only | It is what the Redis tools send; one request format to parse and test | Inline commands and RESP3: more surface, no benefit for the benchmark |
| `std::unordered_map` behind a `Store` interface first | Lets milestones 1-4 focus on networking and durability; the interface makes the later swap a contained change | Hand-written table from day one: more risk in the first milestone |
| Log format is the RESP text of each write command | Reuses the tested parser for replay; the file can be read by eye | Custom binary records with checksums: detects corruption, but more code and a second parser |
| Expiry is logged as an absolute timestamp (`PEXPIREAT key unix-ms`), never as "N seconds from now" | Replaying "expire in 60 s" a day later would wrongly revive the key | Logging the client's EXPIRE as received |
| Under `always`, replies wait until the batch of writes from this loop turn is fsynced | One fsync covers many commands (group commit) and no client is told OK before its data is on disk | fsync per command: same guarantee, far slower under pipelining |
| A failed log write or fsync stops the server | After a failed fsync the kernel may have dropped the data; carrying on would acknowledge writes that are not durable | Log and continue |
| A log that ends mid-command is truncated to the last complete command, with a warning | That is what a crash mid-write looks like; everything before it is valid | Refusing to start: safe, but turns every crash into manual repair |
| A log that is malformed in the middle makes startup fail, reporting the byte offset | That is not a crash artefact; guessing would hide data loss | Skipping the bad part |
| Expiry: check on access, plus a bounded periodic sweep | Access checks give correctness; the sweep frees keys nobody reads | Min-heap of deadlines: exact, but a second structure to keep in step with the map |
| Expiry uses wall-clock time | Deadlines must survive a restart, and a monotonic clock restarts from an arbitrary point | Monotonic clock: immune to clock changes, meaningless across restarts |
| Shutdown signals are read through `signalfd` in the epoll loop | A signal becomes one more readable descriptor; no race | A flag set in a signal handler: racy between checking the flag and blocking in epoll_wait |
| Periodic work (sweep, once-a-second fsync) is driven by the epoll_wait timeout | No extra descriptor; enough precision for 100 ms tasks | `timerfd`: cleaner if timers multiply, more than we need |
| Clang for building, formatting, linting and coverage | One toolchain for clang-format, clang-tidy, sanitizers and llvm-cov | GCC as primary: fine compiler, but splits the tooling |

## 7. Milestones and acceptance criteria

Every milestone is done only when the CLAUDE.md quality gates pass with one command
(`make check`) locally and in CI. The criteria below are in addition to that.

### Milestone 0: toolchain and CI

The quality gates need a working toolchain before any server code exists.

- Docker on the Mac: done on 2026-11-23 (Colima plus the Docker CLI and buildx, via Homebrew).
- Builds copy the source into the image; the project folder is not mounted into containers.
  macOS privacy protection blocks the Docker VM from `~/Documents`, and this route is the
  same as what CI does. Rejected alternatives: granting Terminal Full Disk Access (unverified
  on this machine) and moving the project out of Documents.
- Dev container image: Ubuntu 26.04 LTS with clang, clang-format, clang-tidy and llvm-cov 21,
  CMake 4.2, Ninja 1.13, GoogleTest 1.17 and redis-tools 8.0. LLVM is pinned by major
  version in the package names; the rest are fixed by the Ubuntu release. `make check`
  prints the exact versions it ran with.
- `git init`, connected to the existing public GitHub repository
  (https://github.com/guypztos/key-value_server).
- CMake project with build types for debug, ASan+UBSan, release and coverage.
- `.clang-format`, `.clang-tidy`, GoogleTest wired in, one trivial passing test.
- `make check` runs gates 1-5 and GitHub Actions runs it on every push. Gate 6, coverage,
  is a separate `make coverage` so that `make check` stays fast (owner's decision, 2026-11-23).
- CLAUDE.md "Commands" section filled in.

Commit order (approved by the owner on 2026-11-23):

1. `git init`, `.gitignore`, first commit of CLAUDE.md and SPEC.md, push. The repository is
   public, so confirm the git author name and email with the owner before the first push.
2. Dockerfile for the toolchain.
3. CMake skeleton with the four build types and one trivial passing test.
4. `.clang-format` and `.clang-tidy`.
5. Makefile where `make check` runs gates 1-5 in the container, and `make coverage` runs gate 6.
6. GitHub Actions workflow running the same `make check`.
7. CLAUDE.md "Commands" filled in; README stub.

### Milestone 1: single-client server

- Blocking server: accept one client, serve it until it disconnects, accept the next.
- PING, GET, SET, DEL, EXISTS and the stubs work from `redis-cli`.
- Parser unit tests include every valid message split at every byte position, and malformed input.
- Binary-safe: a value containing `\r\n` and NUL bytes round-trips unchanged.
- Integration tests start the server on an OS-chosen port and talk to it over a real socket.
- A client that disconnects mid-command does not crash or leak; the next client is served.

Be able to explain: Why does a single `read()` not return one whole command? What does
RAII buy for a socket? Why is the parser separate from the socket code? What is the
difference between a simple string and a bulk string in RESP, and why do both exist?

### Milestone 2: many clients

- Non-blocking sockets and a level-triggered epoll loop.
- Test: a client that sends half a command and stalls does not delay other clients.
- Test: a client that reads slowly while owed a large reply receives all of it, intact
  (partial writes), and other clients are served meanwhile.
- Test: a pipelined batch of commands gets all replies in order.
- Limits on client count and buffered output are enforced and tested.
- `redis-benchmark -c 50 -t set,get` finishes with zero errors.
- First benchmark table (section 9) in the README.

Be able to explain: What does epoll do that a loop over blocking `read()` calls cannot?
Level-triggered versus edge-triggered? What happens when `write()` returns fewer bytes
than asked, or EAGAIN? Why one thread, and when would that stop being enough?

### Milestone 3: persistence

- Each write command is appended to the log; the log is replayed at startup.
- `--appendfsync always`: no reply to a write is sent before that write is fsynced.
- `--appendfsync everysec`: the log is fsynced about once a second.
- Test: write keys, restart cleanly, all keys present.
- Test: under `always`, the server process is killed with SIGKILL mid-load; after
  restart every acknowledged write is present.
- Test: a log cut off mid-command is truncated and loaded; a log corrupted in the
  middle makes startup fail with a clear message.
- Benchmark rerun for: no persistence, `everysec`, `always`.

This test kills the process, not the machine, so it proves the write path and replay
are correct but not that data survives power loss. The README will say so.

Be able to explain: What is the difference between `write()` and `fsync()`? What can be
lost under each policy? Why batch the fsync? Why stop the server when fsync fails? Why
does a slow disk stall every client in this design, and how does Redis avoid that?

### Milestone 4: expiry and polish

- EXPIRE, TTL and SET with EX, with the edge cases in section 4.
- An expired key is never returned, whether or not the sweep has reached it.
- The sweep does a bounded amount of work per run and never scans every key in one go.
  How to pick keys cheaply from the map is an open design question for the milestone plan.
- Expiry tests use the injected clock; no test sleeps to wait for a key to expire.
- Test: a key with a TTL keeps the correct deadline across a restart; a key whose
  deadline passed while the server was down is gone after restart.
- SIGINT or SIGTERM: stop accepting, flush and fsync the log, close clients, exit 0.
- README: architecture, the decision table, known limitations, final benchmark.
- Line coverage of `src/` reported, 80% or more, with the uncovered lines explained.

Be able to explain: Why both lazy expiry and a sweep? Why log an absolute timestamp?
What goes wrong if the system clock jumps? Why is a signal handler that sets a flag racy?

### Stretch goals, in priority order

1. **Hand-written hash table.** A second `Store` implementation using open addressing.
   The same test suite runs against both implementations; the README reports a
   before-and-after benchmark. Probing scheme, deletion strategy and growth policy are
   decided in that milestone's plan. Estimate: 8-10 h.
2. **Log compaction at startup** (write a fresh log to a temp file, then rename over the old one).
3. **Second compiler in CI** (GCC) for a different set of warnings.

## 8. Testing strategy

| Layer | What it covers | How |
|---|---|---|
| Unit | Parser, serializer, store, command handlers, log replay, expiry | GoogleTest, no sockets, injected clock, temp files |
| Integration | Real server over real sockets: partial reads and writes, pipelining, many clients, limits | GoogleTest with a small test client; server on an OS-chosen port |
| Process | Crash recovery, graceful shutdown | Test starts the server binary, signals it, restarts it |
| Tool smoke | Compatibility with real tools | Script runs `redis-cli` and a short `redis-benchmark` in `make check` |

All layers run under ASan and UBSan. Tests must not depend on sleeping or on a fixed port.

## 9. Benchmark method

- Tool: `redis-benchmark`, SET and GET, 50 clients, with and without pipelining (`-P 1`, `-P 16`).
- Both this server (release build) and real `redis-server` run in the same container,
  one at a time, with matching persistence settings.
- Report requests per second and p50/p99 latency, in a README table, with the exact commands.
- There is no pass/fail number. The README explains the gap, in either direction.
- Caveat to state in the README: Docker on a Mac runs inside a Linux virtual machine, so
  the numbers are meaningful relative to each other, not as absolute figures.

## 10. Known limitations (to be copied into the README)

Unbounded log growth; no memory limit; fsync on the main thread stalls all clients when
the disk is slow; no checksums, so silent corruption inside a well-formed log record is
not detected; wall-clock expiry is affected by clock changes; resizing the hash map
pauses the server for the duration of the rehash; no authentication or encryption.

## 11. Open questions

- Sweep key selection (milestone 4): how to sample keys with a TTL without a full scan.
- Whether `redis-cli` and `redis-benchmark` in the container need any stub beyond
  COMMAND and CONFIG GET (verify in milestone 1).
- Whether the tool smoke test is stable enough to run in CI or should be local only.

## 12. Changes to CLAUDE.md (accepted by the owner and applied on 2026-11-23)

1. Milestone 0 (toolchain and CI) added before milestone 1.
2. The README and benchmark are updated at the end of every milestone, not only in milestone 4.
3. The hand-written hash table added as a stretch milestone after milestone 4.
