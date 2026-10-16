// SPDX-License-Identifier: MPL-2.0

//! CPU execution context control.

use crate::{
    arch::trap::RawUserContext,
    mm::Vaddr,
    user::{ReturnReason, UserContextApi, UserContextApiInternal, UserModeHooks},
};

/// x86-64 RFLAGS bits that OSTD sets before entering user mode: the interrupt
/// flag, so that external interrupts are taken, and the ID flag, so that the
/// user program may use `cpuid`.
const RFLAGS_IF: usize = 1 << 9;
const RFLAGS_ID: usize = 1 << 21;

/// Userspace CPU context, including general-purpose registers and exception
/// information.
#[repr(C)]
#[derive(Clone, Debug, Default)]
pub struct UserContext {
    user_context: RawUserContext,
    exception: Option<CpuException>,
}

/// General registers.
///
/// The field order is the image ABI: the endovisor copies these eighteen words
/// to and from Linux's `struct pt_regs`.
#[allow(missing_docs)]
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct GeneralRegs {
    pub rax: usize,
    pub rbx: usize,
    pub rcx: usize,
    pub rdx: usize,
    pub rsi: usize,
    pub rdi: usize,
    pub rbp: usize,
    pub rsp: usize,
    pub r8: usize,
    pub r9: usize,
    pub r10: usize,
    pub r11: usize,
    pub r12: usize,
    pub r13: usize,
    pub r14: usize,
    pub r15: usize,
    pub rip: usize,
    pub rflags: usize,
}

/// Architectural CPU exceptions.
///
/// The same shape as real OSTD's, with the variants this prototype can actually
/// produce. `PageFault` carries [`RawPageFaultInfo`] exactly as it does there;
/// the one difference is where the address comes from. On bare metal OSTD reads
/// CR2 in its own trap handler; here the endovisor has the address from Linux's
/// `struct vm_fault` (or from the signal's `si_addr`) and passes it across the
/// image ABI in `RawUserContext::fault_addr`.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CpuException {
    ///  0 - #DE  Divide-by-zero error.
    DivisionError,
    ///  1 - #DB  Debug.
    Debug,
    ///  3 - #BP  Breakpoint (INT3).
    BreakPoint,
    ///  4 - #OF  Overflow.
    Overflow,
    ///  5 - #BR  Bound-range exceeded.
    BoundRangeExceeded,
    ///  6 - #UD  Invalid or undefined opcode.
    InvalidOpcode,
    ///  7 - #NM  Device not available (FPU/MMX/SSE disabled).
    DeviceNotAvailable,
    /// 13 - #GP  General protection fault.
    GeneralProtectionFault(Option<SelectorErrorCode>),
    /// 14 - #PF  Page fault.
    PageFault(RawPageFaultInfo),
    /// 16 - #MF  x87 floating-point exception.
    X87FloatingPointException,
    /// 17 - #AC  Alignment check.
    AlignmentCheck,
    /// 19 - #XM / #XF  SIMD/FPU floating-point exception.
    SIMDFloatingPointException,
    /// Catch-all for reserved or undefined vector numbers.
    Reserved,
}

impl CpuException {
    pub(crate) fn new(trap_num: usize, error_code: usize, fault_addr: Vaddr) -> Option<Self> {
        let exception = match trap_num {
            0 => Self::DivisionError,
            1 => Self::Debug,
            3 => Self::BreakPoint,
            4 => Self::Overflow,
            5 => Self::BoundRangeExceeded,
            6 => Self::InvalidOpcode,
            7 => Self::DeviceNotAvailable,
            13 => {
                let error_code = if error_code == 0 {
                    None
                } else {
                    Some(SelectorErrorCode(error_code))
                };
                Self::GeneralProtectionFault(error_code)
            }
            14 => Self::PageFault(RawPageFaultInfo {
                error_code: PageFaultErrorCode::from_bits_truncate(error_code),
                addr: fault_addr,
            }),
            16 => Self::X87FloatingPointException,
            17 => Self::AlignmentCheck,
            19 => Self::SIMDFloatingPointException,
            2 | 8..=12 | 15 | 18 | 20..=31 => Self::Reserved,
            _ => return None,
        };

        Some(exception)
    }
}

/// Selector error code.
#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub struct SelectorErrorCode(usize);

/// Architecture-specific data reported with a page-fault exception.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RawPageFaultInfo {
    /// The error code for this page fault.
    pub error_code: PageFaultErrorCode,
    /// The linear (virtual) address that triggered the fault.
    pub addr: Vaddr,
}

/// Page fault error code, following the Intel manual.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct PageFaultErrorCode(usize);

#[allow(dead_code)]
impl PageFaultErrorCode {
    /// 0 if no translation for the linear address.
    pub const PRESENT: Self = Self(1 << 0);
    /// 1 if the access was a write.
    pub const WRITE: Self = Self(1 << 1);
    /// 1 if the access was a user-mode access.
    pub const USER: Self = Self(1 << 2);
    /// 1 if a reserved bit was set.
    pub const RESERVED: Self = Self(1 << 3);
    /// 1 if the access was an instruction fetch.
    pub const INSTRUCTION: Self = Self(1 << 4);
    /// 1 if a protection key disallowed the access.
    pub const PROTECTION: Self = Self(1 << 5);
    /// 1 if the access was a shadow-stack access.
    pub const SHADOW_STACK: Self = Self(1 << 6);

    /// The raw bits.
    pub const fn bits(&self) -> usize {
        self.0
    }

    /// Keeps only the bits this type defines.
    pub const fn from_bits_truncate(bits: usize) -> Self {
        Self(bits & 0x7f)
    }

    /// Whether all the flags in `other` are set.
    pub const fn contains(&self, other: Self) -> bool {
        self.0 & other.0 == other.0
    }
}

impl core::ops::BitOr for PageFaultErrorCode {
    type Output = Self;
    fn bitor(self, rhs: Self) -> Self {
        Self(self.0 | rhs.0)
    }
}

impl UserContext {
    /// Returns a reference to the general registers.
    pub fn general_regs(&self) -> &GeneralRegs {
        &self.user_context.general
    }

    /// Returns a mutable reference to the general registers.
    pub fn general_regs_mut(&mut self) -> &mut GeneralRegs {
        &mut self.user_context.general
    }

    /// Takes the CPU exception out.
    pub fn take_exception(&mut self) -> Option<CpuException> {
        self.exception.take()
    }
}

impl UserContextApiInternal for UserContext {
    fn execute<T: UserModeHooks>(&mut self, hooks: &T) -> ReturnReason {
        self.user_context.general.rflags |= RFLAGS_IF | RFLAGS_ID;

        loop {
            match self.user_context.run() {
                0 => return ReturnReason::UserSyscall,
                1 => {
                    self.exception = CpuException::new(
                        self.user_context.trap_num,
                        self.user_context.error_code,
                        self.user_context.fault_addr,
                    );
                    return ReturnReason::UserException;
                }
                _ => {
                    // The host says there is work for the kernelet. Take the
                    // pending virtual interrupts — but without switching tasks:
                    // the tenant's floating-point registers are live here.
                    crate::vcpu::deliver_no_switch();
                    if hooks.has_kernel_event() {
                        return ReturnReason::KernelEvent;
                    }
                }
            }
        }
    }
}

impl UserContextApi for UserContext {
    fn set_instruction_pointer(&mut self, ip: usize) {
        self.set_rip(ip);
    }

    fn instruction_pointer(&self) -> usize {
        self.rip()
    }

    fn set_stack_pointer(&mut self, sp: usize) {
        self.set_rsp(sp)
    }

    fn stack_pointer(&self) -> usize {
        self.rsp()
    }
}

macro_rules! cpu_context_impl_getter_setter {
    ( $( [ $field: ident, $setter_name: ident] ),*) => {
        impl UserContext {
            $(
                #[doc = concat!("Gets the value of ", stringify!($field))]
                #[inline(always)]
                pub fn $field(&self) -> usize {
                    self.user_context.general.$field
                }

                #[doc = concat!("Sets the value of ", stringify!(field))]
                #[inline(always)]
                pub fn $setter_name(&mut self, $field: usize) {
                    self.user_context.general.$field = $field;
                }
            )*
        }
    };
}

cpu_context_impl_getter_setter!(
    [rax, set_rax],
    [rbx, set_rbx],
    [rcx, set_rcx],
    [rdx, set_rdx],
    [rsi, set_rsi],
    [rdi, set_rdi],
    [rbp, set_rbp],
    [rsp, set_rsp],
    [r8, set_r8],
    [r9, set_r9],
    [r10, set_r10],
    [r11, set_r11],
    [r12, set_r12],
    [r13, set_r13],
    [r14, set_r14],
    [r15, set_r15],
    [rip, set_rip],
    [rflags, set_rflags]
);

// ---------------------------------------------------------------------------
// Floating-point state
// ---------------------------------------------------------------------------

/// The largest save area vOSTD will make room for.
const MAX_FPU_AREA_SIZE: usize = 4096;

static FPU_AREA_SIZE: core::sync::atomic::AtomicUsize = core::sync::atomic::AtomicUsize::new(512);

/// Records the size of a floating-point save area. Called once, at entry.
pub(crate) fn init_fpu(size: usize) {
    let size = size.clamp(512, MAX_FPU_AREA_SIZE);
    FPU_AREA_SIZE.store(size, core::sync::atomic::Ordering::Relaxed);
}

/// A save area with the alignment `XSAVE` requires.
#[repr(C)]
#[repr(align(64))]
#[derive(Clone, Copy)]
struct XSaveArea([u8; MAX_FPU_AREA_SIZE]);

/// The FPU context of a user task.
///
/// Real OSTD executes `XSAVE`/`XRSTOR` here. On a Linux host the registers may
/// not be live at all — the host defers loading a task's floating-point state
/// until it returns to user mode — so the two operations are the two services
/// `fpu_save` and `fpu_load`, which make the registers live first and then do
/// exactly the same instruction. The public API is real OSTD's, and the kernel
/// proper calls it in the same places: when it switches user threads, when it
/// builds a signal frame, and when it forks.
pub struct FpuContext {
    xsave_area: alloc::boxed::Box<XSaveArea>,
    area_size: usize,
}

impl core::fmt::Debug for FpuContext {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.debug_struct("FpuContext")
            .field("area_size", &self.area_size)
            .finish()
    }
}

impl FpuContext {
    /// Creates a new FPU context.
    pub fn new() -> Self {
        let area_size = FPU_AREA_SIZE.load(core::sync::atomic::Ordering::Relaxed);
        Self {
            xsave_area: alloc::boxed::Box::new(XSaveArea([0; MAX_FPU_AREA_SIZE])),
            area_size,
        }
    }

    /// Saves the CPU's current FPU context to this instance.
    pub fn save(&mut self) {
        let len = self.area_size as u64;
        let ptr = self.xsave_area.0.as_mut_ptr();
        // SAFETY: the area is `area_size` bytes long and 64-byte aligned, which
        // is what the host promised to write into.
        unsafe { (crate::abi::svc().fpu_save)(ptr, len) };
    }

    /// Loads the CPU's FPU context from this instance.
    pub fn load(&self) {
        let len = self.area_size as u64;
        let ptr = self.xsave_area.0.as_ptr();
        // SAFETY: as above, read-only.
        unsafe { (crate::abi::svc().fpu_load)(ptr, len) };
    }

    /// Returns the FPU context as a byte slice.
    pub fn as_bytes(&self) -> &[u8] {
        &self.xsave_area.0[..self.area_size]
    }

    /// Returns the FPU context as a mutable byte slice.
    pub fn as_bytes_mut(&mut self) -> &mut [u8] {
        &mut self.xsave_area.0[..self.area_size]
    }
}

impl Default for FpuContext {
    fn default() -> Self {
        Self::new()
    }
}

impl Clone for FpuContext {
    fn clone(&self) -> Self {
        let mut area = alloc::boxed::Box::new(XSaveArea([0; MAX_FPU_AREA_SIZE]));
        area.0.copy_from_slice(&self.xsave_area.0);
        Self {
            xsave_area: area,
            area_size: self.area_size,
        }
    }
}
