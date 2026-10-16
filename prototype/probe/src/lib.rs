// SPDX-License-Identifier: MPL-2.0

//! The probe kernel: a kernel proper in the style of Asterinas's 100-line Hello
//! World kernel, written against the same OSTD-shaped API, that exercises the
//! three mechanisms the 100-line kernel never reaches.
//!
//! 1. **Demand paging.** Only the program's text is mapped before the user task
//!    starts. The program stores to an unmapped page; the kernel gets a
//!    [`ReturnReason::UserException`] carrying a page-fault [`CpuException`] with
//!    the faulting address, maps a fresh frame there with a cursor, and returns to
//!    user mode, where the store is retried. The program then reads back what it
//!    wrote and reports it with a `write` system call.
//! 2. **A non-page-fault exception.** The program executes `ud2`. The kernel gets
//!    [`CpuException::InvalidOpcode`], logs it, and steps over the two bytes.
//! 3. **Eviction.** The program makes a system call whose handler never returns.
//!    The only way the host gets that CPU back is to evict the kernelet.

#![no_std]
#![deny(unsafe_code)]

extern crate alloc;

use align_ext::AlignExt;
use core::str;

use alloc::sync::Arc;
use alloc::vec;

use ostd::arch::cpu::context::{CpuException, UserContext};
use ostd::mm::{
    CachePolicy, FallibleVmRead, FrameAllocOptions, PageFlags, PageProperty, Vaddr, VmIo, VmSpace,
    VmWriter, PAGE_SIZE,
};
use ostd::power::{poweroff, ExitCode};
use ostd::prelude::*;
use ostd::task::{disable_preempt, Task, TaskOptions};
use ostd::user::{DummyUserHooks, ReturnReason, UserMode};

/// Where the program image is mapped, and where its entry point lands.
const MAP_ADDR: Vaddr = 0x0040_0000;
const ENTRY_POINT: Vaddr = 0x0040_1000;

#[ostd::main]
pub fn main() {
    let program_binary = include_bytes!("../probe");
    let vm_space = Arc::new(create_vm_space(program_binary));
    vm_space.activate();
    let user_task = create_user_task(vm_space);
    user_task.run();
}

/// Maps the program's text, and nothing else: no data page, no stack.
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

    println!(
        "probe: mapped {} text page(s) at {:#x}; no data page and no stack",
        nbytes / PAGE_SIZE, MAP_ADDR
    );
    vm_space
}

/// Maps one fresh, zeroed, read-write page over the address that faulted.
fn map_on_demand(vm_space: &VmSpace, addr: Vaddr) {
    let va = addr.align_down(PAGE_SIZE);
    let frame = FrameAllocOptions::new().alloc_frame().unwrap();
    let preempt_guard = disable_preempt();
    let mut cursor = vm_space
        .cursor_mut(&preempt_guard, &(va..va + PAGE_SIZE))
        .unwrap();
    cursor.map(
        frame.into(),
        PageProperty::new_user(PageFlags::RW, CachePolicy::Writeback),
    );
}

fn create_user_task(vm_space: Arc<VmSpace>) -> Arc<Task> {
    fn user_task() {
        let current = Task::current().unwrap();
        let vm_space = current.data().downcast_ref::<Arc<VmSpace>>().unwrap();
        let mut user_mode = {
            let user_ctx = create_user_context();
            UserMode::new(user_ctx)
        };

        loop {
            let return_reason = user_mode.execute(&DummyUserHooks);
            let user_context = user_mode.context_mut();
            match return_reason {
                ReturnReason::UserSyscall => handle_syscall(user_context, vm_space),
                ReturnReason::UserException => handle_exception(user_context, vm_space),
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

fn handle_exception(user_context: &mut UserContext, vm_space: &VmSpace) {
    match user_context.take_exception() {
        Some(CpuException::PageFault(info)) => {
            println!(
                "probe: page fault at {:#x} (error code {:#x}), mapping a fresh frame",
                info.addr,
                info.error_code.bits()
            );
            map_on_demand(vm_space, info.addr);
        }
        Some(CpuException::InvalidOpcode) => {
            let rip = user_context.rip();
            println!(
                "probe: illegal instruction at {:#x} (trap 6), stepping over two bytes",
                rip
            );
            user_context.set_rip(rip + 2);
        }
        other => {
            println!("probe: unexpected exception {:?}, giving up", other);
            poweroff(ExitCode::Failure);
        }
    }
}

fn handle_syscall(user_context: &mut UserContext, vm_space: &VmSpace) {
    const SYS_WRITE: usize = 1;
    const SYS_EXIT: usize = 60;
    /// Not a Linux system call number: the probe's own, whose handler never
    /// returns, so that the host has to take the CPU back by force.
    const SYS_SPIN: usize = 1000;

    match user_context.rax() {
        SYS_WRITE => {
            let (_, buf_addr, buf_len) = (
                user_context.rdi(),
                user_context.rsi(),
                user_context.rdx(),
            );
            let buf = {
                let mut buf = vec![0u8; buf_len];
                let mut reader = vm_space.reader(buf_addr, buf_len).unwrap();
                reader
                    .read_fallible(&mut VmWriter::from(&mut buf as &mut [u8]))
                    .unwrap();
                buf
            };
            println!(
                "probe: demand paging: read back \"{}\" from {:#x}",
                str::from_utf8(&buf).unwrap(),
                buf_addr
            );
            user_context.set_rax(buf_len);
        }
        SYS_SPIN => {
            println!("probe: spinning inside the kernelet at depth 0; only eviction can stop me");
            loop {
                core::hint::spin_loop();
            }
        }
        SYS_EXIT => poweroff(ExitCode::Success),
        other => {
            println!("probe: unimplemented syscall {}, giving up", other);
            poweroff(ExitCode::Failure);
        }
    }
}
