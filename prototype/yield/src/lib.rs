// SPDX-License-Identifier: MPL-2.0

//! The yield kernel: a kernel proper that computes, in safe Rust, for several
//! seconds inside one OSTD task, without a single system call, allocation or
//! other voluntary preemption point.
//!
//! On a Linux that preempts kernel code that is all it takes to be scheduled
//! away. On a Linux that does not — `preempt=none`, `preempt=voluntary`, or a
//! kernel built without `CONFIG_PREEMPTION` — nothing in this computation will
//! ever give the CPU back, and whatever else is pinned to that CPU starves. The
//! endovisor's watch timer is what fixes that, and this kernel is how the fix
//! is measured.
//!
//! The computation is eight parallel xorshift64 lanes folded into one LCG
//! accumulator. Ten live `u64`s keep most of the general registers busy, which
//! is the point: the yield stub has to restore all of them, and the flags, or the
//! checksum will come out wrong. The same computation is done in user space by
//! the runtime, so the answer is checked against an independent implementation
//! as well as against the run with the tick turned off.

#![no_std]
#![deny(unsafe_code)]

extern crate alloc;

use align_ext::AlignExt;

use alloc::sync::Arc;

use ostd::arch::cpu::context::UserContext;
use ostd::mm::{
    CachePolicy, FrameAllocOptions, PageFlags, PageProperty, Vaddr, VmIo, VmSpace, PAGE_SIZE,
};
use ostd::power::{poweroff, ExitCode};
use ostd::prelude::*;
use ostd::task::{disable_preempt, Task, TaskOptions};
use ostd::user::{DummyUserHooks, ReturnReason, UserMode};

const MAP_ADDR: Vaddr = 0x0040_0000;
const ENTRY_POINT: Vaddr = 0x0040_1000;

/// How many rounds of the eight-lane mixer to run. Tuned so that the whole thing
/// takes a few seconds on the prototype's QEMU guest.
const ROUNDS: u64 = 800_000_000;

#[ostd::main]
pub fn main() {
    let program_binary = include_bytes!("../yield");
    let vm_space = Arc::new(create_vm_space(program_binary));
    vm_space.activate();
    let user_task = create_user_task(vm_space);
    user_task.run();
}

fn create_vm_space(program: &[u8]) -> VmSpace {
    let nbytes = program.len().align_up(PAGE_SIZE);
    let user_pages = {
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
    let map_prop = PageProperty::new_user(PageFlags::RX, CachePolicy::Writeback);
    for frame in user_pages {
        cursor.map(frame.into(), map_prop);
    }
    drop(cursor);
    vm_space
}

fn create_user_task(vm_space: Arc<VmSpace>) -> Arc<Task> {
    fn user_task() {
        let mut user_mode = {
            let user_ctx = create_user_context();
            UserMode::new(user_ctx)
        };

        loop {
            let return_reason = user_mode.execute(&DummyUserHooks);
            let user_context = user_mode.context_mut();
            match return_reason {
                ReturnReason::UserSyscall => handle_syscall(user_context),
                ReturnReason::UserException => {
                    println!("yield: unexpected exception, giving up");
                    poweroff(ExitCode::Failure);
                }
                ReturnReason::KernelEvent => (),
            }
        }
    }

    Arc::new(TaskOptions::new(user_task).data(vm_space).build().unwrap())
}

fn create_user_context() -> UserContext {
    let mut user_ctx = UserContext::default();
    user_ctx.set_rip(ENTRY_POINT);
    user_ctx
}

/// Eight xorshift64 lanes folded into one LCG accumulator.
///
/// Every operation is explicitly wrapping, so the result is the same on any
/// machine and the same whatever the host does to the registers in between.
fn mix(rounds: u64) -> u64 {
    const MUL: u64 = 0x5851_f42d_4c95_7f2d;

    let mut s0: u64 = 0x1234_5678_9abc_def0;
    let mut s1: u64 = 0x0fed_cba9_8765_4321;
    let mut s2: u64 = 0xdead_beef_cafe_babe;
    let mut s3: u64 = 0x0123_4567_89ab_cdef;
    let mut s4: u64 = 0xa5a5_5a5a_3c3c_c3c3;
    let mut s5: u64 = 0x1111_2222_3333_4444;
    let mut s6: u64 = 0xffff_0000_ffff_0000;
    let mut s7: u64 = 0x0f1e_2d3c_4b5a_6978;
    let mut acc: u64 = 0;

    let mut i: u64 = 0;
    while i < rounds {
        s0 ^= s0 << 13;
        s0 ^= s0 >> 7;
        s0 ^= s0 << 17;
        s1 ^= s1 << 13;
        s1 ^= s1 >> 7;
        s1 ^= s1 << 17;
        s2 ^= s2 << 13;
        s2 ^= s2 >> 7;
        s2 ^= s2 << 17;
        s3 ^= s3 << 13;
        s3 ^= s3 >> 7;
        s3 ^= s3 << 17;
        s4 ^= s4 << 13;
        s4 ^= s4 >> 7;
        s4 ^= s4 << 17;
        s5 ^= s5 << 13;
        s5 ^= s5 >> 7;
        s5 ^= s5 << 17;
        s6 ^= s6 << 13;
        s6 ^= s6 >> 7;
        s6 ^= s6 << 17;
        s7 ^= s7 << 13;
        s7 ^= s7 >> 7;
        s7 ^= s7 << 17;
        acc = acc
            .wrapping_mul(MUL)
            .wrapping_add(s0 ^ s1 ^ s2 ^ s3 ^ s4 ^ s5 ^ s6 ^ s7);
        i = i.wrapping_add(1);
    }

    acc ^ s0 ^ s1 ^ s2 ^ s3 ^ s4 ^ s5 ^ s6 ^ s7
}

fn handle_syscall(user_context: &mut UserContext) {
    const SYS_EXIT: usize = 60;
    /// The yield kernel's own call: compute for a long time and say what came out.
    const SYS_COMPUTE: usize = 2000;

    match user_context.rax() {
        SYS_COMPUTE => {
            println!(
                "yield: computing {} rounds inside the kernelet, no preemption point",
                ROUNDS
            );
            let sum = mix(ROUNDS);
            println!("yield: checksum {:#018x} after {} rounds", sum, ROUNDS);
            user_context.set_rax(0);
        }
        SYS_EXIT => poweroff(ExitCode::Success),
        other => {
            println!("yield: unimplemented syscall {}, giving up", other);
            poweroff(ExitCode::Failure);
        }
    }
}
