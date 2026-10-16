# Introduction to Kernelets in Linux

A tutorial book, with a working prototype, about running a kernel of your own inside Linux.

A **kernelet** is a complete kernel, written in safe Rust against the Asterinas kernel framework, that runs *inside* a host kernel as an ordinary piece of loaded code and is kept apart from it by the language rather than by hardware. This repository holds a book that explains how that works on Linux, chapter by chapter, and the prototype the book describes: a small kernel running as a kernelet inside a patched Linux 6.12, serving a user program's system calls, managing its memory in a Linux page table, scheduled and stopped by Linux.

- `src/`: the book, an [mdBook](https://rust-lang.github.io/mdBook/). Start with `src/README.md`.
- `prototype/`: the companion prototype. Start with `prototype/README.md`.
- `tools/`: the book's checker and page renderer.

## Building the book

```sh
make build          # into book/; needs mdbook and mdbook-mermaid
make check          # every link resolves; every file and identifier the captions name exists in prototype/
make render PAGE=the-gate.html OUT=/tmp/gate.png   # screenshot a page and check its diagrams rendered
```

## Building and running the prototype

```sh
make test           # build everything, boot it in QEMU, run the tests the book mentions
make bench          # the measurements of the last chapter
```

Both delegate to `prototype/Makefile`, which has the details and the individual targets. The first build downloads Linux 6.12 (about 140 MB) and builds it (about ten minutes on eight cores); it needs about 4 GB of disk under `prototype/.build/`, a Rust nightly toolchain (`prototype/rust-toolchain.toml` names it), `gcc`, `make`, `cpio`, `curl`, `python3` and QEMU with KVM.
