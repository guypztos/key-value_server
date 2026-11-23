# Host entry points. Every target does its work inside the dev container, so the Mac
# needs only Docker and make. Written for GNU Make 3.81, the version macOS ships.
#
#   make check      quality gates 1-5: warnings-as-errors build, clang-format, clang-tidy,
#                   tests under ASan and UBSan. Exits non-zero on any failure.
#   make coverage   quality gate 6: line coverage report.
#   make format     apply clang-format to the source files on the host.
#   make shell      interactive shell in the container.
#   make image      rebuild the container image, showing progress.
#   make clean      delete the container's work volume and the image.
#
# To run any other command in the container: ./scripts/dev.sh <command...>

export KV_IMAGE := kv-dev
export KV_WORK_VOLUME := kv-work

.PHONY: check coverage format shell image clean

check:
	./scripts/dev.sh scripts/check.sh

coverage:
	./scripts/dev.sh scripts/coverage.sh

# The container formats its own copy and sends the files back as a tar stream.
# pipefail: if formatting fails, nothing is unpacked over the host's files.
format:
	bash -o pipefail -c './scripts/dev.sh scripts/format.sh fix | tar -xf -'

shell:
	./scripts/dev.sh

image:
	KV_VERBOSE_BUILD=1 ./scripts/dev.sh true

clean:
	docker volume rm --force $(KV_WORK_VOLUME)
	docker image rm --force $(KV_IMAGE)
