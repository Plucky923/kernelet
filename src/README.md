# How to read this book

This is a tutorial about the **kernelet**: a complete OS kernel that runs *inside* another kernel, and does so *safely*.

The tutorial comes with a prototype implementation of kernelets in Linux. It patches and extends the Linux kernel so that a small Rust kernel written against OSTD, the framework at the bottom of the Rust kernel Asterinas, can run inside Linux, serve a user program's system calls, manage that program's memory, and be scheduled and stopped by Linux without Linux ever understanding what it is.

By the end you will know how every part of that prototype works, down to the C and Rust that does it, and you will have run it.

## Who this is for

The book assumes what one course on operating systems teaches, C, a fair amount of Rust, and nothing about the Linux source. You know what a process is, what virtual memory and a page table are, what a system call does, and what an interrupt and a context switch are, in the abstract. You can read C, and you know Rust fairly well. You have not read the Linux source.

Every Linux mechanism beyond that is explained the first time it is needed, in a box like this:

<div class="linux">

**Linux.** A box like this explains a Linux mechanism that the chapter is about to use: what it is, what it is called in the source, and why the design cares.

</div>

## The companion repository

Every code excerpt in the book comes from the `prototype/` directory of this repository, whose README says how to build and run it. A caption under each excerpt names the file it comes from and, for a simplified excerpt, the functions it shows, like this:

*Simplified from `prototype/linux/endovisor/switch.S`: `klet_switch`.*

The caption's first word says how the block differs from the file. "Simplified" means that logging, counters, error paths and comments have been cut so that the mechanism fits on the page. "Unchanged" means that the block is copied from the file verbatim.

## The chapters

The book follows the order in which a kernelet comes to life, so each chapter uses only what the ones before it have built.

1. **Why a kernel of your own** says what a kernelet is and why it can be safe.
2. **The endovisor UAPI** is what a program on the host may ask of the endovisor: the image as a file, the device node and its descriptors, and how user space creates the carriers.
3. **The kernel we will run** reads the hundred-line kernel that runs throughout the book, and lists what it needs from a machine.
4. **The kernelet ABI** is how a kernelet talks to its host from the inside: the three tables, the grant, and the first services.
5. **Carrier hooks and patch overview** adds the two hooks, one at a carrier's system call and one on its way back to user mode, through which a carrier enters and leaves kernelet code, and lists the rest of the one small patch to Linux.
6. **Carriers** puts a kernelet on the Linux tasks it runs on.
7. **Two stacks** is how a kernelet keeps its own stacks on a Linux task.
8. **Into user mode and back** is the round trip of a system call, after which the hundred-line kernel prints its greeting.
9. **Tasks and virtual CPUs** gives the kernelet its own tasks and its own scheduler.
10. **Virtual interrupts** gives it a timer.
11. **Sharing a processor politely** keeps it from holding a processor against Linux.
12. **Stopping a kernelet** removes it, even when it will not cooperate.
13. **Tenant memory on Linux's page tables** puts the tenant's memory in a Linux address space that the kernelet edits only by asking.
14. **What vOSTD adds on top** is the bookkeeping that makes that sound.
15. **What it costs** gives the numbers.

Chapters 13 and 14 are the climax, and everything before them is there so that they can be read.

## Conventions

The book keeps three conventions. A few words are used in exactly one sense throughout; each is defined where it first appears, and chapter 1 collects them, so some appear in the chapter list above before they are defined. Linux functions are linked to the version 6.12 source on `elixir.bootlin.com` the first time they are named, so that you can read the real code. Figures are diagrams drawn in the text, except for a few drawings.
