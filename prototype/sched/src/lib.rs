// SPDX-License-Identifier: MPL-2.0

//! The sched kernel: a kernel proper with **its own task scheduler**.
//!
//! Everything below is safe Rust written against real OSTD's scheduler-injection
//! interface — [`ostd::task::scheduler::inject_scheduler`], the [`Scheduler`] and
//! [`LocalRunQueue`] traits, [`UpdateFlags`], [`EnqueueFlags`] — so it would
//! compile against Asterinas's OSTD unchanged. What it proves is that the
//! *kernelet's* scheduler is what decides which kernelet task runs, on a Linux
//! host, on virtual CPUs that Linux schedules and knows nothing about.
//!
//! # The policy
//!
//! Strict priority, round-robin within a priority level with a 5 ms slice,
//! per-vCPU run queues, and wake-ups that go to the waker's vCPU unless the task
//! is pinned. Priority and pinning are carried in the task's data, which is
//! exactly what [`ostd::task::TaskOptions::data`] is for. Linux's fair class
//! would never produce this order.
//!
//! # The scenarios
//!
//! One image serves all of them; which one runs comes from the sandbox's command
//! line (`ostd::boot::boot_info().kernel_cmdline`), as a scenario would come from
//! a kernel command line on a machine.

#![no_std]
#![deny(unsafe_code)]

extern crate alloc;

use align_ext::AlignExt;

use alloc::{boxed::Box, sync::Arc, vec::Vec};
use core::{
    sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering},
    time::Duration,
};

use ostd::{
    arch::{cpu::context::{FpuContext, UserContext}, read_tsc},
    boot::{boot_info, smp::register_ap_entry},
    cpu::{num_cpus, CpuId, PinCurrentCpu},
    irq::DisabledLocalIrqGuard,
    mm::{
        CachePolicy, FrameAllocOptions, PageFlags, PageProperty, Vaddr, VmIo, VmSpace, PAGE_SIZE,
    },
    power::{poweroff, ExitCode},
    prelude::*,
    sync::{SpinLock, WaitQueue},
    task::{
        disable_preempt, inject_post_schedule_handler, inject_pre_schedule_handler,
        scheduler::{
            enable_preemption_on_cpu, info::CommonSchedInfo, inject_scheduler, EnqueueFlags,
            LocalRunQueue, Scheduler, UpdateFlags,
        },
        Task, TaskOptions,
    },
    timer::{Jiffies, TIMER_FREQ},
    user::{DummyUserHooks, ReturnReason, UserMode, UserContextApi},
};

// ---------------------------------------------------------------------------
// The policy's constants
// ---------------------------------------------------------------------------

/// How many priority levels: 0 is the most urgent.
const NR_LEVELS: usize = 3;
/// The round-robin slice inside a level, in ticks (and a tick is 1 ms).
const SLICE_TICKS: u32 = 5;

const MAP_ADDR: Vaddr = 0x0040_0000;
const ENTRY_POINT: Vaddr = 0x0040_1000;

/// The kernel's own system-call numbers, which the tenant program uses.
const SYS_YIELD: usize = 3000;
const SYS_FPU_OK: usize = 3001;
const SYS_FPU_BAD: usize = 3002;

// ---------------------------------------------------------------------------
// What a task carries
// ---------------------------------------------------------------------------

/// Per-task data: the scheduler reads the first three fields, the kernel proper
/// the rest. OSTD never looks inside.
struct TaskInfo {
    id: u32,
    prio: u8,
    pinned: Option<u32>,
    /// When this task should stop, in milliseconds since the sandbox started. A
    /// scenario staggers these so that every priority level gets a turn: strict
    /// priority means a level only runs when nothing above it is runnable.
    deadline_ms: u64,
    /// The user-mode side of a tenant thread, if it has one.
    user: Option<UserSide>,
}

struct UserSide {
    vm_space: Arc<VmSpace>,
    /// What goes in `rdi` on the first entry to user mode.
    role: u64,
    /// This tenant thread's floating-point state. The kernel proper swaps it
    /// around every task switch, through OSTD's pre- and post-schedule handlers,
    /// which is where Asterinas does it too.
    fpu: SpinLock<FpuContext>,
}

fn info_of(task: &Task) -> Option<&TaskInfo> {
    task.data().downcast_ref::<TaskInfo>()
}

fn prio_of(task: &Task) -> u8 {
    info_of(task).map(|i| i.prio).unwrap_or((NR_LEVELS - 1) as u8)
}

fn id_of(task: &Task) -> u32 {
    info_of(task).map(|i| i.id).unwrap_or(0)
}

// ---------------------------------------------------------------------------
// The trace
// ---------------------------------------------------------------------------

#[derive(Clone, Copy)]
struct Switch {
    seq: u32,
    vcpu: u8,
    prev: u32,
    next: u32,
    prio: u8,
    reason: u8,
    ms: u64,
    tsc: u64,
    /// This virtual CPU's own tick count. The slice is five *ticks*, and a virtual
    /// CPU the host has descheduled receives none, so a slice that is five ticks
    /// long can be seven milliseconds of wall clock. Checking it in ticks is
    /// checking the policy; checking it in milliseconds would be measuring the
    /// host's scheduling of the carrier.
    ticks: u64,
}

const TRACE_CAP: usize = 16384;
static TRACE: SpinLock<Vec<Switch>> = SpinLock::new(Vec::new());
static TRACE_SEQ: AtomicU32 = AtomicU32::new(0);
static TRACE_LOST: AtomicU32 = AtomicU32::new(0);

fn reason_name(r: u8) -> &'static str {
    match r {
        0 => "tick",
        1 => "wait",
        2 => "yield",
        3 => "exit",
        _ => "pick",
    }
}

fn trace_push(s: Switch) {
    // With interrupts masked: the upcall's tick handler reaches the scheduler,
    // and the scheduler reaches this.
    let mut t = TRACE.disable_irq().lock();
    if t.len() < TRACE_CAP {
        t.push(s);
    } else {
        TRACE_LOST.fetch_add(1, Ordering::Relaxed);
    }
}

fn trace_dump() {
    let t = TRACE.disable_irq().lock();
    println!("SCHED-TRACE begin {} switch(es), {} lost", t.len(),
             TRACE_LOST.load(Ordering::Relaxed));
    for s in t.iter() {
        println!(
            "SCHED: sw {} v{} {}->{} p{} r{} @{} c{} k{}",
            s.seq, s.vcpu, s.prev, s.next, s.prio, reason_name(s.reason), s.ms,
            s.tsc, s.ticks
        );
    }
    println!("SCHED-TRACE end");
}

/// Events the scheduler cannot see but the reference model needs: when a task
/// went to sleep and when one was woken, and by whom.
fn event(kind: &str, id: u32, vcpu: u32) {
    println!("SCHED-EV {} t{} v{} @{}", kind, id, vcpu, now_ms());
}

fn now_ms() -> u64 {
    Jiffies::elapsed().as_u64() * 1000 / TIMER_FREQ
}

// ---------------------------------------------------------------------------
// The scheduler
// ---------------------------------------------------------------------------

struct PrioScheduler {
    rq: Vec<SpinLock<PrioRunQueue>>,
}

struct PrioRunQueue {
    vcpu: u32,
    levels: [Vec<Arc<Task>>; NR_LEVELS],
    current: Option<Arc<Task>>,
    /// Ticks left in the current task's slice.
    slice_left: u32,
    /// Why `update_current` last said yes, for the trace.
    reason: u8,
    /// How many ticks this virtual CPU has taken.
    ticks: u64,
    /// The task `dequeue_current` last took out, for the trace: a sleeping or
    /// exiting task is gone from `current` by the time the next one is picked, and
    /// the reference model has to be able to see which one it was.
    dequeued: u32,
}

impl PrioRunQueue {
    fn new(vcpu: u32) -> Self {
        Self {
            vcpu,
            levels: [Vec::new(), Vec::new(), Vec::new()],
            current: None,
            slice_left: SLICE_TICKS,
            reason: 4,
            ticks: 0,
            dequeued: 0,
        }
    }

    /// The most urgent level with a runnable task, if any.
    fn best_level(&self) -> Option<usize> {
        (0..NR_LEVELS).find(|&l| !self.levels[l].is_empty())
    }
}

impl PrioScheduler {
    fn new(nr_cpus: usize) -> Self {
        let mut rq = Vec::new();
        for i in 0..nr_cpus {
            rq.push(SpinLock::new(PrioRunQueue::new(i as u32)));
        }
        Self { rq }
    }
}

impl Scheduler<Task> for PrioScheduler {
    fn enqueue(&self, runnable: Arc<Task>, flags: EnqueueFlags) -> Option<CpuId> {
        let prio = prio_of(&runnable) as usize;
        let prio = prio.min(NR_LEVELS - 1);

        // Where should it go? Pinned tasks have no choice; a wake-up follows the
        // waker, and so does a spawn, which keeps a producer and its consumer on
        // one virtual CPU unless the kernel says otherwise.
        let wanted = match info_of(&runnable).and_then(|i| i.pinned) {
            Some(v) => CpuId::new(v.min(num_cpus() as u32 - 1)),
            None => CpuId::current_racy(),
        };

        // OSTD's rule: a task may be in at most one runqueue. `set_if_is_none`
        // is the claim; if someone else already holds it, follow them.
        let (still_queued, target) = match runnable.cpu().set_if_is_none(wanted) {
            Ok(()) => (false, wanted),
            Err(other) => {
                debug_assert!(flags != EnqueueFlags::Spawn);
                (true, other)
            }
        };

        let mut rq = self.rq[target.as_usize()].disable_irq().lock();
        if still_queued && runnable.cpu().set_if_is_none(target).is_err() {
            return None;
        }

        // Does it deserve the processor it landed on?
        //
        // Only if something less urgent is running there. An *idle* virtual CPU
        // needs no preemption — it picks the task up itself — but a remote idle
        // one has to be woken, and that is what returning its id does. Saying yes
        // for the local idle case would be wrong in a way that is easy to miss:
        // the bootstrap context has no current task either, so the first
        // `Task::run` of `main` would switch away and the rest of `main` would
        // never run.
        let preempt = match rq.current.as_ref() {
            None => target != CpuId::current_racy(),
            Some(cur) => (prio as u8) < prio_of(cur),
        };
        rq.levels[prio].push(runnable);
        drop(rq);

        if preempt {
            Some(target)
        } else {
            None
        }
    }

    fn local_rq_with(&self, f: &mut dyn FnMut(&dyn LocalRunQueue<Task>)) {
        let preempt_guard = disable_preempt();
        let rq = self.rq[preempt_guard.current_cpu().as_usize()]
            .disable_irq()
            .lock();
        f(&*rq);
    }

    fn mut_local_rq_with(&self, f: &mut dyn FnMut(&mut dyn LocalRunQueue<Task>)) {
        let preempt_guard = disable_preempt();
        let mut rq = self.rq[preempt_guard.current_cpu().as_usize()]
            .disable_irq()
            .lock();
        f(&mut *rq);
    }
}

impl LocalRunQueue<Task> for PrioRunQueue {
    fn current(&self) -> Option<&Arc<Task>> {
        self.current.as_ref()
    }

    fn update_current(&mut self, flags: UpdateFlags) -> bool {
        match flags {
            UpdateFlags::Tick => {
                self.reason = 0;
                self.ticks += 1;
                let Some(cur) = self.current.as_ref() else {
                    return self.best_level().is_some();
                };
                let cur_prio = prio_of(cur) as usize;

                // Strict priority: anything more urgent takes the processor now.
                if let Some(best) = self.best_level() {
                    if best < cur_prio {
                        return true;
                    }
                }

                // Round robin inside the level, on a 5 ms slice.
                if self.slice_left > 0 {
                    self.slice_left -= 1;
                }
                self.slice_left == 0 && !self.levels[cur_prio].is_empty()
            }
            UpdateFlags::Wait => {
                self.reason = 1;
                self.best_level().is_some()
            }
            UpdateFlags::Yield => {
                self.reason = 2;
                self.best_level().is_some()
            }
            UpdateFlags::Exit => {
                self.reason = 3;
                self.best_level().is_some()
            }
        }
    }

    fn try_pick_next(&mut self) -> Option<&Arc<Task>> {
        let level = self.best_level()?;
        let next = self.levels[level].remove(0);
        let next_id = id_of(&next);
        let prev_id = self
            .current
            .as_ref()
            .map(|t| id_of(t))
            .unwrap_or(self.dequeued);
        self.dequeued = 0;

        if let Some(prev) = self.current.replace(next) {
            // Still runnable, so back it goes — at the *tail* of its level, which
            // is what makes the level round robin.
            let p = (prio_of(&prev) as usize).min(NR_LEVELS - 1);
            self.levels[p].push(prev);
        }
        self.slice_left = SLICE_TICKS;

        trace_push(Switch {
            seq: TRACE_SEQ.fetch_add(1, Ordering::Relaxed),
            vcpu: self.vcpu as u8,
            prev: prev_id,
            next: next_id,
            prio: level as u8,
            reason: self.reason,
            ms: now_ms(),
            tsc: read_tsc(),
            ticks: self.ticks,
        });
        self.reason = 4;

        self.current.as_ref()
    }

    fn dequeue_current(&mut self) -> Option<Arc<Task>> {
        let out = self.current.take().inspect(|task| task.cpu().set_to_none());
        if let Some(t) = out.as_ref() {
            self.dequeued = id_of(t);
        }
        out
    }
}

// ---------------------------------------------------------------------------
// Floating-point state
// ---------------------------------------------------------------------------

/*
 * Where the swap has to go, and why it is not where it first looks like it should
 * be.
 *
 * The obvious place is the task switch, through OSTD's pre- and post-schedule
 * handlers, and that is wrong. Kernel code uses the vector registers: `memcpy`,
 * `memset` and anything the compiler decides to vectorise all live in xmm, and a
 * kernelet runs in kernel mode *on the tenant's live floating-point state*, because
 * the host defers loading and saving it until the return to user mode. So by the
 * time a task switch happens, the live registers are no longer the tenant's, and
 * saving them there saves rubbish over the good copy.
 *
 * The right boundary is the user/kernel one, which is where Asterinas puts it too:
 * save the moment the kernel gets control back from user mode, load the moment
 * before giving it back. These two handlers are still registered, to show that a
 * kernel proper may have them, and they deliberately do nothing to the
 * floating-point state.
 */
fn pre_schedule(_guard: &DisabledLocalIrqGuard) {}

fn post_schedule() {}

// ---------------------------------------------------------------------------
// The command line
// ---------------------------------------------------------------------------

fn arg(key: &str) -> Option<&'static str> {
    let line: &'static str = &boot_info().kernel_cmdline;
    for token in line.split_whitespace() {
        if let Some(rest) = token.strip_prefix(key) {
            if let Some(value) = rest.strip_prefix('=') {
                return Some(value);
            }
        }
    }
    None
}

fn arg_u64(key: &str, default: u64) -> u64 {
    arg(key).and_then(|v| v.parse::<u64>().ok()).unwrap_or(default)
}

fn mode() -> &'static str {
    arg("mode").unwrap_or("policy")
}

// ---------------------------------------------------------------------------
// Shared run state
// ---------------------------------------------------------------------------

static DEADLINE_MS: AtomicU64 = AtomicU64::new(0);
static LIVE: AtomicU32 = AtomicU32::new(0);
static STOP: AtomicBool = AtomicBool::new(false);

fn past_deadline() -> bool {
    STOP.load(Ordering::Relaxed) || now_ms() >= DEADLINE_MS.load(Ordering::Relaxed)
}

/// Burns roughly `us` microseconds of kernelet time without ever giving the
/// processor up voluntarily.
fn burn_us(us: u64) {
    let khz_guess = 1_000_000u64; // one iteration ~ 1 ns on any modern machine
    let end = read_tsc() + us * (khz_guess / 1000) * 3;
    while read_tsc() < end {
        core::hint::spin_loop();
    }
}

// ---------------------------------------------------------------------------
// Statistics
// ---------------------------------------------------------------------------

static LOCK_OPS: AtomicU64 = AtomicU64::new(0);
static LOCK_MAX_WAIT: AtomicU64 = AtomicU64::new(0);
static SHARED: SpinLock<u64> = SpinLock::new(0);
static OVERSTAYS: AtomicU64 = AtomicU64::new(0);
static OVERSTAY_MAX: AtomicU64 = AtomicU64::new(0);

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

#[ostd::main]
pub fn main() {
    inject_scheduler(Box::leak(Box::new(PrioScheduler::new(num_cpus()))) as &dyn Scheduler<Task>);
    inject_pre_schedule_handler(pre_schedule);
    inject_post_schedule_handler(post_schedule);
    TRACE.disable_irq().lock().reserve(TRACE_CAP);

    let m = mode();
    let dur = arg_u64("dur", 3000);
    DEADLINE_MS.store(now_ms() + dur, Ordering::Relaxed);
    println!(
        "SCHED-CONF mode={} dur={} vcpus={} levels={} slice_ticks={}",
        m, dur, num_cpus(), NR_LEVELS, SLICE_TICKS
    );

    // The other virtual CPUs. Registering the entry point is what starts them,
    // and it must happen after the scheduler is injected.
    register_ap_entry(ap_main);

    match m {
        "policy" => scenario_policy(),
        "coop" => scenario_coop(false),
        "coop-over" => scenario_coop(true),
        "fair" => scenario_fair(arg_u64("tasks", 1) as usize, arg_u64("over", 0) != 0),
        "perf" => scenario_perf(),
        "fpu" => scenario_fpu(),
        other => {
            println!("SCHED: unknown mode {}", other);
            poweroff(ExitCode::Failure);
        }
    }

    /*
     * Last, and it has to be last. This is what registers the tick callback that
     * sets `need_preempt`, and `Task::run` ends in `might_preempt()`: with the
     * callback already registered, the first task created here would take the
     * processor and the bootstrap context — which has no task to come back to —
     * would be abandoned with the rest of the scenario uncreated. Real OSTD has
     * the same shape; its own documentation puts `enable_preemption_on_cpu` after
     * initialization for this reason.
     */
    enable_preemption_on_cpu();
}

fn ap_main() {
    enable_preemption_on_cpu();
}

// ---------------------------------------------------------------------------
// Building tasks
// ---------------------------------------------------------------------------

fn kernel_task<F>(id: u32, prio: u8, pinned: Option<u32>, func: F) -> Arc<Task>
where
    F: FnOnce() + Send + 'static,
{
    println!(
        "SCHED-TASK t{} prio={} pin={} kind=kernel",
        id,
        prio,
        pinned.map(|v| v as i64).unwrap_or(-1)
    );
    LIVE.fetch_add(1, Ordering::Relaxed);
    Arc::new(
        TaskOptions::new(move || {
            func();
            LIVE.fetch_sub(1, Ordering::Relaxed);
        })
        .data(TaskInfo {
            id,
            prio,
            pinned,
            deadline_ms: u64::MAX,
            user: None,
        })
        .build()
        .unwrap(),
    )
}

/// One tenant address space with the program mapped into it, plus one page of
/// zeroed data the program may use.
fn new_vm_space(program: &[u8]) -> Arc<VmSpace> {
    let nbytes = program.len().align_up(PAGE_SIZE);
    let pages = {
        let segment = FrameAllocOptions::new()
            .alloc_segment(nbytes / PAGE_SIZE)
            .unwrap();
        segment.write_bytes(0, program).unwrap();
        segment
    };

    let vm_space = VmSpace::new();
    let preempt_guard = disable_preempt();
    let mut cursor = vm_space
        .cursor_mut(&preempt_guard, &(MAP_ADDR..MAP_ADDR + nbytes))
        .unwrap();
    let prop = PageProperty::new_user(PageFlags::RWX, CachePolicy::Writeback);
    for frame in pages {
        cursor.map(frame.into(), prop);
    }
    drop(cursor);
    drop(preempt_guard);
    Arc::new(vm_space)
}

fn user_task(
    id: u32,
    prio: u8,
    pinned: Option<u32>,
    vm_space: Arc<VmSpace>,
    role: u64,
    deadline_ms: u64,
) -> Arc<Task> {
    println!(
        "SCHED-TASK t{} prio={} pin={} kind=user role={}",
        id,
        prio,
        pinned.map(|v| v as i64).unwrap_or(-1),
        role
    );
    LIVE.fetch_add(1, Ordering::Relaxed);
    Arc::new(
        TaskOptions::new(move || {
            run_user_thread();
            LIVE.fetch_sub(1, Ordering::Relaxed);
        })
        .data(TaskInfo {
            id,
            prio,
            pinned,
            deadline_ms,
            user: Some(UserSide {
                vm_space,
                role,
                fpu: SpinLock::new(FpuContext::new()),
            }),
        })
        .build()
        .unwrap(),
    )
}

/// What every tenant thread's task runs. The loop is the one from the 100-line
/// kernel; what is new is that the address space is activated on each trip, so
/// that a virtual CPU that ran another tenant's thread a moment ago ends up in
/// the right one.
fn run_user_thread() {
    let current = Task::current().unwrap();
    let info = info_of(&current).unwrap();
    let user = info.user.as_ref().unwrap();

    let mut user_mode = {
        let mut ctx = UserContext::default();
        ctx.set_instruction_pointer(ENTRY_POINT);
        ctx.set_rdi(user.role as usize);
        UserMode::new(ctx)
    };

    loop {
        user.vm_space.activate();
        // This thread's own floating-point state, live for the trip to user mode.
        user.fpu.disable_irq().lock().load();
        let reason = user_mode.execute(&DummyUserHooks);
        // And back into its own area before any kernelet code touches xmm.
        user.fpu.disable_irq().lock().save();
        let ctx = user_mode.context_mut();
        match reason {
            ReturnReason::UserSyscall => {
                if handle_syscall(info, ctx) {
                    return;
                }
            }
            ReturnReason::UserException => {
                println!("SCHED: t{} unexpected exception, giving up", info.id);
                poweroff(ExitCode::Failure);
            }
            ReturnReason::KernelEvent => (),
        }
    }
}

static FPU_CHECKINS: AtomicU64 = AtomicU64::new(0);
static FPU_FAILED: AtomicBool = AtomicBool::new(false);
static USER_SWITCH_LAST: SpinLock<[(u32, u64); 8]> = SpinLock::new([(0, 0); 8]);
static USER_SWITCH_SAMPLES: SpinLock<Vec<u64>> = SpinLock::new(Vec::new());

/// Returns true if the thread should exit.
fn handle_syscall(info: &TaskInfo, ctx: &mut UserContext) -> bool {
    match ctx.rax() {
        SYS_YIELD => {
            // For the switch measurement (tenant role 2): rsi is this thread's
            // last yield as it timed it in user mode. It is a round trip through
            // the other tenant thread, and a sample, only if the other thread
            // was the last to yield on this virtual CPU, i.e. it ran in between:
            // the same rule as the native measurement's `turn` flag.
            let guard = disable_preempt();
            let v = guard.current_cpu().as_usize();
            {
                let mut last = USER_SWITCH_LAST.disable_irq().lock();
                let (last_id, _) = last[v];
                let sample = ctx.rsi() as u64;
                if info.user.as_ref().is_some_and(|u| u.role == ROLE_PINGPONG)
                    && last_id != 0
                    && last_id != info.id
                    && sample != 0
                {
                    let mut s = USER_SWITCH_SAMPLES.disable_irq().lock();
                    if s.len() < 8192 {
                        s.push(sample);
                    }
                }
                last[v] = (info.id, read_tsc());
            }
            drop(guard);
            ctx.set_rax(0);
            Task::yield_now();
            past_deadline() || now_ms() >= info.deadline_ms
        }
        SYS_FPU_OK => {
            FPU_CHECKINS.fetch_add(1, Ordering::Relaxed);
            ctx.set_rax(0);
            Task::yield_now();
            past_deadline() || now_ms() >= info.deadline_ms
        }
        SYS_FPU_BAD => {
            FPU_FAILED.store(true, Ordering::Relaxed);
            println!("SCHED-FPU t{} FAILED: an xmm register changed", info.id);
            true
        }
        other => {
            println!("SCHED: t{} unimplemented syscall {}", info.id, other);
            poweroff(ExitCode::Failure);
        }
    }
}

// ---------------------------------------------------------------------------
// Scenario 1: the policy is obeyed, and it preempts
// ---------------------------------------------------------------------------

static SLEEPER: WaitQueue = WaitQueue::new();
static SLEEPER_READY: AtomicBool = AtomicBool::new(false);
static SLEEPER_STOP: AtomicBool = AtomicBool::new(false);
static WAKE_STAMP_P: AtomicU64 = AtomicU64::new(0);
static WAKES: AtomicU64 = AtomicU64::new(0);
static WAKE_LATENCY_MAX: AtomicU64 = AtomicU64::new(0);

/// Several kernel tasks and two tenant threads at three priority levels, some
/// CPU-bound, one asleep and being woken from the *other* virtual CPU.
///
/// The level-1 tasks stop half way through, because strict priority means level 2
/// never runs while a level-1 task is runnable; that is the policy, and the trace
/// has to show both halves for the reference model to have anything to check about
/// the lower level.
fn scenario_policy() {
    let program = include_bytes!("../sched");
    let vm = new_vm_space(program);
    let dur = arg_u64("dur", 3000);
    let half = now_ms() + dur / 2;

    println!("SCHED-PHASE half={} end={}", half, DEADLINE_MS.load(Ordering::Relaxed));

    // Level 0 on vCPU 0: asleep, and urgent the moment it is woken.
    kernel_task(1, 0, Some(0), || {
        loop {
            let woken = SLEEPER.wait_until(|| {
                if SLEEPER_READY.swap(false, Ordering::Acquire) {
                    Some(true)
                } else if SLEEPER_STOP.load(Ordering::Acquire) || past_deadline() {
                    Some(false)
                } else {
                    None
                }
            });
            if !woken {
                break;
            }
            let stamp = WAKE_STAMP_P.load(Ordering::Acquire);
            if stamp != 0 {
                let dt = read_tsc().wrapping_sub(stamp);
                WAKE_LATENCY_MAX.fetch_max(dt, Ordering::Relaxed);
            }
            event("run", 1, u32::from(CpuId::current_racy()));
            burn_us(1000);
        }
    })
    .run();

    // Level 1: CPU-bound, one per virtual CPU, until half way.
    kernel_task(2, 1, Some(0), move || {
        while !past_deadline() && now_ms() < half {
            burn_us(200);
        }
    })
    .run();

    // Level 1 on the other virtual CPU, and the one that wakes the urgent task —
    // from across, so the wake goes through the endovisor's kick.
    kernel_task(3, 1, Some(1), move || {
        let mut next = now_ms() + 30;
        while !past_deadline() && now_ms() < half {
            burn_us(200);
            if now_ms() >= next {
                next = now_ms() + 30;
                WAKE_STAMP_P.store(read_tsc(), Ordering::Release);
                SLEEPER_READY.store(true, Ordering::Release);
                event("wake", 1, u32::from(CpuId::current_racy()));
                WAKES.fetch_add(1, Ordering::Relaxed);
                SLEEPER.wake_all();
            }
        }
        // Let the sleeper go too, or it would wait for a wake that never comes.
        SLEEPER_STOP.store(true, Ordering::Release);
        SLEEPER.wake_all();
    })
    .run();

    // Level 2: CPU-bound to the end. They only get a processor once level 1 is
    // gone, which is what the trace has to show.
    kernel_task(4, 2, Some(0), || {
        while !past_deadline() {
            burn_us(200);
        }
    })
    .run();
    kernel_task(5, 2, Some(1), || {
        while !past_deadline() {
            burn_us(200);
        }
    })
    .run();

    // Two tenant threads at two different levels, sharing one address space.
    user_task(6, 1, Some(0), vm.clone(), 0, half).run();
    user_task(7, 2, Some(1), vm.clone(), 0, u64::MAX).run();

    reaper(|| {
        trace_dump();
        println!(
            "SCHED-RESULT policy wakes={} max_wake_latency_cycles={}",
            WAKES.load(Ordering::Relaxed),
            WAKE_LATENCY_MAX.load(Ordering::Relaxed)
        );
    });
}

// ---------------------------------------------------------------------------
// Scenario 2: cooperative — spin locks while Linux preempts the carriers
// ---------------------------------------------------------------------------

/// Nothing is pinned here, on purpose: a task that migrates between virtual CPUs
/// is also a carrier that Linux may move between processors, and the question the
/// experiment asks — is a carrier ever descheduled in the middle of a critical
/// section — has to be asked of a carrier that has been preempted and moved.
fn scenario_coop(overstayer: bool) {
    for i in 0..4u32 {
        kernel_task(10 + i, 1, None, move || {
            while !past_deadline() {
                for _ in 0..200 {
                    let t0 = read_tsc();
                    let mut g = SHARED.lock();
                    *g += 1;
                    // A short critical section: a handful of memory operations.
                    let mut x = *g;
                    for _ in 0..16 {
                        x = x.wrapping_mul(6364136223846793005).wrapping_add(1);
                    }
                    *g ^= x & 1;
                    drop(g);
                    let waited = read_tsc() - t0;
                    LOCK_OPS.fetch_add(1, Ordering::Relaxed);
                    LOCK_MAX_WAIT.fetch_max(waited, Ordering::Relaxed);
                }
            }
        })
        .run();
    }

    if overstayer {
        kernel_task(20, 1, None, || {
            while !past_deadline() {
                let t0 = read_tsc();
                {
                    let _guard = disable_preempt();
                    burn_us(10_000);
                }
                OVERSTAYS.fetch_add(1, Ordering::Relaxed);
                OVERSTAY_MAX.fetch_max(read_tsc() - t0, Ordering::Relaxed);
            }
        })
        .run();
    }

    reaper(|| {
        println!(
            "SCHED-RESULT coop lock_ops={} max_lock_wait_cycles={} overstays={} max_overstay_cycles={}",
            LOCK_OPS.load(Ordering::Relaxed),
            LOCK_MAX_WAIT.load(Ordering::Relaxed),
            OVERSTAYS.load(Ordering::Relaxed),
            OVERSTAY_MAX.load(Ordering::Relaxed)
        );
    });
}

// ---------------------------------------------------------------------------
// Scenario 3: fair — how much of the processor the sandbox takes
// ---------------------------------------------------------------------------

fn scenario_fair(tasks: usize, overstayer: bool) {
    for i in 0..tasks as u32 {
        let prio = (i % NR_LEVELS as u32) as u8;
        let vcpu = i % (num_cpus() as u32);
        kernel_task(100 + i, prio, Some(vcpu), || {
            while !past_deadline() {
                burn_us(500);
            }
        })
        .run();
    }

    if overstayer {
        kernel_task(200, 0, Some(0), || {
            while !past_deadline() {
                let _guard = disable_preempt();
                burn_us(10_000);
            }
        })
        .run();
    }

    reaper(move || {
        println!("SCHED-RESULT fair tasks={} overstayer={}", tasks, overstayer);
    });
}

// ---------------------------------------------------------------------------
// Scenario 4: efficient — what a switch and a wake-up cost
// ---------------------------------------------------------------------------

static PING: AtomicU64 = AtomicU64::new(0);
static YIELD_SAMPLES: SpinLock<Vec<u64>> = SpinLock::new(Vec::new());
static WAKE_SAMPLES_LOCAL: SpinLock<Vec<u64>> = SpinLock::new(Vec::new());
static WAKE_SAMPLES_REMOTE: SpinLock<Vec<u64>> = SpinLock::new(Vec::new());
static WAKE_Q: WaitQueue = WaitQueue::new();
static WAKE_READY: AtomicBool = AtomicBool::new(false);
static WAKE_STAMP: AtomicU64 = AtomicU64::new(0);
static PERF_PHASE: AtomicU32 = AtomicU32::new(0);
/// The tenant program's switch-measurement mode (`sched.S`).
const ROLE_PINGPONG: u64 = 2;
/// Where the remote waker sleeps until the local half of (b) is over, so that
/// vCPU 1 is quiet while vCPU 0 is being measured.
static PHASE2_Q: WaitQueue = WaitQueue::new();

const PERF_ROUNDS: usize = 1500;

fn percentiles(name: &str, samples: &mut Vec<u64>) {
    if samples.is_empty() {
        println!("SCHED-PERF {} n=0", name);
        return;
    }
    samples.sort_unstable();
    let n = samples.len();
    let median = samples[n / 2];
    let p99 = samples[(n * 99) / 100];
    println!(
        "SCHED-PERF {} n={} median={} p99={} min={}",
        name, n, median, p99, samples[0]
    );
}

fn scenario_perf() {
    let program = include_bytes!("../sched");

    // (a) two kernel tasks yielding to each other on one virtual CPU.
    kernel_task(30, 1, Some(0), || {
        let mut n = 0usize;
        while n < PERF_ROUNDS {
            let t0 = read_tsc();
            Task::yield_now();
            let dt = read_tsc() - t0;
            if PING.load(Ordering::Relaxed) > 0 {
                YIELD_SAMPLES.disable_irq().lock().push(dt);
                n += 1;
            }
        }
        PERF_PHASE.store(1, Ordering::Release);
    })
    .run();
    kernel_task(31, 1, Some(0), || {
        while PERF_PHASE.load(Ordering::Acquire) == 0 {
            PING.fetch_add(1, Ordering::Relaxed);
            Task::yield_now();
        }
    })
    .run();

    // (b) wake-up-to-run latency, on the same virtual CPU and across. The wakers
    //     are at the same level as the yield pair, so they wait for it to finish
    //     rather than share its round robin, which would make its round trip mean
    //     something else.
    kernel_task(32, 0, Some(0), || {
        let mut n = 0usize;
        while n < 2 * PERF_ROUNDS && !past_deadline() {
            WAKE_Q.wait_until(|| {
                if WAKE_READY.swap(false, Ordering::Acquire) {
                    Some(())
                } else if past_deadline() {
                    Some(())
                } else {
                    None
                }
            });
            let stamp = WAKE_STAMP.load(Ordering::Acquire);
            if stamp != 0 {
                let dt = read_tsc() - stamp;
                if PERF_PHASE.load(Ordering::Relaxed) >= 2 {
                    WAKE_SAMPLES_REMOTE.disable_irq().lock().push(dt);
                } else {
                    WAKE_SAMPLES_LOCAL.disable_irq().lock().push(dt);
                }
                n += 1;
            }
        }
    })
    .run();

    // The waker: first from the same virtual CPU, then from the other one.
    kernel_task(33, 1, Some(0), || {
        while PERF_PHASE.load(Ordering::Acquire) == 0 && !past_deadline() {
            Task::yield_now();
        }
        for _ in 0..PERF_ROUNDS {
            if past_deadline() {
                break;
            }
            WAKE_STAMP.store(read_tsc(), Ordering::Release);
            WAKE_READY.store(true, Ordering::Release);
            WAKE_Q.wake_all();
            Task::yield_now();
        }
        PERF_PHASE.store(2, Ordering::Release);
        WAKE_Q.wake_all();
        PHASE2_Q.wake_all();
    })
    .run();
    // (c), below, runs on vCPU 1 too, at level 0, where it would keep this
    // level-1 waker from ever running; so the waker starts (c) when it is done.
    let program_c = program;
    kernel_task(34, 1, Some(1), move || {
        PHASE2_Q.wait_until(|| (PERF_PHASE.load(Ordering::Acquire) >= 2 || past_deadline()).then_some(()));
        for _ in 0..PERF_ROUNDS {
            if past_deadline() {
                break;
            }
            WAKE_STAMP.store(read_tsc(), Ordering::Release);
            WAKE_READY.store(true, Ordering::Release);
            WAKE_Q.wake_all();
            burn_us(20);
        }
        PERF_PHASE.store(3, Ordering::Release);

        // (c) two tenant threads of two different address spaces, alternating
        //     on virtual CPU 1 through a yield system call.
        let vm_a = new_vm_space(program_c);
        let vm_b = new_vm_space(program_c);
        user_task(40, 0, Some(1), vm_a, ROLE_PINGPONG, u64::MAX).run();
        user_task(41, 0, Some(1), vm_b, ROLE_PINGPONG, u64::MAX).run();
    })
    .run();

    reaper(move || {
        percentiles(
            "kernelet_yield_roundtrip_cycles",
            &mut YIELD_SAMPLES.disable_irq().lock(),
        );
        percentiles(
            "kernelet_wake_same_vcpu_cycles",
            &mut WAKE_SAMPLES_LOCAL.disable_irq().lock(),
        );
        percentiles(
            "kernelet_wake_other_vcpu_cycles",
            &mut WAKE_SAMPLES_REMOTE.disable_irq().lock(),
        );
        percentiles(
            "kernelet_user_switch_other_mm_cycles",
            &mut USER_SWITCH_SAMPLES.disable_irq().lock(),
        );
    });
}

// ---------------------------------------------------------------------------
// Scenario 5: the floating-point swap
// ---------------------------------------------------------------------------

fn scenario_fpu() {
    let program = include_bytes!("../sched");
    let vm_a = new_vm_space(program);
    let vm_b = new_vm_space(program);

    // Two tenant threads on the *same* virtual CPU, in two different address
    // spaces, each keeping four distinct values in xmm0..xmm3 across every trip
    // through the kernel. The kernel proper swaps their FpuContexts around the
    // task switch; if it did not, one would see the other's values.
    user_task(50, 1, Some(0), vm_a, 0x1122_3344_5566_7788, u64::MAX).run();
    user_task(51, 1, Some(0), vm_b, 0x99aa_bbcc_ddee_ff00, u64::MAX).run();

    reaper(|| {
        let checkins = FPU_CHECKINS.load(Ordering::Relaxed);
        if FPU_FAILED.load(Ordering::Relaxed) {
            println!("SCHED-RESULT fpu FAILED checkins={}", checkins);
        } else {
            println!("SCHED-RESULT fpu OK checkins={}", checkins);
        }
    });
}

// ---------------------------------------------------------------------------
// The reaper: the last task standing
// ---------------------------------------------------------------------------

/// Runs at the least urgent level, so it only gets the processor when every
/// other task of the scenario has finished. Then it reports and powers off.
fn reaper<F>(report: F)
where
    F: FnOnce() + Send + 'static,
{
    kernel_task(999, (NR_LEVELS - 1) as u8, Some(0), move || {
        while LIVE.load(Ordering::Relaxed) > 1 {
            if now_ms() > DEADLINE_MS.load(Ordering::Relaxed) + 4000 {
                println!("SCHED: the reaper gave up waiting; {} task(s) still live",
                         LIVE.load(Ordering::Relaxed) - 1);
                break;
            }
            Task::yield_now();
        }
        STOP.store(true, Ordering::Relaxed);
        println!("SCHED-ELAPSED {}", now_ms());
        report();
        println!("SCHED-DONE");
        poweroff(ExitCode::Success);
    })
    .run();

    // The bootstrap context has nothing more to do: fall into the task context,
    // exactly as returning from `#[ostd::main]` does on bare metal.
    let _ = Duration::from_millis(0);
}
