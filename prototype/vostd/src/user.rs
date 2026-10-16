// SPDX-License-Identifier: MPL-2.0

//! User mode: real OSTD's `UserMode`, its hooks and the reasons it returns.
//! Entering user mode is the `user_run` service, which leaves the kernelet's
//! stack, lets the carrier return to user mode in the address space its
//! virtual CPU has activated, and comes back on the next system call,
//! exception or virtual interrupt (see [`crate::arch::cpu::context`]).

use crate::arch::cpu::context::UserContext;

/// The internal interface that every CPU architecture-specific [`UserContext`]
/// implements.
pub(crate) trait UserContextApiInternal {
    /// Starts executing in the user mode.
    fn execute<T: UserModeHooks>(&mut self, hooks: &T) -> ReturnReason;
}

/// The common interface that every CPU architecture-specific [`UserContext`]
/// implements.
pub trait UserContextApi {
    /// Sets the instruction pointer.
    fn set_instruction_pointer(&mut self, ip: usize);

    /// Gets the instruction pointer.
    fn instruction_pointer(&self) -> usize;

    /// Sets the stack pointer.
    fn set_stack_pointer(&mut self, sp: usize);

    /// Gets the stack pointer.
    fn stack_pointer(&self) -> usize;
}

/// Code execution in the user mode.
pub struct UserMode {
    context: UserContext,
}

impl UserMode {
    /// Creates a new `UserMode`.
    pub fn new(context: UserContext) -> Self {
        Self { context }
    }

    /// Starts executing in the user mode.
    #[track_caller]
    pub fn execute<T: UserModeHooks>(&mut self, hooks: &T) -> ReturnReason {
        self.context.execute(hooks)
    }

    /// Returns an immutable reference to the user-mode CPU context.
    pub fn context(&self) -> &UserContext {
        &self.context
    }

    /// Returns a mutable reference to the user-mode CPU context.
    pub fn context_mut(&mut self) -> &mut UserContext {
        &mut self.context
    }
}

/// A reason as to why the control of the CPU is returned from the user space to
/// the kernel.
#[derive(Debug, Eq, PartialEq)]
pub enum ReturnReason {
    /// A system call is issued by the user space.
    UserSyscall,
    /// A CPU exception is triggered by the user space.
    UserException,
    /// A kernel event is pending.
    KernelEvent,
}

/// Hooks that will be called during [`UserMode::execute`].
pub trait UserModeHooks {
    /// Checks whether a kernel event is pending.
    fn has_kernel_event(&self) -> bool {
        false
    }
}

/// A struct that provides dummy (no-op) user mode hooks.
pub struct DummyUserHooks;

impl UserModeHooks for DummyUserHooks {}
