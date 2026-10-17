# initramfs: PID 1 of the test machine

`init.c` is the whole user space of the guest that QEMU boots: no busybox, no
shell. It mounts `/proc`, `/sys` and `/dev`, loads the modules listed in
`/modules/order` with their parameters, runs every program in `/tests/` in
order, unloads the modules and powers the machine off, so that `make run` is
a test that ends by itself. (A runtime that needs an argument reads it from
its own `/tests/<name>.arg`.)

Everything it prints goes to the serial console with `write(2)`, never through
a stdio buffer, so that nothing is lost when the machine powers off or a test
crashes the kernel.

It belongs to the harness rather than to the design; the book describes the
harness, and how to read a serial log, where it first boots the prototype
(chapter 7, where `make hello` first boots).

## How it is built

`make initramfs`: `gcc -static -O2 -Wall -Wextra` into `.build/init`, copied to
`.build/stage/init` beside what the `stage-*` targets put there (the module,
the test's runtime, the `.klet` file), and packed into
`.build/initramfs.cpio.gz` by the kernel's own `usr/gen_init_cpio`, from a
list of the staged files written to `.build/initramfs.list`. The list also
names the one device node the archive needs, `/dev/console`, so the archive
is built without `mknod` and without root, and everything in it is owned by
root. The archive is repacked on every run, because what is staged changes
independently of `init.c`.

## Files

| file | what it is |
|---|---|
| `init.c` | PID 1 |
