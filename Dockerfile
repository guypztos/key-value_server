# Dev container for the key-value server. Every build, lint and test step runs in here,
# so the Mac host and the CI runner use exactly the same tools.
#
# Two stages:
#   toolchain  compilers and tools. Changes rarely, so Docker caches it.
#   dev        toolchain plus a snapshot of the source tree. Rebuilt on every source
#              change, which takes about a second because it is a single COPY.
#
# The source is copied in rather than mounted because macOS blocks the Docker VM from
# reading ~/Documents, and because a copy is also what CI does.

FROM ubuntu:26.04 AS toolchain

# One LLVM major version for the compiler, formatter, linter, sanitizer runtimes and
# coverage tools. Ubuntu packages them per major version (clang-21, clang-tidy-21, ...).
ARG LLVM_VERSION=21

# libclang-rt holds the ASan, UBSan and coverage runtimes. clang only "recommends" it,
# and recommended packages are switched off below to keep the image small.
# rsync is used by scripts/container-entry.sh to sync the source snapshot.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends \
      clang-${LLVM_VERSION} \
      clang-format-${LLVM_VERSION} \
      clang-tidy-${LLVM_VERSION} \
      libclang-rt-${LLVM_VERSION}-dev \
      llvm-${LLVM_VERSION} \
      cmake \
      ninja-build \
      libgtest-dev \
      libgmock-dev \
      redis-tools \
      rsync \
 && rm -rf /var/lib/apt/lists/*

# Unversioned names (clang++, clang-tidy, ...) so scripts do not repeat the version.
# llvm-symbolizer must be on PATH for sanitizer reports to show file and line numbers.
RUN for tool in clang clang++ clang-format clang-tidy llvm-cov llvm-profdata llvm-symbolizer; do \
      ln --symbolic "/usr/bin/${tool}-${LLVM_VERSION}" "/usr/local/bin/${tool}"; \
    done

ENV CC=clang CXX=clang++

FROM toolchain AS dev
# The label lets scripts/dev.sh delete the superseded snapshot left behind by each rebuild.
LABEL project=kv-server
# /src is a read-only snapshot of the host's source tree. Work happens in /work, a
# volume that the entry script brings up to date from the snapshot (see that script).
COPY . /src
WORKDIR /work
ENTRYPOINT ["/src/scripts/container-entry.sh"]
CMD ["bash"]
