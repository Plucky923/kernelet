# How to read this book

This is a tutorial about the **kernelet**: a complete OS kernel that runs *inside* another kernel, and does so *safely*.

The tutorial comes with a prototype implementation of kernelets in Linux. It patches and extends the Linux kernel. With those changes small Rust kernels written against OSTD, the framework at the bottom of the Rust kernel Asterinas, can run inside Linux, scheduled and stopped by Linux without Linux's own code needing to understand the kernel it runs.

By the end you will know how every part of that prototype works, down to the C and Rust that do it. You will also have run it; the prototype's README says how.

## Who this is for

The book assumes three things: what one operating-systems course teaches, the ability to read C, and a fair command of Rust. From the course you know what a process is, what virtual memory and a page table are, what a system call does, and what an interrupt and a context switch are, in the abstract.

It assumes nothing about the Linux source. Background knowledge beyond the course, whether about Linux, ELF, compiler behavior or processor details, is explained the first time it is needed in a **background box**. Each box begins with a subject and a topic, such as **Linux: control groups** or **ELF: relocations**. It explains the concept, the names used for it in the relevant code or format, and why it matters to the kernelet design.

<div class="background">

**Linux: control groups.** A control group is a set of tasks that Linux accounts and limits together. The prototype puts a sandbox's carrier tasks in one group so that Linux can account for their resource use together.

</div>

If you already know a box's topic, you can continue with the main text. The same box style is used for every subject; the label tells you which background knowledge it introduces.

## Code excerpts

Every code excerpt in the book comes from the `prototype/` directory of this repository.

A caption under each excerpt names the file it comes from and, for a simplified excerpt, the functions it shows, like this:

*Simplified from `prototype/linux/endovisor/switch.S`: `klet_switch`.*

The caption's first word says how the block differs from the file. "Simplified" means that logging, counters, error paths and comments have been cut so that the mechanism fits on the page. "Unchanged" means that the block is copied from the file verbatim.

## The chapters

Each chapter uses only what the ones before it have built.

Some words in the list below are defined only in the next chapter; skim past them.

1. **Why a kernel of your own** says what a kernelet is and why it can be safe.
2. **The endovisor UAPI**, its user-space interface, is what a program on the host may ask of the endovisor: the image as a file, the device node and its descriptors, and how user space creates the carriers.
3. **The first kernel we will run** reads the hundred-line kernel that runs throughout the book, and lists what it needs from a machine.
4. **The kernelet ABI**, its binary interface, is how a kernelet talks to its host from the inside: the tables passed between host and kernelet, the grant, and the first services.
5. **Carrier hooks and patch overview** adds the two carrier event hooks, where a carrier enters and leaves kernelet code, and lists the rest of the small patch the prototype makes to Linux.
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

Chapters 13 and 14, where the tenant's memory moves onto Linux's page tables without giving up soundness, are the climax; everything before them prepares for them.

## Conventions

The book keeps three conventions.

- A few words are used in exactly one sense throughout; the word table at the end of the next chapter collects the first of them, and the chapter named beside a word there defines it in full.
- Linux functions are linked to the version 6.12 source on `elixir.bootlin.com` the first time they are named, so that you can read the real code.
- Most figures are diagrams written as text in the page source; a few are drawings.
