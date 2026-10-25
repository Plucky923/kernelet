// SPDX-License-Identifier: MPL-2.0

//! The virtual CPU: the record, the virtual-interrupt upcall, and the mirror of
//! the kernelet's guard depth in the host's preemption count.
//!
//! A carrier carries a virtual CPU, not a task. Everything in this module is the
//! part of vOSTD that stands where hardware stands on bare metal: the local
//! interrupt-enable flag, the interrupt entry stub, the reschedule IPI and the
//! idle instruction.
//!
//! # Finding the record without a service call
//!
//! `CpuId::current()` is on the hottest path there is, so it cannot be a service
//! call. The endovisor publishes three numbers in the boot arguments:
//!
//! - the `gs:`-relative offset of the host's current-task pointer,
//! - the offset of the hooks pointer inside the host's task structure,
//! - the offset of the vCPU record from the hooks pointer.
//!
//! Two dependent loads then give the record. The sequence is safe at any
//! instruction boundary: whichever processor the carrier is on, the host's
//! current-task pointer names *this* task, and this task's hooks name this
//! vCPU's record. Migration between the two loads changes nothing.
//!
//! # The mirror
//!
//! Every guard raises the host's own per-processor preemption count by one, with
//! the same single instruction the host's `preempt_disable()` uses, so that the
//! host defers an involuntary preemption of the vCPU until the kernelet's
//! critical section ends. Dropping the last guard is a `dec` whose zero flag
//! means "count zero and reschedule wanted" — the host folds the need-resched
//! bit into the count, inverted, exactly so that this is one instruction — and
//! then vOSTD asks the host to reschedule.
//!
//! Every `inc`/`dec`/`add`/`sub` below is a *single instruction*. That is what
//! makes them safe: before the increment the carrier may be moved to another
//! processor, after it it may not, so the instruction always lands on the
//! processor the carrier is running on. Nothing may be split across a migration.

use core::{
    arch::{asm, global_asm},
    sync::atomic::{AtomicU32, AtomicUsize, Ordering},
};

use crate::abi::{svc, BootArgs, VcpuRec, VIRQ_KICK, VIRQ_LINES, VIRQ_TICK};

static GS_CURRENT_TASK: AtomicUsize = AtomicUsize::new(0);
static GS_PREEMPT_COUNT: AtomicUsize = AtomicUsize::new(0);
static TASK_HOOKS_OFF: AtomicUsize = AtomicUsize::new(0);
static HOOKS_VREC_OFF: AtomicUsize = AtomicUsize::new(0);
static MIRROR_ON: AtomicU32 = AtomicU32::new(0);
static IMAGE_TEXT_LO: AtomicUsize = AtomicUsize::new(0);
static IMAGE_TEXT_HI: AtomicUsize = AtomicUsize::new(0);

/// Records the host offsets. Called once, from `kernelet_entry`.
pub(crate) fn init_host_offsets(boot: &BootArgs) {
    TASK_HOOKS_OFF.store(boot.task_hooks_off as usize, Ordering::Relaxed);
    HOOKS_VREC_OFF.store(boot.hooks_vrec_off as usize, Ordering::Relaxed);
    GS_PREEMPT_COUNT.store(boot.gs_preempt_count as usize, Ordering::Relaxed);
    IMAGE_TEXT_LO.store(boot.image_text_lo as usize, Ordering::Relaxed);
    IMAGE_TEXT_HI.store(boot.image_text_hi as usize, Ordering::Relaxed);
    // Published last: it is what `is_up` tests.
    GS_CURRENT_TASK.store(boot.gs_current_task as usize, Ordering::Release);
    MIRROR_ON.store(
        if boot.mirror_preempt != 0 { 1 } else { 0 },
        Ordering::Release,
    );
}

/// Whether the record can be found yet.
#[inline]
pub(crate) fn is_up() -> bool {
    GS_CURRENT_TASK.load(Ordering::Acquire) != 0
}

/// This vCPU's record.
///
/// # Panics
///
/// Reads nonsense if called before `kernelet_entry`.
#[inline(always)]
pub(crate) fn vrec() -> &'static VcpuRec {
    let off_task = GS_CURRENT_TASK.load(Ordering::Relaxed);
    let task: usize;
    // SAFETY: the offset was published by the host and names its per-processor
    // current-task pointer, which is a valid task pointer at every instruction.
    unsafe {
        asm!(
            "mov {t}, gs:[{o}]",
            t = out(reg) task,
            o = in(reg) off_task,
            options(nostack, readonly, preserves_flags),
        );
    }
    let hooks_slot = task + TASK_HOOKS_OFF.load(Ordering::Relaxed);
    // SAFETY: a carrier's task always has a non-null hooks pointer, and the vCPU
    // record is embedded in the carrier record the hooks belong to.
    let hooks = unsafe { core::ptr::read(hooks_slot as *const usize) };
    // SAFETY: as above.
    unsafe { &*((hooks + HOOKS_VREC_OFF.load(Ordering::Relaxed)) as *const VcpuRec) }
}

/// Tells the endovisor the low bound of the kernelet stack the current OSTD task
/// is on, so that it will not push an upcall frame onto a stack with no room.
#[inline(always)]
pub(crate) fn publish_stack_limit(base: usize) {
    if !is_up() {
        return;
    }
    // SAFETY: the field belongs to this vCPU's record and only vOSTD writes it.
    unsafe { core::ptr::write_volatile(vrec().stack_limit.get(), base as u64) }
}

/// This vCPU's index.
#[inline(always)]
pub(crate) fn current_id() -> u32 {
    if !is_up() {
        return 0;
    }
    vrec().vcpu_id
}

// ---------------------------------------------------------------------------
// The host's preemption count
// ---------------------------------------------------------------------------

/// Marks the mirror as raised or lowered. See [`crate::abi::VcpuRec::mirrored`].
#[inline(always)]
fn set_mirrored(on: bool) {
    if !is_up() {
        return;
    }
    // SAFETY: the field belongs to this vCPU's record and only vOSTD writes it.
    unsafe { core::ptr::write_volatile(vrec().mirrored.get(), if on { 1 } else { 0 }) }
}

/// Whether the host's preemption count currently includes the kernelet's one.
#[inline(always)]
fn mirrored() -> bool {
    if !is_up() {
        return false;
    }
    // SAFETY: the field belongs to this vCPU's record.
    unsafe { core::ptr::read_volatile(vrec().mirrored.get()) != 0 }
}

/// Raises the host's preemption count by one, if it is not already raised.
///
/// The guard is not decoration. The mirror is *boolean*, and the alternative — a
/// count of transitions that vOSTD keeps balanced by construction — turned out to
/// be beyond what could be shown correct here: OSTD's own guard and
/// interrupt-flag lifetimes cross a context switch (`switch_to_task` takes a guard
/// and the *next* task releases it), so the pairing has to hold across tasks and
/// virtual CPUs, and a single unmatched decrement takes Linux's per-processor
/// count to -1 and every task that afterwards runs on that processor with it. So
/// the flag is the authority: raising twice is a no-op, lowering when it is not
/// raised is a no-op, and the worst a mistake can now cost is one missed
/// deferral. Setting the flag is adjacent to the instruction it describes, so the
/// two never disagree at a point where the carrier could migrate.
#[inline(always)]
pub(crate) fn host_preempt_inc() {
    if mirrored() {
        return;
    }
    if MIRROR_ON.load(Ordering::Relaxed) != 0 {
        let off = GS_PREEMPT_COUNT.load(Ordering::Relaxed);
        // SAFETY: the offset names the host's own per-processor preemption count,
        // and this is the instruction the host's `preempt_disable()` executes.
        unsafe {
            asm!(
                "inc dword ptr gs:[{o}]",
                o = in(reg) off,
                options(nostack),
            );
        }
    }
    // *After* the count is up, never before: the flag's whole job is to say that
    // the host's count really is the kernelet's, so that the endovisor can tell a
    // failure of the mirror from the two instructions in which the kernelet is
    // between the two updates. The flag is kept even when the mirror is off, which
    // is what lets the control run measure what the mirror buys.
    set_mirrored(true);
}

/// Lowers the host's preemption count by one and reports whether the host now
/// both wants and may reschedule. One instruction plus a `setz`.
#[inline(always)]
pub(crate) fn host_preempt_dec_and_test() -> bool {
    if !mirrored() {
        return false;
    }
    // Before, never after: from here on the kernelet no longer claims the count,
    // so a preemption in the window below is the host's right and not a failure.
    set_mirrored(false);
    if MIRROR_ON.load(Ordering::Relaxed) == 0 {
        return false;
    }
    let off = GS_PREEMPT_COUNT.load(Ordering::Relaxed);
    let zero: u8;
    // SAFETY: as above. The host keeps `!need_resched` in bit 31 of the same
    // word, so a decrement to exactly zero means "no guards left and the host
    // wants the processor".
    unsafe {
        asm!(
            "dec dword ptr gs:[{o}]",
            "setz {z}",
            o = in(reg) off,
            z = out(reg_byte) zero,
            options(nostack),
        );
    }
    zero != 0
}

// ---------------------------------------------------------------------------
// Virtual interrupts
// ---------------------------------------------------------------------------

/// Whether any virtual interrupt is waiting for this vCPU.
#[inline(always)]
pub(crate) fn has_pending() -> bool {
    is_up() && vrec().pending.load(Ordering::Relaxed) != 0
}

// The assembly upcall stub. Never called: the endovisor points an interrupted
// instruction pointer at it.
//
// It is entered by the host interrupt's own `iret`, on the current OSTD task's
// kernelet stack, at an arbitrary instruction boundary, so it must put every
// general register and RFLAGS back. The interrupted instruction pointer is a
// slot reserved *before* the flags are pushed, so that the last two
// instructions can be `popfq; ret` and touch nothing the interrupted code can
// see. The slot is reserved with `lea`, not `sub`: `sub` writes the arithmetic
// flags, and the `pushfq` after it would then save the flags of the `sub`
// rather than the interrupted code's. An upcall that lands between a compare
// and the instruction that consumes its result (a `setne` or a `jz`) would
// silently change what that code decided. Kernel code has no red zone, so
// pushing below the interrupted `rsp` is safe, and its alignment is unknown,
// so `rsp` is realigned for the call out of `rbp` (already saved).
//
// Because the interrupted instruction pointer ends up on the *task's* stack,
// `handle_virq` may switch OSTD tasks and this frame resumes later, on any
// vCPU. That is kernel-mode preemption.
//
// Stack, with S the `rsp` the interrupt returned with:
//
// ```text
//   S-8                 the interrupted instruction pointer
//   S-16                RFLAGS
//   S-24 .. S-136       rax rcx rdx rbx rbp rsi rdi r8 .. r15
// ```
global_asm!(
    // Its own section, and not plain `.text`: when the image was linked into
    // the module, gcc put an empty `.text` at the head of image_start.S, `ld -r`
    // merged every input `.text` into that one, and the result sat *below*
    // __klet_image_text_start. The endovisor now loads the image itself and
    // takes the text's bounds from its sections; the section stays.
    ".pushsection .text.klet_virq_entry, \"ax\", @progbits",
    ".globl klet_virq_entry",
    ".type klet_virq_entry, @function",
    "klet_virq_entry:",
    "  lea rsp, [rsp - 8]",
    "  pushfq",
    "  push rax",
    "  push rcx",
    "  push rdx",
    "  push rbx",
    "  push rbp",
    "  push rsi",
    "  push rdi",
    "  push r8",
    "  push r9",
    "  push r10",
    "  push r11",
    "  push r12",
    "  push r13",
    "  push r14",
    "  push r15",
    "  mov rbp, rsp",
    "  and rsp, -16",
    "  call klet_virq_body",
    "  mov rsp, rbp",
    "  mov [rsp + 128], rax",
    "  pop r15",
    "  pop r14",
    "  pop r13",
    "  pop r12",
    "  pop r11",
    "  pop r10",
    "  pop r9",
    "  pop r8",
    "  pop rdi",
    "  pop rsi",
    "  pop rbp",
    "  pop rbx",
    "  pop rdx",
    "  pop rcx",
    "  pop rax",
    "  popfq",
    "  ret",
    ".size klet_virq_entry, .-klet_virq_entry",
    ".popsection",
);

extern "C" {
    /// The address the endovisor redirects to. Never called as a function.
    pub(crate) fn klet_virq_entry();
}

/// The Rust half of the upcall. Returns the instruction pointer to resume at.
///
/// The endovisor has already set this vCPU's `irq_off`, as hardware clears IF when
/// it takes an interrupt, so nothing nests inside this. Clearing it at the end is
/// the `iret`.
///
/// Two things make the frame safe across a task switch: the interrupted
/// instruction pointer is copied onto *this task's* stack before anything else,
/// and the record this frame acts on is the one it was entered on, not whichever
/// vCPU it happens to be on when it returns.
#[no_mangle]
extern "C" fn klet_virq_body() -> u64 {
    let rec = vrec();
    let ip = unsafe { core::ptr::read_volatile(rec.virq_ip.get()) } as usize;

    // The endovisor gave us this address; check it before ever returning to it.
    let lo = IMAGE_TEXT_LO.load(Ordering::Relaxed);
    let hi = IMAGE_TEXT_HI.load(Ordering::Relaxed);
    if lo != 0 && (ip < lo || ip >= hi) {
        panic!("the host tried to resume kernelet code at {:#x}", ip);
    }

    // If no guard was held, the kernelet was not in a critical section before the
    // upcall and is in one now, so this frame owns the host's mirrored count for
    // its duration. If a guard was held, the mirror is already up and stays.
    let owns_mirror = crate::task::preempt::cpu_local::get_guard_count() == 0;
    if owns_mirror {
        host_preempt_inc();
    }

    run_handlers(rec);

    // The `iret`: hand the mirror back and unmask, in that order.
    let host_wants_cpu = if owns_mirror {
        host_preempt_dec_and_test()
    } else {
        false
    };
    // SAFETY: the flag belongs to the record this upcall was entered on.
    unsafe { core::ptr::write_volatile(rec.irq_off.get(), 0) };
    if host_wants_cpu {
        host_yield();
    }

    // Kernel-mode preemption: the interrupted instruction pointer is on this
    // task's stack, so the task may be switched away here and resume later on any
    // vCPU. Only if it holds no guard, which is OSTD's own rule.
    if crate::task::preempt::cpu_local::get_guard_count() == 0 {
        crate::task::scheduler::might_preempt();
    }

    ip as u64
}

/// Takes every pending virtual interrupt of `rec` and runs what it means.
fn run_handlers(rec: &VcpuRec) {
    loop {
        let pending = rec.pending.swap(0, Ordering::AcqRel);
        if pending == 0 {
            break;
        }
        if pending & VIRQ_TICK != 0 {
            crate::timer::call_timer_callback_functions();
        }
        if pending & (VIRQ_KICK | VIRQ_LINES) != 0 {
            // What a reschedule IPI means: look again at who should run.
            crate::task::preempt::cpu_local::set_need_preempt();
        }
    }
}

crate::cpu_local_cell! {
    /// Whether this vCPU is inside `handle_virq`. Stops the guard-drop delivery
    /// path from recursing into the handler it is running under.
    static IN_VIRQ: bool = false;
}

/// Delivers pending virtual interrupts from ordinary kernelet code, which is what
/// a guard drop does when it finds one that arrived while interrupts were masked.
pub(crate) fn handle_virq() {
    if IN_VIRQ.load() {
        return;
    }
    IN_VIRQ.store(true);

    {
        // Masking while the handlers run is what the upcall gets from the
        // endovisor; here vOSTD does it itself, and dropping the guard hands the
        // mirror back and asks the host to reschedule if it wanted to.
        let _guard = crate::irq::disable_local();
        run_handlers(vrec());
    }

    // Cleared before the switch below, because the switch may not come back on
    // this vCPU.
    IN_VIRQ.store(false);
    crate::task::scheduler::might_preempt();
}

/// Runs the pending virtual interrupts but does *not* switch tasks.
///
/// This is what `UserMode::execute` uses when the host says "an event; loop
/// again". It must not switch: the tenant's floating-point registers are live on
/// this processor at that point, and another task's kernelet code would clobber
/// them. The `need_preempt` the handlers set is acted on at the next guard drop in
/// kernel code, which is never far away.
pub(crate) fn deliver_no_switch() {
    if !is_up() || IN_VIRQ.load() {
        return;
    }
    IN_VIRQ.store(true);
    {
        let _guard = crate::irq::disable_local();
        run_handlers(vrec());
    }
    IN_VIRQ.store(false);
}

/// Runs the pending virtual interrupts, if there are any, without switching
/// tasks: what the scheduler does before it decides (`open_resched_window`).
#[inline]
pub(crate) fn deliver_pending_no_switch() {
    if has_pending() {
        deliver_no_switch();
    }
}

/// Whether this virtual CPU is inside a virtual-interrupt upcall.
#[inline]
pub(crate) fn in_upcall() -> bool {
    is_up() && IN_VIRQ.load()
}

/// Called from a guard drop that has just brought the depth to zero.
#[inline]
pub(crate) fn deliver_if_pending() {
    if has_pending() {
        handle_virq();
    }
}

// ---------------------------------------------------------------------------
// Services
// ---------------------------------------------------------------------------

/// Asks the host to reschedule: the kernelet's last guard just went away and
/// the host wants this processor.
#[inline]
pub(crate) fn host_yield() {
    if !is_up() {
        return;
    }
    // SAFETY: the service runs on the carrier's own stack and returns.
    unsafe { (svc().vcpu_yield)() }
}

/// Makes virtual CPU `id` take a KICK as soon as it can. What a reschedule IPI
/// is on bare metal.
pub(crate) fn kick(id: u32) {
    // SAFETY: the service only touches the named vCPU's record and carrier.
    unsafe { (svc().vcpu_kick)(id as u64) }
}

/// Starts virtual CPU `id`.
pub fn boot(id: u32) {
    // SAFETY: as above.
    unsafe { (svc().vcpu_boot)(id as u64) }
}

/// Sleeps until something happens. OSTD's idle, for a virtual CPU.
pub(crate) fn idle(deadline_ns: u64) {
    if !is_up() {
        return;
    }
    // vcpu_idle counts as a sleeping service, and is a drain point for
    // dropped address spaces when the caller holds no guard.
    crate::sync::r2::assert_may_sleep("vcpu_idle");
    crate::mm::vm_space::retire::drain_if_safe();
    // SAFETY: the service sleeps on the current kernelet stack and returns.
    unsafe { (svc().vcpu_idle)(deadline_ns) }
}

/// Tells the host that this vCPU has been spinning on a lock whose holder may
/// be a vCPU the host has descheduled.
pub(crate) fn on_spin() {
    if !is_up() {
        return;
    }
    // SAFETY: as above.
    unsafe { (svc().vcpu_on_spin)() }
}
