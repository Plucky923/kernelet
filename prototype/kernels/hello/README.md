# hello: the 100-line kernel, unedited

The kernel proper of `make hello` is Asterinas's "write a kernel in 100 lines"
example: a Hello World kernel in safe Rust against OSTD, which loads a tenant
program, gives it an address space and a user context, and serves its `write`
and `exit` system calls. Here it is compiled against vOSTD instead of OSTD, and
**its source is not changed by one byte**. That is the claim the whole
prototype rests on, and the build checks it: `make kernel-proper-check`, run
before every `make hello`, `cmp`s `src/lib.rs` and `hello.S` against
`upstream/`.

The book walks through this kernel and the OSTD API it uses in chapter 2 (the
kernel we will run); the rest of the book is what it takes for this file to
run on Linux.

## How it is built

`make image` (the default `KLET_KERNEL=hello`) builds the crate with vOSTD as
its `ostd` and pre-links both into the endovisor's `image.o_shipped`.
`hello.S` is assembled with `gcc -static -nostdlib` into `hello/hello`, which
the kernel embeds with `include_bytes!("../hello")`.

## Files

| file | what it is |
|---|---|
| `src/lib.rs` | the kernel proper; never edited |
| `hello.S` | the tenant program: `write("Hello, world\n")`, then `exit`; never edited |
| `upstream/lib.rs`, `upstream/hello.S` | the reference copies, from the Asterinas tree at commit `ab9a4cfdc`, `osdk/tests/examples_in_book/write_a_kernel_in_100_lines_templates/` |
| `Cargo.toml` | the crate: `ostd` is `vostd` under its library name |
