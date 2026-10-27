# Building Kernelets on Linux. Shared shortcuts for the book and prototype.
#
#   make build    build the book into book/build/
#   make check    every link resolves, every named prototype file and identifier exists
#   make render   screenshot book/build/$(PAGE) and check its Mermaid blocks rendered (OUT=file.png)
#   make crates   download the prototype's Rust crates, once (needs a network; make test does it if needed)
#   make test     build the prototype and run its test suite in QEMU (about 5 minutes the first time, 3 after)
#   make bench    the prototype's measurements (about 3 minutes)
#   make serve    live preview

.PHONY: all build check render serve crates test bench clean

all: check build

build check render serve clean:
	$(MAKE) -C book $@

crates:
	$(MAKE) -C prototype crates

test:
	$(MAKE) -C prototype test

bench:
	$(MAKE) -C prototype bench
