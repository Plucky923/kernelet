# How to read this book

This is a tutorial about the **kernelet**: a complete OS kernel that runs *inside* another kernel, and does so *safely*.

The tutorial comes with a prototype implementation of kernelets in Linux. It patches and extends the Linux kernel so that a small Rust kernel written against OSTD (Asterinas's kernel framework) can run inside Linux, serve a user program's system calls, manage that program's memory, and be scheduled and stopped by Linux without Linux ever understanding what it is.

By the end you will know how every part of that prototype works, down to the C and Rust that does it, and you will have run it.

## Who this is for

You have taken one course on operating systems. You know what a process is, what virtual memory and a page table are, what a system call does, and what an interrupt and a context switch are, in the abstract. You can read C, and you know Rust fairly well. You have not read the Linux source.

Everything beyond that is explained the first time it is needed, in a box like this:

<div class="linux">

**Linux.** A box like this explains a Linux mechanism that the chapter is about to use: what it is, what it is called in the source, and why the design cares.

</div>

## The companion repository

The code is in the `prototype/` directory of this repository. Every code excerpt in the book is a simplified version of code there, and is given a caption that names the file it comes from and the functions it shows, like this:

*Simplified from `prototype/linux/endovisor/switch.S`: `klet_switch`.*

"Simplified" means that logging, counters, error paths and comments have been cut so that the mechanism fits on the page. If the caption begins with "Unchanged" instead, the block is copied from the file verbatim.

## The chapters

The book follows the order in which a kernelet comes to life, so each chapter uses only what the ones before it have built.

1. **Why a kernel of your own** says what a kernelet is and why it can be safe.
2. **The kernelet UAPI** is what a program on the host may ask of a kernel that runs kernelets: the image as a file, the device node and its descriptors, and how user space creates the carriers.
3. **The kernel we will run** reads the hundred-line kernel that runs throughout the book, and lists what it needs from a machine.
4. **The kernelet ABI** is how a kernelet talks to its host from the inside: the three tables, the grant, and the first services.
5. **Carrier hooks and patch overview** adds the two hooks through which a tenant's system calls reach its kernelet, and lists the rest of the one small patch to Linux.
6. **Carriers** are the Linux tasks on which a kernelet runs.
7. **Two stacks** is how a kernelet keeps its own stacks on a Linux task.
8. **Into user mode and back** is the round trip of a system call, after which the hundred-line kernel prints its greeting.
9. **Tasks and virtual CPUs** gives the kernelet its own tasks and its own scheduler.
10. **Virtual interrupts** gives it a timer.
11. **Sharing a processor politely** keeps it from holding a processor against Linux.
12. **Stopping a kernelet** removes it, even when it will not cooperate.
13. **Tenant memory on Linux's page tables** is the central mechanism: the tenant's memory lives in a Linux address space that the kernelet edits only by asking.
14. **What vOSTD adds on top** is the bookkeeping that makes that sound.
15. **What it costs** gives the numbers.

Chapters 13 and 14 are the climax, and everything before them is there so that they can be read.

## Conventions

A few words are used in exactly one sense throughout; each is defined where it first appears, and the first chapter collects them. Linux functions are linked to the version 6.12 source on `elixir.bootlin.com` the first time they are named, so that you can read the real code. Every figure is either a diagram in the text or a drawing.
