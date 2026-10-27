# Build and check Building Kernelets on Linux from this directory.
# Generated HTML goes to build/; the companion implementation is ../prototype/.
MDBOOK ?= mdbook
PYTHON ?= python3

.PHONY: all build check render serve clean

all: check build

build:
	$(MDBOOK) build

check:
	$(PYTHON) tools/check.py

render: build
	tools/render.sh $(PAGE) $(OUT)

serve:
	$(MDBOOK) serve --hostname 0.0.0.0

clean:
	$(MDBOOK) clean
	rm -rf .cache/render tools/__pycache__
