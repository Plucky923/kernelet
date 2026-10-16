# Virtual interrupts

A scheduler needs to be interrupted. A time slice ends because a timer interrupt fires; a wake-up on another processor is noticed because an interrupt arrives there. The kernelet has no interrupts of its own: Linux owns the interrupt controller, the vector table and every physical line, and nothing in vOSTD can register a handler for any of them. This chapter gives the kernelet virtual ones.

## Bits in a record

A virtual interrupt is a bit in the `pending` word of a virtual CPU's record (chapter 8). The endovisor sets it, from any context; the kernelet's handler for it runs on that virtual CPU's carrier, in ordinary task context, soon after. Two bits exist in this prototype:

| bit | meaning | set by |
|---|---|---|
| TICK | a millisecond of execution has passed on this virtual CPU | the watch timer, below |
| KICK | another virtual CPU wants this one to look at its run queue | the `vcpu_kick` service |

The kernel proper's timer callbacks and its scheduler's tick accounting run from TICK exactly as they would from a hardware timer interrupt. KICK does what a reschedule interrupt does on a machine: it makes the virtual CPU ask its scheduler whether something more urgent has become runnable.

The question is *when* the handler runs, and the answer depends on what the virtual CPU is doing at the moment the bit is set.

## The watch timer

<div class="linux">

**Linux: high-resolution timers and preemption notifiers.** An [`hrtimer`](https://elixir.bootlin.com/linux/v6.12/source/kernel/time/hrtimer.c) is a timer whose callback runs in interrupt context on the processor that armed it; a *pinned* timer stays on that processor, and a *hard* one runs in the interrupt itself even on a real-time kernel. A timer callback can read the registers of whatever the interrupt interrupted with `get_irq_regs()`, which is how Linux's profiler samples programs; if the callback changes the saved instruction pointer, the interrupt returns somewhere else. A **preemption notifier** ([`preempt_notifier_register()`](https://elixir.bootlin.com/linux/v6.12/source/kernel/sched/core.c#L4866)) is a pair of callbacks Linux runs for one task every time it switches that task out of a processor and in to one; KVM uses it to know where its virtual CPUs are.

</div>

The **watch timer** is one `hrtimer` per processor, pinned and hard, with a period of one millisecond. The rule for when it runs is one sentence: **a processor's watch timer is armed exactly while the task running there is a carrier.** Each carrier registers a preemption notifier when it starts, and the notifier's switch-in callback arms the timer of whatever processor the carrier has just landed on; the timer's own callback re-arms itself if it interrupted a carrier and stops otherwise. So a carrier that Linux migrates is watched wherever it lands, and no timer runs on a processor that has no carrier.

*Simplified from `prototype/endovisor/watch.c` and `prototype/endovisor/sched.c`: `klet_watch_arm`, `klet_sched_in`.*

```c
static void klet_sched_in(struct preempt_notifier *pn, int cpu)   /* Linux just put this carrier on a processor */
{
	struct klet_carrier *c = container_of(pn, struct klet_carrier, pnotifier);
	klet_watch_arm(c);
}

void klet_watch_arm(struct klet_carrier *c)
{
	struct hrtimer *timer = this_cpu_ptr(&klet_watch_timer);
	if (!hrtimer_active(timer))
		hrtimer_start(timer, ns_to_ktime(KLET_WATCH_INTERVAL_NS), HRTIMER_MODE_REL_PINNED_HARD);
}
```

Every time it fires, the callback raises TICK and then decides how to deliver it:

*Simplified from `prototype/endovisor/watch.c`: `klet_watch_fn`.*

```c
static enum hrtimer_restart klet_watch_fn(struct hrtimer *timer)
{
	struct pt_regs *regs = get_irq_regs();      /* what the interrupt interrupted */
	struct klet_carrier *c;

	if (!current->kernelet)                     /* not a carrier any more: stop */
		return HRTIMER_NORESTART;
	c = klet_current_carrier();

	klet_virq_raise(c, KLET_VIRQ_TICK);         /* 1. the tick */

	if (user_mode(regs) || !klet_in_image_text(regs->ip) || !klet_in_kernelet(c)) {
		/* in user mode (klet_virq_raise flagged the carrier), in a service, or in Linux: leave it pending */
	} else if (!klet_critical(c)) {
		klet_virq_redirect(c, regs);            /* 2. in kernelet code with interrupts on: deliver now */
	} else {
		/* in kernelet code with interrupts masked: the kernelet delivers it itself when it unmasks */
	}
	/* 3. the bound on critical sections: chapter 10 */

	hrtimer_forward_now(timer, ns_to_ktime(KLET_WATCH_INTERVAL_NS));
	return HRTIMER_RESTART;
}
```

`klet_virq_raise` sets the bit and does the two cheap things that get it noticed: wakes the carrier if it is asleep in `vcpu_idle`, and flags it (chapter 7) if it is in user mode, so that it comes back through the resume hook, `user_run` returns 2, and `execute`'s loop runs the handler before it re-enters user mode.

The interesting case is the middle one: the carrier is executing kernelet code, at an arbitrary instruction, and the kernelet's virtual interrupts are on. A machine would push the interrupted instruction pointer and jump to the handler. The endovisor does the same, by changing one saved register:

*Simplified from `prototype/endovisor/watch.c`: `klet_virq_redirect`.*

```c
bool klet_virq_redirect(struct klet_carrier *c, struct pt_regs *regs)
{
	if (user_mode(regs) || !klet_in_image_text(regs->ip) || !klet_in_kernelet(c))
		return false;
	if (klet_irq_off(c))                         /* interrupts masked: wait */
		return false;
	if (regs->sp - c->vrec.stack_limit < KLET_UPCALL_HEADROOM)   /* not enough stack for the handler */
		return false;

	WRITE_ONCE(c->vrec.virq_ip, regs->ip);       /* where we interrupted the kernelet */
	WRITE_ONCE(c->vrec.irq_off, 1);              /* mask, as hardware clears IF when it takes an interrupt */
	regs->ip = (unsigned long)kernelet_entry_table.virq_entry;   /* return there instead */
	return true;
}
```

When the timer interrupt returns, it returns into the kernelet's upcall stub rather than into the interrupted instruction. `klet_in_kernelet(c)` is the endovisor's own bookkeeping, state `RUNNING` and depth 0, from chapter 6: a carrier inside a service call is never redirected, because it may hold Linux's locks.

## The upcall

The stub is in vOSTD, in assembly, because it is entered between two arbitrary instructions and must put every register and the flags back exactly. It saves everything on the *current task's* kernelet stack, calls a Rust function, and returns to the interrupted instruction.

*Simplified from `prototype/vostd/src/vcpu.rs`: `klet_virq_entry`, `klet_virq_body`.*

```asm
klet_virq_entry:
    sub rsp, 8               ; a slot for the interrupted instruction pointer
    pushfq                   ; the flags
    push rax ... push r15    ; every general register
    mov rbp, rsp
    and rsp, -16             ; align for the call
    call klet_virq_body      ; returns the instruction pointer to resume at
    mov rsp, rbp
    mov [rsp + 128], rax     ; into the slot
    pop r15 ... pop rax
    popfq
    ret                      ; to the interrupted instruction
```

```rust
extern "C" fn klet_virq_body() -> u64 {
    let rec = vrec();
    let ip = unsafe { read_volatile(rec.virq_ip.get()) } as usize;
    assert!(IMAGE_TEXT_LO <= ip && ip < IMAGE_TEXT_HI);   // never resume at an address the host made up

    run_handlers(rec);                                   // TICK: the timer callbacks; KICK: a look at the run queue

    unsafe { write_volatile(rec.irq_off.get(), 0) };     // unmask: the iret
    if get_guard_count() == 0 {                          // kernel-mode preemption: switch if the scheduler wants to
        crate::task::scheduler::might_preempt();
    }
    ip as u64
}

fn run_handlers(rec: &VcpuRec) {
    loop {
        let pending = rec.pending.swap(0, Ordering::AcqRel);
        if pending == 0 { break; }
        if pending & VIRQ_TICK != 0 { crate::timer::call_timer_callback_functions(); }
        if pending & VIRQ_KICK != 0 { cpu_local::set_need_preempt(); }
    }
}
```

The last few lines are something OSTD on a machine does not do today, and the design needs: **kernel-mode preemption**. Because the interrupted instruction pointer is on the task's own stack, the handler may switch to another task before returning, and the interrupted task resumes later, from the same frame, on whichever virtual CPU next picks it. That is how a tick ends a time slice in the middle of a kernel task's computation, as it does on a machine with a preemptible kernel.

```mermaid
flowchart LR
    t["watch timer fires<br/>(interrupt context)"] --> raise["set TICK in the record"]
    raise --> where{"what was interrupted?"}
    where -- "user mode" --> flag["flag the carrier:<br/>resume hook, user_run returns 2"]
    where -- "kernelet code, interrupts on" --> redir["saved ip := virq_entry<br/>irq_off := 1"]
    where -- "kernelet code, interrupts off<br/>or a service, or Linux" --> pend["leave the bit pending"]
    redir --> stub["virq_entry: push all,<br/>klet_virq_body"]
    stub --> h["timer callbacks:<br/>scheduler.update_current(Tick)"]
    h --> pre["irq_off := 0;<br/>might_preempt()"]
    pre --> ret["pop all, ret"]
    pend --> later["delivered when the kernelet<br/>unmasks or returns"]
```

## Interrupts off, and guards

Two separate fields in the record stand for the two ways a kernel holds things off, and they are kept separate because OSTD keeps them separate.

- `irq_off` is the virtual interrupt flag, inverted. vOSTD sets it where OSTD's interrupts-off guard would clear the processor's flag, and clears it when the guard drops; the endovisor sets it when it redirects into the upcall, and the upcall clears it at the end. While it is set, nothing is delivered.
- The **guard count**, the low bits of `preempt_info`, is how many preemption guards and spin locks are held. It does *not* mask interrupts, on a machine or here: a handler may run on top of a task that holds a preemption guard. What a guard forbids is a task switch, which is why `klet_virq_body` calls `might_preempt` only when the count is zero.

Both are updated by the virtual CPU that owns the record, with single instructions where it matters, because the endovisor reads them from an interrupt on the same processor.

A bit that was left pending while interrupts were masked must still be delivered. The guard that unmasks does it:

*Simplified from `prototype/vostd/src/task/preempt/cpu_local.rs` and `prototype/vostd/src/vcpu.rs`: `irq_unmask`, `deliver_if_pending`, `handle_virq`.*

```rust
pub(crate) fn irq_unmask() {
    let leaving = get_guard_count() == 0;       // the end of a critical section?
    /* ... chapter 10's mirror ... */
    set_irq_off(false);
    if leaving {
        vcpu::deliver_if_pending();             // one load and a branch
    }
}

pub(crate) fn deliver_if_pending() {
    if has_pending() { handle_virq(); }
}

pub(crate) fn handle_virq() {                   // the same handlers, called as a function
    {
        let _guard = crate::irq::disable_local();
        run_handlers(vrec());
    }
    crate::task::scheduler::might_preempt();
}
```

The same function is called by every service stub when the service returns, in case a bit arrived while the carrier was in Linux. So a virtual interrupt is delivered by whichever of three paths comes first: the upcall, if the kernelet was interruptible when it arrived; the unmask, if it was not; or the return from user mode or from a service.

## The kick's interrupt

When one virtual CPU kicks another that is running kernelet code on a different processor, waiting for that processor's next watch tick could cost a millisecond. The endovisor sends an inter-processor interrupt instead, with the one Linux function for running a function on another processor:

*Simplified from `prototype/endovisor/sched.c`: `klet_kick_remote`, `klet_kick_ipi`.*

```c
void klet_kick_remote(struct klet_carrier *c)
{
	if (c->state != KLET_RUNNING || c->depth != 0 || !task_on_cpu(c->task))
		return;                                 /* not in kernelet code on a processor: the bit will be found */
	smp_call_function_single(task_cpu(c->task), klet_kick_ipi, c, 0);
}

static void klet_kick_ipi(void *arg)            /* runs in interrupt context on that processor */
{
	struct klet_carrier *c = arg;
	if (current->kernelet == &c->gate)          /* still the same carrier there? */
		klet_virq_redirect(c, get_irq_regs());  /* then deliver now */
}
```

A kick whose bit is already set does nothing at all, so a thousand kicks cost one delivery.

<div class="recap">

**Recap.** Virtual interrupts are bits in the virtual CPU's record: TICK from the watch timer, KICK from `vcpu_kick`. The watch timer is a pinned, hard, one-millisecond `hrtimer` per processor, armed by each carrier's preemption notifier whenever Linux puts the carrier on that processor. When it finds the carrier in kernelet code with virtual interrupts on, it points the interrupted frame at the image's upcall stub, which saves everything on the task's stack, runs the handlers, and may switch tasks before returning: kernel-mode preemption. A carrier in user mode is flagged; one with interrupts masked delivers the bit itself when it unmasks.

</div>
