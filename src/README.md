# How to read this book

This book explains one idea and one program.

The idea is the **kernelet**: a complete operating-system kernel that runs *inside* another kernel, as an ordinary piece of loaded code, and yet is kept apart from it. The program is a prototype that does exactly that on Linux: a small kernel written against the Asterinas kernel framework runs inside a patched Linux, serves a user program's system calls, manages that program's memory, and is scheduled and stopped by Linux without Linux ever understanding what it is.

By the end you will know how every part of that prototype works, down to the C and Rust that does it, and you will have run it.

## Who this is for

You have taken one course on operating systems. You know what a process is, what virtual memory and a page table are, what a system call does, and what an interrupt and a context switch are, in the abstract. You can read C. You have not read the Linux source, and you do not know Rust.

Everything beyond that is explained the first time it is needed, in boxes like these:

<div class="linux">

**Linux.** A box like this explains a Linux mechanism that the chapter is about to use: what it is, what it is called in the source, and why the design cares.

</div>

<div class="rust">

**Rust.** A box like this explains a Rust construct the next code excerpt relies on, and nothing more than that.

</div>

## The companion repository

The code is in the `prototype/` directory of this repository. Every code excerpt in the book is a simplified version of code there, and a caption under each excerpt names the file it comes from and the functions it shows, like this:

*Simplified from `prototype/endovisor/switch.S`: `klet_switch`.*

"Simplified" means that logging, counters, error paths and comments have been cut so that the mechanism fits on the page. The file holds the real thing, with its comments, and is worth opening beside the book.

To build and run the prototype you need a Linux machine with a Rust nightly toolchain, `gcc`, `make`, `cpio`, `curl`, and QEMU with hardware virtualization. From the `prototype/` directory, `make hello` downloads Linux 6.12, patches and builds it, builds the kernelet and the module, boots the result in QEMU, and checks the serial log. The first run takes about ten minutes and about 4 GB of disk; later runs take a minute or two. `make test` runs every test the book mentions, and `make bench` the measurements of the last chapter. `prototype/README.md` has the details.

## The chapters

The book follows the order in which a kernelet comes to life, so each chapter uses only what the ones before it have built.

1. **Why a kernel of your own** says what a kernelet is and why it can be safe.
2. **The kernel we will run** reads the hundred-line kernel that runs throughout the book, and lists what it needs from a machine.
3. **What a kernelet is made of** is the shape of the thing: the image, the framework beneath the kernel, and the table of functions through which it talks to Linux.
4. **The gate** is the small patch to Linux that hands a tenant's system calls to its kernelet.
5. **Carriers** are the Linux tasks on which a kernelet runs.
6. **Two stacks** is how a kernelet keeps its own stacks on a Linux task.
7. **Into user mode and back** is the round trip of a system call, after which the hundred-line kernel prints its greeting.
8. **Tasks and virtual CPUs** gives the kernelet its own tasks and its own scheduler.
9. **Virtual interrupts** gives it a timer.
10. **Sharing a processor politely** keeps it from holding a processor against Linux.
11. **Stopping a kernelet** removes it, even when it will not cooperate.
12. **Tenant memory on Linux's page tables** is the central mechanism: the tenant's memory lives in a Linux address space that the kernelet edits only by asking.
13. **What vOSTD adds on top** is the bookkeeping that makes that sound.
14. **What it costs** gives the numbers.

Chapters 12 and 13 are the climax, and everything before them is there so that they can be read.

## Conventions

A few words are used in exactly one sense throughout; each is defined where it first appears, and the first chapter collects them. Linux functions are linked to the version 6.12 source on `elixir.bootlin.com` the first time they are named, so that you can read the real code. Every figure is either a diagram in the text or a drawing; nothing in a figure is decorative.

Each chapter ends with a short recap, and with the `make` target that runs the code the chapter explained.
