# How to read this book

This is a tutorial about the **kernelet**: a complete OS kernel that runs *inside* another kernel, and does so *safely*.

The tutorial comes with a prototype implementation of kernelets in Linux. It patches and extends the Linux kernel. With those changes a small Rust kernel written against OSTD, the framework at the bottom of the Rust kernel Asterinas, can run inside Linux, scheduled and stopped by Linux without Linux's own code needing to understand the kernel it runs.

By the end you will know how every part of that prototype works, down to the C and Rust that do it. You will also have run it.

## Who this is for

The book assumes three things: what one operating-systems course teaches, the ability to read C, and a fair command of Rust. From the course you know what a process is, what virtual memory and a page table are, what a system call does, and what an interrupt and a context switch are, in the abstract.

It assumes nothing about the Linux source: every Linux mechanism beyond the course is explained the first time it is needed, in a box like this:

<div class="linux">

**Linux.** Each box says what the mechanism is, what the source calls it, and why the design cares.

</div>

## Code excerpts

Every code excerpt in the book comes from the `prototype/` directory of this repository. Its README says how to build and run the prototype.

A caption under each excerpt names the file it comes from and, for a simplified excerpt, the functions it shows, like this:

*Simplified from `prototype/linux/endovisor/switch.S`: `klet_switch`.*

The caption's first word says how the block differs from the file. "Simplified" means that logging, counters, error paths and comments have been cut so that the mechanism fits on the page. "Unchanged" means that the block is copied from the file verbatim.

## The chapters

The book follows the order in which a kernelet comes to life, so each chapter uses only what the ones before it have built. Chapters 13 and 14 are the climax; everything before them prepares for them.

1. **Why a kernel of your own** says what a kernelet is and why it can be safe.
2. **The endovisor UAPI**, its user-space interface, is what a program on the host may ask of the endovisor: the image as a file, the device node and its descriptors, and how user space creates the carriers.
3. **The kernel we will run** reads the hundred-line kernel that runs throughout the book, and lists what it needs from a machine.
4. **The kernelet ABI**, its binary interface, is how a kernelet talks to its host from the inside: the three tables, the grant, and the first services.
5. **Carrier hooks and patch overview** adds the two carrier event hooks, at a carrier's system call and on its way back to user mode, which is where a carrier enters and leaves kernelet code, and lists the rest of the one small patch to Linux.
6. **Carriers** puts a kernelet on the Linux tasks it runs on.
7. **Two stacks** is how a kernelet keeps its own stacks on a Linux task.
8. **Into user mode and back** is the round trip of a system call, after which the hundred-line kernel prints its greeting.
9. **Tasks and virtual CPUs** gives the kernelet its own tasks and its own scheduler.
10. **Virtual interrupts** gives it a timer.
11. **Sharing a processor politely** keeps it from holding a processor against Linux.
12. **Stopping a kernelet** removes it, even when it will not cooperate.
13. **Tenant memory on Linux's page tables** puts the tenant's memory in a Linux address space that the kernelet edits only by asking.
14. **What vOSTD adds on top** is the bookkeeping that keeps that arrangement memory-safe, or *sound*, in chapter 1's term.
15. **What it costs** gives the numbers.

## Conventions

The book keeps three conventions.

- A few words are used in exactly one sense throughout. Each is introduced where it first appears, collected in chapter 1, and defined in full in the chapter named beside it there; a few appear in the chapter list above before chapter 1 defines them.
- Linux functions are linked to the version 6.12 source on `elixir.bootlin.com` the first time they are named, so that you can read the real code.
- Most figures are diagrams written as text in the page source; a few are drawings.
