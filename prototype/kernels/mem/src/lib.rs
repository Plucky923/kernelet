// SPDX-License-Identifier: MPL-2.0

//! The mem kernel: a kernel proper that exercises vOSTD's `VmSpace`, a tenant
//! address space that is a Linux address space, and measures what it costs.
//!
//! Safe Rust against the OSTD-shaped API, like the other kernels here. What it
//! reads beyond that API comes from `ostd::klet`, the prototype's
//! instrumentation: counter deltas around each test (Linux faults counted in
//! the endovisor's fault handler, service calls, range-lock waits, grace
//! periods) and the one test hook, which makes `vm_map` sleep in the host. One
//! image serves every scenario; the sandbox's command line picks one with
//! `mode=`:
//!
//! - `func`: mapped pages need no Linux fault (E2), one tenant fault maps a
//!   whole fault-around window (E2), a protection change leaves the entries
//!   present (E3), a map under a preemption guard is legal because the service
//!   lifts the mirror (E4), and a page without read permission goes through
//!   the withheld set and back (E10);
//! - `r2`: a sleeping service called under a kernelet spin lock ends the
//!   kernelet by vOSTD's own assertion (E5);
//! - `pressure`: the entries survive Linux's reclaim (E7);
//! - `conc`, two virtual CPUs: lockless copies against concurrent unmaps, a
//!   contended cursor, and a process that exits under a copy (E8, E11);
//! - `kill`: one carrier of a two-thread process killed from outside while the
//!   other thread keeps faulting in the same space (E11);
//! - `killidle` and `killspin`, two virtual CPUs: vCPU 1's carrier killed from
//!   outside while it is asleep in `vcpu_idle` with nothing to run, or while it
//!   runs a kernel task that loops in kernelet code and calls no service;
//!   either kill must end the sandbox, which vCPU 0's tenant would otherwise
//!   outlive;
//! - `perf`: the costs of first touch, map, protect, copies, fork and munmap
//!   (E6, E9).
//!
//! The E-numbers are the names the tests go by in the Makefile and the logs.
//!
//! Where the kernel proper does what the tree's kernel proper does, it does it
//! the same way: fault-around maps the 64 KiB window under one cursor
//! (`vm_mapping.rs:641-716`), fork is the tree's `cow_copy_pt` (child's cursor
//! first, then the parent's; one `protect_next` and one child `map` per page;
//! one `for_all` flush at the end), protection changes are `protect_next` loops
//! followed by one flush.

#![no_std]
#![deny(unsafe_code)]

extern crate alloc;

use alloc::{boxed::Box, sync::Arc, vec, vec::Vec};
use core::{
    ops::Range,
    sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering},
};

use align_ext::AlignExt;
use ostd::{
    arch::{
        cpu::context::{CpuException, UserContext},
        read_tsc,
    },
    boot::{boot_info, smp::register_ap_entry},
    cpu::{num_cpus, CpuId, PinCurrentCpu},
    klet::{self, MemStats},
    mm::{
        tlb::TlbFlushOp, CachePolicy, CursorMut, FallibleVmRead, FallibleVmWrite,
        FrameAllocOptions, HasPaddr, PageFlags, PageProperty, UFrame, Vaddr, VmIo, VmQueriedItem,
        VmReader, VmSpace, VmWriter, PAGE_SIZE,
    },
    power::{poweroff, ExitCode},
    prelude::*,
    sync::SpinLock,
    task::{
        disable_preempt,
        scheduler::{
            enable_preemption_on_cpu, info::CommonSchedInfo, inject_scheduler, EnqueueFlags,
            LocalRunQueue, Scheduler, UpdateFlags,
        },
        Task, TaskOptions,
    },
    user::{DummyUserHooks, ReturnReason, UserContextApi, UserMode},
};

// ---------------------------------------------------------------------------
// Layout of the tenant's address space
// ---------------------------------------------------------------------------

const TEXT: Vaddr = 0x0040_0000;
const ENTRY: Vaddr = 0x0040_1000;
const RESULTS: Vaddr = 0x1000_0000;
const RESULT_PAGES: usize = 2;
const REGION_A: Vaddr = 0x2000_0000;
const REGION_F: Vaddr = 0x3000_0000;
const REGION_P: Vaddr = 0x4000_0000;
const REGION_Q: Vaddr = 0x5000_0000;
const REGION_W: Vaddr = 0x7000_0000;
const REGION_BIG: Vaddr = 0x1_0000_0000;

const SYS_REPORT: usize = 3100;
const SYS_CHECKPOINT: usize = 3101;
const SYS_REWIND: usize = 3102;

const CMD_TOUCH_READ: u64 = 1;
const CMD_TOUCH_WRITE: u64 = 2;
const CMD_CHECK: u64 = 3;
const CMD_SPIN: u64 = 4;
const CMD_READ_ONE: u64 = 5;
const CMD_WRITE_ONE: u64 = 6;
const CMD_COUNT: u64 = 7;

/// The rewind check's tally (E11, `make mem-kill`): checkpoints the tenant
/// made, and how many of them found its register and memory counts apart.
static CHECKPOINTS: AtomicU64 = AtomicU64::new(0);
static REWINDS: AtomicU64 = AtomicU64::new(0);

const SIGNAL_MARKER: usize = 0x5160_5160;

fn rw() -> PageProperty {
    PageProperty::new_user(PageFlags::RW, CachePolicy::Writeback)
}

// ---------------------------------------------------------------------------
// The command line
// ---------------------------------------------------------------------------

fn arg(key: &str) -> Option<&'static str> {
    let line: &'static str = &boot_info().kernel_cmdline;
    line.split_whitespace()
        .find_map(|t| t.strip_prefix(key).and_then(|r| r.strip_prefix('=')))
}

fn arg_u64(key: &str, default: u64) -> u64 {
    arg(key).and_then(|v| v.parse().ok()).unwrap_or(default)
}

// ---------------------------------------------------------------------------
// A pinned FIFO scheduler, which counts task switches per virtual CPU
// ---------------------------------------------------------------------------

struct TaskInfo {
    pin: Option<u32>,
}

static SWITCHES: [AtomicU64; 8] = [const { AtomicU64::new(0) }; 8];

fn switches(v: usize) -> u64 {
    SWITCHES[v].load(Ordering::Relaxed)
}

struct PinScheduler {
    rq: Vec<SpinLock<PinRunQueue>>,
}

struct PinRunQueue {
    vcpu: usize,
    queue: Vec<Arc<Task>>,
    current: Option<Arc<Task>>,
    slice: u32,
}

impl Scheduler<Task> for PinScheduler {
    fn enqueue(&self, runnable: Arc<Task>, flags: EnqueueFlags) -> Option<CpuId> {
        let wanted = match runnable.data().downcast_ref::<TaskInfo>().and_then(|i| i.pin) {
            Some(v) => CpuId::new(v.min(num_cpus() as u32 - 1)),
            None => CpuId::current_racy(),
        };
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
        let idle = rq.current.is_none();
        rq.queue.push(runnable);
        drop(rq);
        if idle && target != CpuId::current_racy() {
            Some(target)
        } else {
            None
        }
    }

    fn local_rq_with(&self, f: &mut dyn FnMut(&dyn LocalRunQueue<Task>)) {
        let guard = disable_preempt();
        let rq = self.rq[guard.current_cpu().as_usize()].disable_irq().lock();
        f(&*rq);
    }

    fn mut_local_rq_with(&self, f: &mut dyn FnMut(&mut dyn LocalRunQueue<Task>)) {
        let guard = disable_preempt();
        let mut rq = self.rq[guard.current_cpu().as_usize()].disable_irq().lock();
        f(&mut *rq);
    }
}

impl LocalRunQueue<Task> for PinRunQueue {
    fn current(&self) -> Option<&Arc<Task>> {
        self.current.as_ref()
    }

    fn update_current(&mut self, flags: UpdateFlags) -> bool {
        match flags {
            UpdateFlags::Tick => {
                if self.current.is_none() {
                    return !self.queue.is_empty();
                }
                if self.slice > 0 {
                    self.slice -= 1;
                }
                self.slice == 0 && !self.queue.is_empty()
            }
            _ => !self.queue.is_empty(),
        }
    }

    fn try_pick_next(&mut self) -> Option<&Arc<Task>> {
        if self.queue.is_empty() {
            return None;
        }
        let next = self.queue.remove(0);
        if let Some(prev) = self.current.replace(next) {
            self.queue.push(prev);
        }
        self.slice = 5;
        SWITCHES[self.vcpu].fetch_add(1, Ordering::Relaxed);
        self.current.as_ref()
    }

    fn dequeue_current(&mut self) -> Option<Arc<Task>> {
        self.current.take().inspect(|t| t.cpu().set_to_none())
    }
}

fn spawn<F: FnOnce() + Send + 'static>(pin: u32, f: F) {
    let task = TaskOptions::new(f)
        .data(TaskInfo { pin: Some(pin) })
        .build()
        .unwrap();
    Arc::new(task).run();
}

// ---------------------------------------------------------------------------
// Statistics
// ---------------------------------------------------------------------------

fn report(name: &str, samples: &mut [u64]) {
    if samples.is_empty() {
        println!("MEM-PERF {} n=0", name);
        return;
    }
    samples.sort_unstable();
    let n = samples.len();
    let med = samples[n / 2];
    let p99 = samples[((n * 99) / 100).min(n - 1)];
    println!(
        "MEM-PERF {} n={} median={} p99={} min={} max={}",
        name, n, med, p99, samples[0], samples[n - 1]
    );
}

fn stats() -> MemStats {
    klet::mem_stats()
}

fn faults(d: &MemStats) -> u64 {
    d.faults + d.mkwrites
}

static FAILED: AtomicBool = AtomicBool::new(false);

fn expect(name: &str, ok: bool, detail: core::fmt::Arguments) {
    println!("MEM-CHECK {} {} {}", if ok { "ok" } else { "FAIL" }, name, detail);
    if !ok {
        FAILED.store(true, Ordering::Relaxed);
    }
}

// ---------------------------------------------------------------------------
// Frames and cursors
// ---------------------------------------------------------------------------

fn new_frames(n: usize) -> Vec<UFrame> {
    (0..n)
        .map(|_| FrameAllocOptions::new().alloc_frame().unwrap().into())
        .collect()
}

fn map_frames(space: &VmSpace, base: Vaddr, frames: &[UFrame], prop: PageProperty) {
    let guard = disable_preempt();
    let mut c = space
        .cursor_mut(&guard, &(base..base + frames.len() * PAGE_SIZE))
        .unwrap();
    for f in frames {
        c.map(f.clone(), prop);
    }
}

fn unmap_pages(space: &VmSpace, base: Vaddr, n: usize) -> usize {
    let guard = disable_preempt();
    let mut c = space
        .cursor_mut(&guard, &(base..base + n * PAGE_SIZE))
        .unwrap();
    c.unmap(n * PAGE_SIZE)
}

/// `protect_next` over every mapped page of the range, then one flush, which
/// is how the tree's `mprotect` does it.
fn protect_pages(
    space: &VmSpace,
    base: Vaddr,
    n: usize,
    mut op: impl FnMut(&mut PageFlags, &mut CachePolicy),
) -> usize {
    let guard = disable_preempt();
    let end = base + n * PAGE_SIZE;
    let mut c = space.cursor_mut(&guard, &(base..end)).unwrap();
    let mut done = 0;
    while c.protect_next(end - c.virt_addr(), &mut op).is_some() {
        done += 1;
    }
    c.flusher().issue_tlb_flush(TlbFlushOp::for_range(base..end));
    c.flusher().dispatch_tlb_flush();
    c.flusher().sync_tlb_flush();
    done
}

/// Writes `seed + i` at offsets 0, 2048 and 4088 of frame i, as the tenant's
/// touch-write does.
fn fill_frames(frames: &[UFrame], seed: u64) {
    for (i, f) in frames.iter().enumerate() {
        let v = (seed + i as u64).to_le_bytes();
        for off in [0, 2048, 4088] {
            f.write_bytes(off, &v).unwrap();
        }
    }
}

// ---------------------------------------------------------------------------
// The tenant
// ---------------------------------------------------------------------------

/// What the kernel proper does with a page fault of the tenant's.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Policy {
    /// Unexpected: fail.
    Fatal,
    /// Map fresh frames over the 64 KiB window around the fault, under one
    /// cursor, as the tree's fault-around does.
    FaultAround,
    /// A write to a read-only page: make it writable again and flush it.
    MakeWritable,
    /// The kernel proper's own permission check says no: deliver the signal,
    /// which here means stepping over the 3-byte load and marking rax.
    Signal,
}

struct Tenant {
    um: UserMode,
    space: Arc<VmSpace>,
    policy: Policy,
    handled: u64,
    signals: u64,
}

impl Tenant {
    fn new(space: Arc<VmSpace>) -> Self {
        let mut ctx = UserContext::default();
        ctx.set_instruction_pointer(ENTRY);
        Self {
            um: UserMode::new(ctx),
            space,
            policy: Policy::Fatal,
            handled: 0,
            signals: 0,
        }
    }

    fn run(&mut self, cmd: u64, base: Vaddr, n: usize, arg: u64, results: Vaddr) -> u64 {
        {
            let ctx = self.um.context_mut();
            ctx.set_rdi(cmd as usize);
            ctx.set_rsi(base);
            ctx.set_rdx(n);
            ctx.set_r8(arg as usize);
            ctx.set_r9(results);
        }
        loop {
            self.space.activate();
            match self.um.execute(&DummyUserHooks) {
                ReturnReason::UserSyscall => {
                    let ctx = self.um.context_mut();
                    if ctx.rax() == SYS_REPORT {
                        ctx.set_rax(0);
                        return ctx.rdi() as u64;
                    }
                    if ctx.rax() == SYS_CHECKPOINT {
                        ctx.set_rax(0);
                        let n = CHECKPOINTS.fetch_add(1, Ordering::Relaxed) + 1;
                        if n % 500 == 0 {
                            println!(
                                "MEM-REWIND checkpoints={} rewinds={}",
                                n,
                                REWINDS.load(Ordering::Relaxed)
                            );
                        }
                        continue;
                    }
                    if ctx.rax() == SYS_REWIND {
                        let (reg, mem) = (ctx.rdi(), ctx.rsi());
                        ctx.set_rax(0);
                        REWINDS.fetch_add(1, Ordering::Relaxed);
                        expect(
                            "E11 rewind: the tenant's register count kept up with its memory count",
                            false,
                            format_args!("(register {}, memory {}: its registers were put back)", reg, mem),
                        );
                        continue;
                    }
                    println!("MEM: unexpected system call {}", ctx.rax());
                    poweroff(ExitCode::Failure);
                }
                ReturnReason::UserException => self.on_exception(),
                ReturnReason::KernelEvent => {}
            }
        }
    }

    fn on_exception(&mut self) {
        let ctx = self.um.context_mut();
        let Some(CpuException::PageFault(info)) = ctx.take_exception() else {
            println!("MEM: unexpected exception at {:#x}", ctx.rip());
            poweroff(ExitCode::Failure);
        };
        self.handled += 1;
        let addr = info.addr.align_down(PAGE_SIZE);
        match self.policy {
            Policy::FaultAround => {
                let window = addr.align_down(16 * PAGE_SIZE);
                let guard = disable_preempt();
                let mut c = self
                    .space
                    .cursor_mut(&guard, &(window..window + 16 * PAGE_SIZE))
                    .unwrap();
                for i in 0..16 {
                    let va = window + i * PAGE_SIZE;
                    c.jump(va).unwrap();
                    if c.query().unwrap().1.is_none() {
                        c.jump(va).unwrap();
                        let f: UFrame = FrameAllocOptions::new().alloc_frame().unwrap().into();
                        c.map(f, rw());
                    }
                }
            }
            Policy::MakeWritable => {
                let guard = disable_preempt();
                let mut c = self
                    .space
                    .cursor_mut(&guard, &(addr..addr + PAGE_SIZE))
                    .unwrap();
                c.protect_next(PAGE_SIZE, |f, _| *f |= PageFlags::W);
                c.flusher().issue_tlb_flush(TlbFlushOp::for_single(addr));
                c.flusher().dispatch_tlb_flush();
            }
            Policy::Signal => {
                // The tree's handler queries the slot and finds the mapping
                // without read permission: that is the tenant's SIGSEGV.
                let guard = disable_preempt();
                let mut c = self.space.cursor(&guard, &(addr..addr + PAGE_SIZE)).unwrap();
                let denied = match c.query().unwrap().1 {
                    Some(VmQueriedItem::MappedRam { prop, .. }) => {
                        !prop.flags.contains(PageFlags::R)
                    }
                    _ => false,
                };
                drop(c);
                drop(guard);
                if !denied {
                    println!("MEM: a fault at {:#x} that the policy cannot explain", addr);
                    poweroff(ExitCode::Failure);
                }
                self.signals += 1;
                let ctx = self.um.context_mut();
                ctx.set_rip(ctx.rip() + 3);
                ctx.set_rax(SIGNAL_MARKER);
            }
            Policy::Fatal => {
                let seen = {
                    let guard = disable_preempt();
                    let mut c = self.space.cursor(&guard, &(addr..addr + PAGE_SIZE)).unwrap();
                    match c.query().unwrap().1 {
                        Some(VmQueriedItem::MappedRam { frame, prop }) => {
                            alloc::format!("mapped to {:#x} {:?}", frame.paddr(), prop.flags)
                        }
                        _ => alloc::string::String::from("not mapped"),
                    }
                };
                println!(
                    "MEM: unexpected page fault at {:#x} (error {:#x}); vOSTD's walk of this space: {}",
                    info.addr,
                    info.error_code.bits(),
                    seen
                );
                poweroff(ExitCode::Failure);
            }
        }
    }

    fn results(&self, n: usize) -> Vec<u64> {
        let mut bytes = vec![0u8; n * 8];
        let mut r = self.space.reader(RESULTS, n * 8).unwrap();
        r.read_fallible(&mut VmWriter::from(&mut bytes[..])).unwrap();
        bytes
            .chunks_exact(8)
            .map(|c| u64::from_le_bytes(c.try_into().unwrap()))
            .collect()
    }
}

/// A space with the program and the results pages mapped, and a tenant in it
/// that has run once, so that its text and results pages are warm in the TLB
/// and the caches before anything is counted.
fn new_tenant() -> Tenant {
    let program = include_bytes!("../mem");
    let npages = program.len().align_up(PAGE_SIZE) / PAGE_SIZE;
    let text = new_frames(npages);
    for (i, f) in text.iter().enumerate() {
        let lo = i * PAGE_SIZE;
        let hi = (lo + PAGE_SIZE).min(program.len());
        f.write_bytes(0, &program[lo..hi]).unwrap();
    }
    let space = Arc::new(VmSpace::new());
    map_frames(
        &space,
        TEXT,
        &text,
        PageProperty::new_user(PageFlags::RX, CachePolicy::Writeback),
    );
    map_frames(&space, RESULTS, &new_frames(RESULT_PAGES), rw());
    let mut t = Tenant::new(space);
    t.run(CMD_TOUCH_WRITE, RESULTS, RESULT_PAGES, 0, 0);
    t
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

#[ostd::main]
pub fn main() {
    let rq = (0..num_cpus())
        .map(|v| {
            SpinLock::new(PinRunQueue {
                vcpu: v,
                queue: Vec::new(),
                current: None,
                slice: 5,
            })
        })
        .collect();
    inject_scheduler(Box::leak(Box::new(PinScheduler { rq })) as &dyn Scheduler<Task>);
    register_ap_entry(ap_main);

    let mode = arg("mode").unwrap_or("func");
    println!(
        "MEM-CONF mode={} vcpus={} grant_frames_in_use={}",
        mode,
        num_cpus(),
        stats().frames_in_use
    );
    match mode {
        "func" => spawn(0, || finish(func_main())),
        "r2" => spawn(0, r2_main),
        "perf" => spawn(0, || finish(perf_main())),
        "pressure" => spawn(0, || finish(pressure_main())),
        "conc" => conc_spawn(),
        "kill" => {
            spawn(1, kill_victim);
            spawn(0, kill_survivor);
        }
        "killidle" => spawn(0, || kill_outlive("idle")),
        "killspin" => {
            spawn(1, kill_spinner);
            spawn(0, || kill_outlive("spin"));
        }
        other => {
            println!("MEM: unknown mode {}", other);
            poweroff(ExitCode::Failure);
        }
    }
    enable_preemption_on_cpu();
}

fn ap_main() {
    enable_preemption_on_cpu();
    AP_UP.store(true, Ordering::Release);
}

/// Set once the application processor, vCPU 1, has started.
static AP_UP: AtomicBool = AtomicBool::new(false);

fn finish(_: ()) {
    let failed = FAILED.load(Ordering::Relaxed);
    println!(
        "MEM-DONE {} frames_in_use={}",
        if failed { "FAIL" } else { "ok" },
        stats().frames_in_use
    );
    poweroff(if failed { ExitCode::Failure } else { ExitCode::Success });
}

// ---------------------------------------------------------------------------
// func: E2, E3, E4, E10
// ---------------------------------------------------------------------------

/// The functional tests of tenant memory, in one tenant process.
fn func_main() {
    let mut t = new_tenant();

    // E2a: map 2 MiB eagerly, then the tenant touches every page.
    let frames = new_frames(512);
    map_frames(&t.space, REGION_A, &frames, rw());
    let s0 = stats();
    t.run(CMD_TOUCH_READ, REGION_A, 512, 0, 0);
    let d = stats().since(&s0);
    println!("MEM-RESULT e2-eager pages=512 faults={}", faults(&d));
    expect("E2 eager: zero Linux faults after the maps", faults(&d) == 0,
           format_args!("({} faults for 512 pages)", faults(&d)));
    unmap_pages(&t.space, REGION_A, 512);
    drop(frames);

    // E2b: one tenant fault maps sixteen pages; the tenant touches all sixteen.
    t.policy = Policy::FaultAround;
    let h0 = t.handled;
    let s0 = stats();
    t.run(CMD_TOUCH_READ, REGION_F, 16, 0, 0);
    let d = stats().since(&s0);
    println!(
        "MEM-RESULT e2-faultaround pages=16 faults={} kernel_handled={} maps={}",
        faults(&d), t.handled - h0, d.maps
    );
    expect("E2 fault-around: one Linux fault for sixteen pages", faults(&d) == 1,
           format_args!("({} faults, {} handled by the kernel proper)", faults(&d), t.handled - h0));
    t.policy = Policy::Fatal;
    unmap_pages(&t.space, REGION_F, 16);

    // E3: map, touch, protect read-only, read every page, write one.
    let frames = new_frames(64);
    map_frames(&t.space, REGION_P, &frames, rw());
    t.run(CMD_TOUCH_WRITE, REGION_P, 64, 0x3333, 0);
    let pr = protect_pages(&t.space, REGION_P, 64, |f, _| *f -= PageFlags::W);
    let s0 = stats();
    t.run(CMD_TOUCH_READ, REGION_P, 64, 0, 0);
    let d = stats().since(&s0);
    println!("MEM-RESULT e3-reads protected={} pages=64 faults={}", pr, faults(&d));
    expect("E3: zero faults on the reads after protect", faults(&d) == 0,
           format_args!("({} faults)", faults(&d)));
    t.policy = Policy::MakeWritable;
    let h0 = t.handled;
    let s0 = stats();
    t.run(CMD_WRITE_ONE, REGION_P, 0, 0x4444, 0);
    let d = stats().since(&s0);
    println!(
        "MEM-RESULT e3-write mkwrites={} faults={} reported={} kernel_handled={}",
        d.mkwrites, d.faults, d.reported, t.handled - h0
    );
    expect("E3: exactly one pfn_mkwrite report on the write",
           d.mkwrites == 1 && d.faults == 0 && d.reported == 1 && t.handled - h0 == 1,
           format_args!("(mkwrites {}, faults {}, reported {})", d.mkwrites, d.faults, d.reported));
    t.policy = Policy::Fatal;
    unmap_pages(&t.space, REGION_P, 64);
    drop(frames);

    // E4: map into a fresh 2 MiB region (Linux must allocate a page-table page)
    // inside a disable_preempt() section.
    let f = new_frames(1);
    fill_frames(&f, 0x4040);
    let v = CpuId::current_racy().as_usize();
    let s0 = stats();
    let sw0 = switches(v);
    let sw_in;
    {
        let guard = disable_preempt();
        let mut c = t
            .space
            .cursor_mut(&guard, &(REGION_Q..REGION_Q + PAGE_SIZE))
            .unwrap();
        c.map(f[0].clone(), rw());
        drop(c);
        sw_in = switches(v);
    }
    let d = stats().since(&s0);
    let bad = t.run(CMD_CHECK, REGION_Q, 1, 0x4040, 0);
    println!(
        "MEM-RESULT e4 maps={} lifted={} switches_in_section={} mismatches={}",
        d.maps, d.lifted, sw_in - sw0, bad
    );
    expect("E4: map under a preempt guard, mirror lifted, mapping correct, no kernelet switch",
           d.maps == 1 && d.lifted == 1 && sw_in == sw0 && bad == 0,
           format_args!("(lifted {}, switches {}, mismatches {})", d.lifted, sw_in - sw0, bad));
    unmap_pages(&t.space, REGION_Q, 1);
    drop(f);

    // E10: PROT_NONE and back, through the withheld set.
    let n = 512;
    let frames = new_frames(n);
    map_frames(&t.space, REGION_W, &frames, rw());
    t.run(CMD_TOUCH_WRITE, REGION_W, n, 0x1010, 0);
    let bad0 = t.run(CMD_CHECK, REGION_W, n, 0x1010, 0);
    let s0 = stats();
    let pr = protect_pages(&t.space, REGION_W, n, |f, _| *f -= PageFlags::RWX);
    let d_none = stats().since(&s0);
    t.policy = Policy::Signal;
    let s1 = stats();
    let got = t.run(CMD_READ_ONE, REGION_W + 5 * PAGE_SIZE, 0, 0, 0);
    let d_read = stats().since(&s1);
    t.policy = Policy::Fatal;
    let s2 = stats();
    let pr2 = protect_pages(&t.space, REGION_W, n, |f, _| *f |= PageFlags::R);
    let d_back = stats().since(&s2);
    let s3 = stats();
    let bad1 = t.run(CMD_CHECK, REGION_W, n, 0x1010, 0);
    let d_check = stats().since(&s3);
    println!(
        "MEM-RESULT e10 pages={} before_mismatches={} to_none={} withheld_in={} vm_unmaps={} \
         read_faults={} signals={} marker_ok={} back={} withheld_out={} maps={} after_mismatches={} check_faults={}",
        n, bad0, pr, d_none.withheld_in, d_none.unmaps, faults(&d_read), t.signals,
        got as usize == SIGNAL_MARKER, pr2, d_back.withheld_out, d_back.maps, bad1, faults(&d_check)
    );
    expect(
        "E10: PROT_NONE round trip through the withheld set, contents intact",
        bad0 == 0
            && pr == n
            && d_none.withheld_in == n as u64
            && t.signals == 1
            && got as usize == SIGNAL_MARKER
            && pr2 == n
            && d_back.withheld_out == n as u64
            && bad1 == 0
            && d_none.unmaps == n as u64
            && d_back.maps == n as u64
            && faults(&d_check) == 0,
        format_args!("(signals {}, mismatches {} then {})", t.signals, bad0, bad1),
    );
    unmap_pages(&t.space, REGION_W, n);
    drop(frames);
}

// ---------------------------------------------------------------------------
// r2: E5
// ---------------------------------------------------------------------------

static A_SPIN_LOCK: SpinLock<u32> = SpinLock::new(0);

/// A sleeping service (`vm_map`) called while holding a kernelet spin lock:
/// vOSTD's assertion must end the kernelet before the call crosses.
fn r2_main() {
    let space = VmSpace::new();
    let f = new_frames(1);
    println!("MEM-E5 calling a sleeping service (vm_map) under a kernelet spin lock");
    let held = A_SPIN_LOCK.lock();
    let guard = disable_preempt();
    let mut c = space
        .cursor_mut(&guard, &(REGION_Q..REGION_Q + PAGE_SIZE))
        .unwrap();
    c.map(f[0].clone(), rw());
    drop(c);
    drop(held);
    println!("MEM-E5 FAIL: the map under a spin lock returned");
    poweroff(ExitCode::Failure);
}

// ---------------------------------------------------------------------------
// perf: E6 and E9
// ---------------------------------------------------------------------------

/// The costs, in cycles: first touch of a mapped page, one map, a 2 MiB
/// protect and the reads after it, copies through the walk (E6); and a fork of
/// 64 MiB, the child's reads, and the munmap (E9).
fn perf_main() {
    let rounds = arg_u64("rounds", 8) as usize;
    let mut t = new_tenant();
    let pool = new_frames(512);

    // E6a: first touch of a mapped page.
    let mut touch = Vec::new();
    let mut touch_faults = 0;
    for _ in 0..rounds {
        map_frames(&t.space, REGION_A, &pool, rw());
        let s0 = stats();
        t.run(CMD_TOUCH_READ, REGION_A, 512, 0, RESULTS);
        touch_faults += faults(&stats().since(&s0));
        touch.extend(t.results(512));
        unmap_pages(&t.space, REGION_A, 512);
    }
    report("first_touch", &mut touch);
    println!("MEM-RESULT e6-first-touch faults={} pages={}", touch_faults, rounds * 512);

    // E6b: map per page.
    let mut single = Vec::new();
    let mut single_avg = Vec::new();
    for _ in 0..rounds {
        let t0 = read_tsc();
        {
            let guard = disable_preempt();
            let mut c = t
                .space
                .cursor_mut(&guard, &(REGION_A..REGION_A + 512 * PAGE_SIZE))
                .unwrap();
            for f in &pool {
                let a = read_tsc();
                c.map(f.clone(), rw());
                single.push(read_tsc() - a);
            }
        }
        single_avg.push((read_tsc() - t0) / 512);
        unmap_pages(&t.space, REGION_A, 512);
    }
    report("map_single", &mut single);
    report("map_single_avg", &mut single_avg);

    // E6c: protect 2 MiB, then 512 reads.
    let mut prot = Vec::new();
    let mut reads = Vec::new();
    let mut read_faults = 0;
    for _ in 0..rounds {
        map_frames(&t.space, REGION_A, &pool, rw());
        t.run(CMD_TOUCH_WRITE, REGION_A, 512, 7, 0);
        let t0 = read_tsc();
        protect_pages(&t.space, REGION_A, 512, |f, _| *f -= PageFlags::W);
        prot.push(read_tsc() - t0);
        let s0 = stats();
        t.run(CMD_TOUCH_READ, REGION_A, 512, 0, RESULTS);
        read_faults += faults(&stats().since(&s0));
        reads.extend(t.results(512));
        unmap_pages(&t.space, REGION_A, 512);
    }
    report("protect_2m", &mut prot);
    report("read_after_protect", &mut reads);
    println!("MEM-RESULT e6-protect faults_on_reads={} pages={}", read_faults, rounds * 512);

    // E6d: a copy through the walk.
    map_frames(&t.space, REGION_A, &pool[..1], rw());
    t.space.activate();
    let mut c64 = Vec::new();
    let mut c4k = Vec::new();
    let mut buf = vec![0u8; PAGE_SIZE];
    for _ in 0..(rounds * 1000) {
        let a = read_tsc();
        let mut r = t.space.reader(REGION_A + 64, 64).unwrap();
        r.read_fallible(&mut VmWriter::from(&mut buf[..64])).unwrap();
        c64.push(read_tsc() - a);
        let a = read_tsc();
        let mut r = t.space.reader(REGION_A, PAGE_SIZE).unwrap();
        r.read_fallible(&mut VmWriter::from(&mut buf[..])).unwrap();
        c4k.push(read_tsc() - a);
    }
    report("copy_64", &mut c64);
    report("copy_4k", &mut c4k);
    unmap_pages(&t.space, REGION_A, 1);

    // E9: fork of 64 MiB, the child's reads, and munmap.
    let r9 = arg_u64("rounds9", 3) as usize;
    e9(&mut t, &pool[..256], r9);
}

const BIG_PAGES: usize = 16384; // 64 MiB

/// The tree's `cow_copy_pt` (`fork.rs:81-131` at `ab9a4cfdc`, its doc comment
/// from 74), RAM only.
fn cow_copy_pt(src: &mut CursorMut<'_>, dst: &mut CursorMut<'_>, size: usize) -> usize {
    let start_va = src.virt_addr();
    let end_va = start_va + size;
    let mut remain = size;
    let mut copied = 0;
    let op = |flags: &mut PageFlags, _: &mut CachePolicy| *flags -= PageFlags::W;
    while let Some(mapped_va) = src.find_next(remain) {
        let (va, Some(item)) = src.query().unwrap() else {
            panic!("found a mapped page but the query failed");
        };
        debug_assert_eq!(mapped_va, va.start);
        let VmQueriedItem::MappedRam { frame, mut prop } = item else {
            panic!("device memory in a tenant space");
        };
        let frame = (*frame).clone();
        src.protect_next(end_va - mapped_va, op).unwrap();
        dst.jump(mapped_va).unwrap();
        op(&mut prop.flags, &mut prop.cache);
        dst.map(frame, prop);
        copied += 1;
        remain = end_va - src.virt_addr();
    }
    copied
}

/// The tree's `fork` of a Vmar: per mapping, the child's cursor, then the
/// parent's; one `for_all` flush after the last.
fn fork(parent: &VmSpace, mappings: &[Range<Vaddr>]) -> (Arc<VmSpace>, usize) {
    let child = Arc::new(VmSpace::new());
    let mut copied = 0;
    for (k, range) in mappings.iter().enumerate() {
        let guard = disable_preempt();
        let mut new_c = child.cursor_mut(&guard, range).unwrap();
        let mut cur_c = parent.cursor_mut(&guard, range).unwrap();
        cur_c.jump(range.start).unwrap();
        new_c.jump(range.start).unwrap();
        copied += cow_copy_pt(&mut cur_c, &mut new_c, range.end - range.start);
        if k == mappings.len() - 1 {
            cur_c.flusher().issue_tlb_flush(TlbFlushOp::for_all());
            cur_c.flusher().dispatch_tlb_flush();
            cur_c.flusher().sync_tlb_flush();
        }
    }
    (child, copied)
}

/// Reaches a drain point of the retire list: `VmSpace::new()`'s `vm_create`
/// stub drains it before it crosses, the caller holding no guard. (The new
/// space is dropped at once and is itself retired.)
fn drain_retired(before: u64) {
    drop(VmSpace::new());
    if stats().drained == before {
        println!("MEM: the retire list was not drained");
        FAILED.store(true, Ordering::Relaxed);
    }
}

fn e9(t: &mut Tenant, pool: &[UFrame], rounds: usize) {
    let big = REGION_BIG..REGION_BIG + BIG_PAGES * PAGE_SIZE;
    let mappings = [
        TEXT..TEXT + PAGE_SIZE * 2,
        RESULTS..RESULTS + RESULT_PAGES * PAGE_SIZE,
        big.clone(),
    ];
    let (mut f_t, mut fr_t, mut cr_t, mut pr_t, mut un_t) = (vec![], vec![], vec![], vec![], vec![]);
    for _ in 0..rounds {
        // The parent: 64 MiB over the pool, every page touched before the
        // fork begins.
        {
            let guard = disable_preempt();
            let mut c = t.space.cursor_mut(&guard, &big).unwrap();
            for i in 0..BIG_PAGES {
                c.map(pool[i % pool.len()].clone(), rw());
            }
        }
        t.run(CMD_TOUCH_READ, REGION_BIG, BIG_PAGES, 0, 0);

        let s0 = stats();
        let t0 = read_tsc();
        let (child, copied) = fork(&t.space, &mappings);
        let t1 = read_tsc();
        let d_fork = stats().since(&s0);

        let mut ct = Tenant::new(child.clone());
        let s1 = stats();
        let t2 = read_tsc();
        ct.run(CMD_TOUCH_READ, REGION_BIG, BIG_PAGES, 0, 0);
        let t3 = read_tsc();
        let d_child = stats().since(&s1);

        let s2 = stats();
        let t4 = read_tsc();
        t.run(CMD_TOUCH_READ, REGION_BIG, BIG_PAGES, 0, 0);
        let t5 = read_tsc();
        let d_parent = stats().since(&s2);

        let t6 = read_tsc();
        let n = unmap_pages(&t.space, REGION_BIG, BIG_PAGES);
        let t7 = read_tsc();

        println!(
            "MEM-RESULT e9 copied={} fork_maps={} fork_protects={} fork_flush_alls={} \
             child_read_faults={} parent_reread_faults={} munmapped={}",
            copied, d_fork.maps, d_fork.protects, d_fork.flush_alls,
            faults(&d_child), faults(&d_parent), n
        );
        expect("E9: one for_all flush in the fork", d_fork.flush_alls == 1,
               format_args!("({} flush-alls)", d_fork.flush_alls));
        f_t.push(t1 - t0);
        fr_t.push(t1 - t0 + t3 - t2);
        cr_t.push(t3 - t2);
        pr_t.push(t5 - t4);
        un_t.push(t7 - t6);

        let before = stats().drained;
        drop(ct);
        drop(child);
        t.space.activate();
        drain_retired(before);
    }
    report("fork_64m", &mut f_t);
    report("fork_child_reads_64m", &mut fr_t);
    report("child_reads_64m", &mut cr_t);
    report("parent_rereads_64m", &mut pr_t);
    report("munmap_64m", &mut un_t);
}

// ---------------------------------------------------------------------------
// pressure: E7
// ---------------------------------------------------------------------------

/// 512 mapped pages, then a long wait in user mode while the runtime's hog
/// pushes the guest into swap: Linux's reclaim must leave every entry of the
/// area present and pointing at the frame it was.
fn pressure_main() {
    let mut t = new_tenant();
    let n = 512;
    let frames = new_frames(n);
    map_frames(&t.space, REGION_A, &frames, rw());
    t.run(CMD_TOUCH_WRITE, REGION_A, n, 0x7070, 0);
    let bad0 = t.run(CMD_CHECK, REGION_A, n, 0x7070, 0);
    let wait_ms = arg_u64("wait_ms", 30000);
    println!("E7-MAPPED pages={} mismatches={} waiting {} ms in user mode", n, bad0, wait_ms);
    let s0 = stats();
    t.run(CMD_SPIN, 0, 0, wait_ms * ostd::time::tsc_khz(), 0);
    let d_wait = stats().since(&s0);
    println!("E7-READBACK faults_during_wait={}", faults(&d_wait));

    // Every entry, through the lockless walk: present, and the frame it was.
    let mut present = 0;
    let mut same = 0;
    {
        let guard = disable_preempt();
        let mut c = t
            .space
            .cursor(&guard, &(REGION_A..REGION_A + n * PAGE_SIZE))
            .unwrap();
        for (i, f) in frames.iter().enumerate() {
            c.jump(REGION_A + i * PAGE_SIZE).unwrap();
            if let (_, Some(VmQueriedItem::MappedRam { frame, prop })) = c.query().unwrap() {
                present += 1;
                if frame.paddr() == f.paddr() && prop.flags.contains(PageFlags::RW) {
                    same += 1;
                }
            }
        }
    }
    let s1 = stats();
    let bad1 = t.run(CMD_CHECK, REGION_A, n, 0x7070, 0);
    let d_read = stats().since(&s1);
    println!(
        "MEM-RESULT e7 pages={} present={} same_frame={} read_faults={} mismatches={}",
        n, present, same, faults(&d_read), bad1
    );
    expect(
        "E7: every entry still present after reclaim, contents intact, no fault on the reads",
        present == n && same == n && faults(&d_read) == 0 && bad1 == 0 && bad0 == 0,
        format_args!("(present {}, read faults {}, mismatches {})", present, faults(&d_read), bad1),
    );
    unmap_pages(&t.space, REGION_A, n);
}

// ---------------------------------------------------------------------------
// conc: E8 and E11, two virtual CPUs
// ---------------------------------------------------------------------------

static PHASE: AtomicUsize = AtomicUsize::new(0);
static DONE_B: AtomicUsize = AtomicUsize::new(0);
static HOLD_T: AtomicU64 = AtomicU64::new(0);
static RELEASE_T: AtomicU64 = AtomicU64::new(0);
static STOP: AtomicBool = AtomicBool::new(false);
static SPACE_S: SpinLock<Option<Arc<VmSpace>>> = SpinLock::new(None);
static SPACE_D: SpinLock<Option<Arc<VmSpace>>> = SpinLock::new(None);
static POOL_SIG: SpinLock<Vec<usize>> = SpinLock::new(Vec::new());

const E8_PAGES: usize = 64;

fn sig(paddr: usize, gen: u64) -> u64 {
    ((paddr as u64) << 20) ^ gen ^ 0x5a5a_0000_0000_0000
}

fn fill_sig(f: &UFrame, gen: u64) {
    let v = sig(f.paddr(), gen).to_le_bytes();
    let mut page = [0u8; PAGE_SIZE];
    for w in page.chunks_exact_mut(8) {
        w.copy_from_slice(&v);
    }
    f.write_bytes(0, &page).unwrap();
}

fn spin_ms(ms: u64) {
    let end = read_tsc() + ms * ostd::time::tsc_khz();
    while read_tsc() < end {
        core::hint::spin_loop();
    }
}

fn wait_phase(p: usize) {
    while PHASE.load(Ordering::Acquire) < p {
        core::hint::spin_loop();
    }
}

fn conc_spawn() {
    if num_cpus() < 2 {
        println!("MEM: conc needs two virtual CPUs");
        poweroff(ExitCode::Failure);
    }
    *SPACE_S.lock() = Some(Arc::new(VmSpace::new()));
    *SPACE_D.lock() = Some(Arc::new(VmSpace::new()));
    spawn(0, conc_a);
    spawn(1, conc_b);
}

fn s_space() -> Arc<VmSpace> {
    SPACE_S.lock().clone().unwrap()
}

/// Virtual CPU 0: maps and unmaps in a loop (E8.1), holds a cursor while
/// sleeping in vm_map (E8.2), then exits a process under a copy (E11).
fn conc_a() {
    let dur = arg_u64("dur", 3000);
    let space = s_space();
    space.activate();
    let pool = new_frames(E8_PAGES);
    *POOL_SIG.lock() = pool.iter().map(|f| f.paddr()).collect();
    let mut gen = 1u64;
    for f in &pool {
        fill_sig(f, gen);
    }

    // E8.1
    PHASE.store(1, Ordering::Release);
    let s0 = stats();
    let end = read_tsc() + dur * ostd::time::tsc_khz();
    let mut iters = 0u64;
    while read_tsc() < end {
        map_frames(&space, REGION_A, &pool, rw());
        let n = unmap_pages(&space, REGION_A, E8_PAGES);
        assert_eq!(n, E8_PAGES);
        // "Reuse": the frames get new contents only after the unmap returned,
        // which, because of the grace period, is after every copy that saw
        // them.
        gen += 1;
        for f in &pool {
            fill_sig(f, gen);
        }
        iters += 1;
    }
    STOP.store(true, Ordering::Release);
    while DONE_B.load(Ordering::Acquire) < 1 {
        core::hint::spin_loop();
    }
    let d = stats().since(&s0);
    println!(
        "MEM-RESULT e8-loop iterations={} maps={} unmaps={} grace_periods={} grace_waits={} owner_checks={}",
        iters, d.maps, d.unmaps, d.grace_periods, d.grace_waits, d.owner_checks
    );

    // E8.2: hold a mutable cursor while sleeping in vm_map.
    PHASE.store(2, Ordering::Release);
    {
        let guard = disable_preempt();
        let mut c = space
            .cursor_mut(&guard, &(REGION_Q..REGION_Q + 4 * PAGE_SIZE))
            .unwrap();
        klet::set_map_test_sleep(true);
        HOLD_T.store(read_tsc(), Ordering::Release);
        for f in &pool[..4] {
            c.map(f.clone(), rw());
        }
        klet::set_map_test_sleep(false);
        RELEASE_T.store(read_tsc(), Ordering::Release);
    }
    while DONE_B.load(Ordering::Acquire) < 2 {
        core::hint::spin_loop();
    }
    unmap_pages(&space, REGION_Q, 16);

    // E11: a process exits under a copy into its memory.
    let x = Arc::new(VmSpace::new());
    *SPACE_S.lock() = Some(x.clone());
    x.activate();
    let victims = new_frames(E8_PAGES);
    let victim_paddrs: Vec<usize> = victims.iter().map(|f| f.paddr()).collect();
    map_frames(&x, REGION_A, &victims, rw());
    drop(victims); // the entries hold the only references now
    PHASE.store(3, Ordering::Release);
    while DONE_B.load(Ordering::Acquire) < 3 {
        core::hint::spin_loop(); // B has started copying
    }
    spin_ms(20);
    let s0 = stats();
    let n = unmap_pages(&x, REGION_A, E8_PAGES); // the exit's unmap
    // Reallocate at once: freed frames come straight back.
    let fresh = new_frames(E8_PAGES);
    let reused = fresh.iter().filter(|f| victim_paddrs.contains(&f.paddr())).count();
    for f in &fresh {
        fill_sig(f, 0xa11ce);
    }
    spin_ms(30);
    STOP.store(true, Ordering::Release);
    while DONE_B.load(Ordering::Acquire) < 4 {
        core::hint::spin_loop();
    }
    let mut corrupted = 0;
    let mut page = vec![0u8; PAGE_SIZE];
    let want = |p: usize| sig(p, 0xa11ce);
    for f in &fresh {
        f.read_bytes(0, &mut page).unwrap();
        if page
            .chunks_exact(8)
            .any(|w| u64::from_le_bytes(w.try_into().unwrap()) != want(f.paddr()))
        {
            corrupted += 1;
        }
    }
    let d_unmap = stats().since(&s0);
    // Drop the last reference with interrupts off, as the post-schedule
    // handler would: Drop must neither sleep nor cross.
    let d_space = SPACE_D.lock().clone().unwrap();
    d_space.activate(); // vCPU 0 lets go of x
    *SPACE_S.lock() = None;
    let before = stats().drained;
    let retired0 = stats().retired;
    {
        let irq = ostd::irq::disable_local();
        drop(x);
        drop(irq);
    }
    let deferred = stats().retired - retired0;
    let frames_before_drain = stats().frames_in_use;
    drain_retired(before);
    let reaped = stats().drained - before;
    println!(
        "MEM-RESULT e11 unmapped={} reused_frames={} corrupted={} grace_waits={} retired_in_irq_off={} drained={} frames_before_drain={} frames_after={}",
        n, reused, corrupted, d_unmap.grace_waits, deferred, reaped, frames_before_drain,
        stats().frames_in_use
    );
    drop(fresh);

    // Verdicts, all on vCPU 0.
    let r = E8_RESULT.lock().clone();
    let (ok, torn, absent, bad_frame, copies) = (r[0], r[1], r[2], r[3], r[4]);
    println!(
        "MEM-RESULT e8-reads copies={} whole={} torn={} absent_or_partial={} unknown_frame={}",
        copies, ok, torn, absent, bad_frame
    );
    let (waited, sleeps, cas, sw0, sw1, after_release) = (r[5], r[6], r[7], r[8], r[9], r[10]);
    println!(
        "MEM-RESULT e8-contended waited_us={} wait_sleeps={} cas_retries={} switches_v0={} switches_v1={} acquired_after_release={}",
        waited, sleeps, cas, sw0, sw1, after_release
    );
    expect("E8: no torn read, no unknown frame, copies of both kinds happened",
           torn == 0 && bad_frame == 0 && ok > 0 && absent > 0,
           format_args!("(whole {}, torn {}, absent {})", ok, torn, absent));
    expect("E8: the second cursor slept in vm_wait and got the lock after the release, \
            no spinning, no kernelet task switch",
           sleeps >= 1 && after_release == 1 && cas <= 4 && sw0 == 0 && sw1 == 0,
           format_args!("(slept {} time(s), waited {} us, {} CAS retries)", sleeps, waited, cas));
    expect("E11: no frame released before the grace period; the space retired with interrupts off and drained later",
           corrupted == 0 && n == E8_PAGES && deferred == 1 && reaped >= 1,
           format_args!("(corrupted {}, deferred {}, reaped {})", corrupted, deferred, reaped));
    finish(());
}

static E8_RESULT: SpinLock<[u64; 11]> = SpinLock::new([0; 11]);

// ---------------------------------------------------------------------------
// kill: E11's second half. One carrier of a two-thread process is preempted,
// signalled, stopped and continued, and then killed from outside, while the
// other thread keeps faulting in the same address space; the kill ends the
// whole sandbox. The killed carrier's tenant runs the rewind check meanwhile.
// ---------------------------------------------------------------------------

static X_SPACE: SpinLock<Option<Arc<VmSpace>>> = SpinLock::new(None);

/// vCPU 1: creates the space, so that the carrier that dies is the one that
/// made the address space (the memory controller's owner must not be it: the
/// endovisor makes the root carrier the owner of every space), then runs the
/// rewind check in user mode until it is killed, while the runtime preempts,
/// signals, stops and continues its carrier.
fn kill_victim() {
    let mut t = new_tenant();
    *X_SPACE.lock() = Some(t.space.clone());
    PHASE.store(1, Ordering::Release);
    println!("MEM-KILL-ME vcpu=1");
    t.run(CMD_COUNT, RESULTS, 200_000, 60_000 * ostd::time::tsc_khz(), 0);
    println!("MEM-KILL vcpu 1 was not killed");
    FAILED.store(true, Ordering::Relaxed);
}

/// vCPU 0: a second thread of the same process, demand-faulting in a loop
/// until its sibling's carrier dies, and the sandbox with it. It reports its
/// progress twice a second; it reports nothing else, because the sandbox ends
/// under it.
fn kill_survivor() {
    wait_phase(1);
    let x = X_SPACE.lock().clone().unwrap();
    let mut t = Tenant::new(x);
    t.policy = Policy::FaultAround;
    let dur = arg_u64("dur", 6000);
    let end = read_tsc() + dur * ostd::time::tsc_khz();
    let s0 = stats();
    let mut rounds = 0;
    let mut next_report = read_tsc();
    while read_tsc() < end {
        t.run(CMD_TOUCH_READ, REGION_F, 64, 0, 0);
        unmap_pages(&t.space, REGION_F, 64);
        rounds += 1;
        if read_tsc() >= next_report {
            next_report = read_tsc() + 500 * ostd::time::tsc_khz();
            println!("MEM-KILL survivor rounds={} faults={}", rounds, faults(&stats().since(&s0)));
        }
    }
    // Reached only if the kill never came, or did not end the sandbox.
    let d = stats().since(&s0);
    expect("E11 kill: the kill of vCPU 1's carrier ended the sandbox before this thread finished",
           false,
           format_args!("({} rounds, {} faults)", rounds, faults(&d)));
    finish(());
}

// ---------------------------------------------------------------------------
// killidle, killspin: a kill must end the sandbox wherever the carrier is
// ---------------------------------------------------------------------------

static SPINNING: AtomicBool = AtomicBool::new(false);

/// vCPU 1, in `killspin`: a kernel task that never leaves kernelet code and
/// calls no service, so that only the watch timer can notice a kill.
fn kill_spinner() {
    SPINNING.store(true, Ordering::Release);
    loop {
        core::hint::spin_loop();
    }
}

/// vCPU 0: once vCPU 1 is where the scenario wants it (idle, or spinning),
/// says so for the runtime, which then kills vCPU 1's carrier, and runs its
/// tenant in user mode for `dur` ms in steps of 50 ms. The kill must end the
/// sandbox long before that; reaching the end is the failure.
fn kill_outlive(what: &str) {
    // Not AP_UP for the spinner: vCPU 1 may switch to it from inside
    // `ap_main`, when the guard drop in `enable_preemption_on_cpu` delivers the
    // KICK its spawn raised, and then never come back to finish `ap_main`.
    let ready = if what == "spin" { &SPINNING } else { &AP_UP };
    while !ready.load(Ordering::Acquire) {
        core::hint::spin_loop();
    }
    let mut t = new_tenant();
    let dur = arg_u64("dur", 10_000);
    let end = read_tsc() + dur * ostd::time::tsc_khz();
    println!("MEM-KILL-READY vcpu 1 is {}", if what == "spin" { "spinning in a kernel task" } else { "idle" });
    while read_tsc() < end {
        t.run(CMD_SPIN, 0, 0, 50 * ostd::time::tsc_khz(), 0);
    }
    expect("kill: the kill of vCPU 1's carrier ended the sandbox before vCPU 0's tenant finished",
           false,
           format_args!("(vCPU 1 {})", what));
    finish(());
}

/// Virtual CPU 1: copies out of the space while vCPU 0 maps and unmaps it
/// (E8.1), opens a contended cursor (E8.2), then copies into a space whose
/// process exits (E11).
fn conc_b() {
    let space = s_space();
    space.activate();
    wait_phase(1);
    let pool: Vec<usize> = POOL_SIG.lock().clone();
    let mut buf = vec![0u8; PAGE_SIZE];
    let (mut ok, mut torn, mut absent, mut bad_frame, mut copies) = (0u64, 0u64, 0u64, 0u64, 0u64);
    while !STOP.load(Ordering::Acquire) {
        for i in 0..E8_PAGES {
            let va = REGION_A + i * PAGE_SIZE;
            let mut r = space.reader(va, PAGE_SIZE).unwrap();
            copies += 1;
            match r.read_fallible(&mut VmWriter::from(&mut buf[..])) {
                Ok(_) => {
                    let first = u64::from_le_bytes(buf[..8].try_into().unwrap());
                    let bad_at = buf
                        .chunks_exact(8)
                        .position(|w| u64::from_le_bytes(w.try_into().unwrap()) != first);
                    if let Some(at) = bad_at {
                        torn += 1;
                        if torn <= 4 {
                            let other =
                                u64::from_le_bytes(buf[at * 8..at * 8 + 8].try_into().unwrap());
                            let dec = |w: u64| {
                                let x = w ^ 0x5a5a_0000_0000_0000;
                                (x >> 20, x & 0xfffff)
                            };
                            println!(
                                "MEM-TORN va={:#x} first={:#x} {:?} word {} = {:#x} {:?}",
                                va, first, dec(first), at, other, dec(other)
                            );
                        }
                    } else if !pool.iter().any(|&p| (first ^ 0x5a5a_0000_0000_0000) >> 20 == p as u64) {
                        bad_frame += 1;
                    } else {
                        ok += 1;
                    }
                }
                Err(_) => absent += 1,
            }
        }
    }
    {
        let mut r = E8_RESULT.lock();
        r[0] = ok;
        r[1] = torn;
        r[2] = absent;
        r[3] = bad_frame;
        r[4] = copies;
    }
    STOP.store(false, Ordering::Release);
    DONE_B.store(1, Ordering::Release);

    // E8.2
    wait_phase(2);
    while HOLD_T.load(Ordering::Acquire) == 0 {
        core::hint::spin_loop();
    }
    spin_ms(5); // well inside the holder's first sleeping vm_map
    let s0 = stats();
    let sw0 = switches(0);
    let sw1 = switches(1);
    let f = new_frames(1);
    let t0 = read_tsc();
    {
        let guard = disable_preempt();
        let mut c = space
            .cursor_mut(&guard, &(REGION_Q + 8 * PAGE_SIZE..REGION_Q + 9 * PAGE_SIZE))
            .unwrap();
        let t1 = read_tsc();
        let after = (t1 >= RELEASE_T.load(Ordering::Acquire)
            && RELEASE_T.load(Ordering::Acquire) != 0) as u64;
        c.map(f[0].clone(), rw());
        let d = stats().since(&s0);
        let mut r = E8_RESULT.lock();
        r[5] = (t1 - t0) * 1000 / ostd::time::tsc_khz();
        r[6] = d.wait_sleeps;
        r[7] = d.lock_cas_retries;
        r[8] = switches(0) - sw0;
        r[9] = switches(1) - sw1;
        r[10] = after;
    }
    DONE_B.store(2, Ordering::Release);

    // E11
    wait_phase(3);
    let x = s_space();
    x.activate();
    let pattern = vec![0xb0u8; PAGE_SIZE];
    DONE_B.store(3, Ordering::Release);
    while !STOP.load(Ordering::Acquire) {
        for i in 0..E8_PAGES {
            if let Ok(mut w) = x.writer(REGION_A + i * PAGE_SIZE, PAGE_SIZE) {
                let _ = w.write_fallible(&mut VmReader::from(&pattern[..]));
            }
        }
    }
    drop(x);
    let d_space = SPACE_D.lock().clone().unwrap();
    d_space.activate(); // vCPU 1 lets go of x
    DONE_B.store(4, Ordering::Release);
}
