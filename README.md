# Building Kernelets on Linux

A book and working prototype about running a kernel of your own inside Linux.

A **kernelet** is a complete kernel, written in safe Rust against the Asterinas kernel framework, that runs *inside* a host kernel as an ordinary piece of loaded code and is kept apart from it by the language rather than by hardware. This repository holds a book that explains how that works on Linux, chapter by chapter, and the prototype the book describes: a small kernel running as a kernelet inside a patched Linux 6.12, serving a user program's system calls, managing its memory in a Linux page table, scheduled and stopped by Linux.

The repository has two main parts:

- [`book/`](book/README.md): the mdBook, including its source, assets, checker, and renderer. Start with [How to read this book](book/src/README.md).
- [`prototype/`](prototype/README.md): the companion implementation, its build harness, and tests.

The book itself has two parts. **Accepted Design** describes the design the project endorses and the implementation that supports it. **Design Proposals** holds optimizations, alternatives, and new material for discussion and review. Accepted proposals are incorporated into the accepted chapters and implementation; other proposals retain their decision history. Use the [proposal guide](book/src/design-proposals/README.md) and [template](book/src/design-proposals/template.md) to contribute. Each proposal's title and filename start with its submission date, for example `2026-10-27 Improve syscall performance` and `2026-10-27-improve-syscall-performance.md`.

The root `Makefile` provides shortcuts for both parts, and `AGENTS.md` records shared contribution conventions.

## Building the book

```sh
make build          # into book/build/; needs mdbook and mdbook-mermaid
make check          # every link resolves; every file and identifier the captions name exists in prototype/
make render PAGE=accepted-design/carrier-hooks.html OUT=/tmp/page.png   # screenshot a page and check its diagrams rendered
```

These commands delegate to `book/Makefile`; they also work directly from `book/`. The generated site starts at `book/build/index.html`.

The book is built with mdbook 0.5.2 and mdbook-mermaid 0.17.0. `make build` then prints `Warning: The mdbook-mermaid preprocessor was built against version 0.5.0 of mdbook, but we're being called from version 0.5.2`; it is harmless, and the diagrams render.

## Building and running the prototype

```sh
make crates         # once, with a network: the Rust crates (make test does it too if they are missing)
make test           # build everything, boot it in QEMU, run the tests the book mentions
make bench          # the measurements of the last chapter
```

All three delegate to `prototype/Makefile`, which has the details and the individual targets; run those from `prototype/`, or from here as `make -C prototype <target>` (for example `make -C prototype hello`). The root `make clean` cleans only generated book output (`book/build/` and `book/.cache/render/`); `make -C prototype clean` removes the prototype's build products and logs, and leaves the Linux tree and its build. The first `make test` downloads Linux 6.12 (about 140 MB), builds it, and runs the tests; `prototype/README.md` gives the times measured, from a fresh clone and after. It needs no root, about 2.5 GB of disk under `prototype/.build/` (the download and the first build of Linux refuse to start with less than 6 GiB free), a Rust nightly toolchain (`prototype/rust-toolchain.toml` names it; `rustup` installs it), `gcc` with a static C library including the static `libpthread` (`libc6-dev` on Debian and Ubuntu, `glibc-static` on Fedora), `make`, `patch`, `flex`, `bison`, `bc`, `libelf` headers, `xz`, `gzip`, `curl`, `python3` and QEMU with KVM (`qemu-system-x86_64` on `PATH`, or `make QEMU=...`). `prototype/README.md` has the full list.
