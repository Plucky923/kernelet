# kernels: the kernels proper

Each subdirectory is one kernel proper, a crate compiled against vOSTD
(`../vostd`), with the tenant program it embeds (`<name>.S`, assembled by the
Makefile into `<name>/<name>`) and a `README.md`. `make <name>` builds the image
with that kernel, boots it and checks the serial log; the Makefile's
`KLET_KERNEL` variable selects one.

| directory | the kernel | the book |
|---|---|---|
| `hello/` | Asterinas's 100-line Hello World kernel, byte for byte (`upstream/` is the original; the build compares the two before every `make hello`) | chapter 3 |
| `probe/` | demand paging, a refused allocation, exceptions that are not page faults, and the kills and signals that end a sandbox | chapters 8 and 12 |
| `yield/` | preemption of kernelet code, the watch timer, the forced yield | chapters 10 and 11 |
| `sched/` | a scheduler of the kernelet's own, fairness and the measurements of chapter 15 | chapters 9 and 15 |
| `mem/` | tenant memory on Linux page tables, and its measurements | chapters 13 to 15 |
