// SPDX-License-Identifier: MPL-2.0

//! Console output.
//!
//! Real OSTD drives a UART. vOSTD hands whole lines to the host's
//! `log_write` service, which is `printk` on the other side, so it buffers
//! until a newline instead of writing byte by byte.

use core::fmt::{Arguments, Write};

use crate::abi::svc;

const LINE_MAX: usize = 448;

struct LineWriter {
    buf: [u8; LINE_MAX],
    len: usize,
}

impl LineWriter {
    const fn new() -> Self {
        Self {
            buf: [0; LINE_MAX],
            len: 0,
        }
    }

    fn flush(&mut self) {
        if self.len == 0 {
            return;
        }
        // SAFETY: the service takes a pointer and a length to read-only bytes.
        unsafe { (svc().log_write)(self.buf.as_ptr(), self.len as u64) };
        self.len = 0;
    }

    fn push(&mut self, byte: u8) {
        if byte == b'\n' {
            // Emit the line even if it is empty: the kernel proper asked for it.
            // SAFETY: as above.
            unsafe { (svc().log_write)(self.buf.as_ptr(), self.len as u64) };
            self.len = 0;
            return;
        }
        if self.len == LINE_MAX {
            self.flush();
        }
        self.buf[self.len] = byte;
        self.len += 1;
    }
}

impl Write for LineWriter {
    fn write_str(&mut self, s: &str) -> core::fmt::Result {
        for byte in s.as_bytes() {
            self.push(*byte);
        }
        Ok(())
    }
}

/// Prints formatted arguments to the console.
pub fn early_print(args: Arguments) {
    let mut writer = LineWriter::new();
    let _ = writer.write_fmt(args);
    writer.flush();
}

/// Prints to the console.
#[macro_export]
macro_rules! early_print {
    ($fmt: literal $(, $($arg: tt)+)?) => {
        $crate::console::early_print(format_args!($fmt $(, $($arg)+)?))
    }
}

/// Prints to the console with a newline.
#[macro_export]
macro_rules! early_println {
    () => { $crate::early_print!("\n") };
    ($fmt: literal $(, $($arg: tt)+)?) => {
        $crate::console::early_print(format_args!(concat!($fmt, "\n") $(, $($arg)+)?))
    }
}
