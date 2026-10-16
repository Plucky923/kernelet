# Introduction to Kernelets in Linux. Run from the repository root.
#
#   make build    build the book into book/
#   make check    every link resolves, every named prototype file and identifier exists
#   make render   screenshot book/$(PAGE) and check its Mermaid blocks rendered (OUT=file.png)
#   make crates   download the prototype's Rust crates, once (needs a network; make test does it if needed)
#   make test     build the prototype and run its test suite in QEMU (about 5 minutes the first time, 3 after)
#   make bench    the prototype's measurements (about 3 minutes)
#   make serve    live preview

MDBOOK ?= mdbook
PYTHON ?= python3

.PHONY: all build check render serve crates test bench clean

all: check build

build:
	$(MDBOOK) build

check:
	$(PYTHON) tools/check.py

render: build
	tools/render.sh $(PAGE) $(OUT)

serve:
	$(MDBOOK) serve --hostname 0.0.0.0

crates:
	$(MAKE) -C prototype crates

test:
	$(MAKE) -C prototype test

bench:
	$(MAKE) -C prototype bench

clean:
	$(MDBOOK) clean
	rm -rf .cache/render tools/__pycache__
