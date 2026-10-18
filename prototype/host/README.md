# host: what runs in the booted Linux's user space

Two things run on the host side, as ordinary programs in the
guest's initramfs, and both are here:

| directory | what it is |
|---|---|
| `runtime/` | the kernelet runtimes, `run-*.c`: one small static C program per kernel, which creates the sandbox by exec'ing its `.klet` file and then drives the test (chapter 5) |
| `initramfs/` | `init.c`, PID 1 of the boot: it mounts the pseudo file systems, loads the staged modules, runs every program in `/tests/`, unloads the modules and powers the machine off |

Each has its own `README.md`.
