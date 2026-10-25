# host: what runs in the booted Linux's user space

Two things run on the host side, as ordinary programs in the
guest's initramfs, and both are here:

| directory | what it is |
|---|---|
| `runtime/` | the kernelet runtime: `sandbox.c`, the client of the endovisor UAPI, and `holder.c`, the command around it; `run-test.c`, which runs a test's holder invocations; the experiment drivers `run-sched.c` and `run-mem.c`; `uapi-check.c` and `yield-rival.c` (chapter 2) |
| `initramfs/` | `init.c`, PID 1 of the boot: it mounts the pseudo file systems, loads the staged modules, runs every program in `/tests/`, unloads the modules and powers the machine off |

Each has its own `README.md`.
