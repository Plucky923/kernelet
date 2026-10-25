// SPDX-License-Identifier: MPL-2.0

//! Console output, and the kernel log.
//!
//! Real OSTD drives a UART. vOSTD hands whole lines to one of two host
//! services, so it buffers until a newline instead of writing byte by byte:
//! `console_write`, the sandbox's console, for what the kernel proper prints
//! (`print!` and `println!` of the prelude), and `log_write`, the sandbox's
//! kernel log, for vOSTD's own lines (`early_print!` and `early_println!`, and
//! the panic message). Each goes to the file the holder gave the sandbox for
//! it, or to the host's kernel log when it gave none.

use core::fmt::{Arguments, Write};

use crate::abi::svc;

const LINE_MAX: usize = 448;

/// Which host service a line goes to.
#[derive(Clone, Copy)]
enum Sink {
    /// `log_write`: the kernel log.
    Log,
    /// `console_write`: the console.
    Console,
}

struct LineWriter {
    buf: [u8; LINE_MAX],
    len: usize,
    sink: Sink,
}

impl LineWriter {
    const fn new(sink: Sink) -> Self {
        Self {
            buf: [0; LINE_MAX],
            len: 0,
            sink,
        }
    }

    fn emit(&self) {
        let svc = svc();
        let write = match self.sink {
            Sink::Log => svc.log_write,
            Sink::Console => svc.console_write,
        };
        // SAFETY: the service takes a pointer and a length to read-only bytes.
        unsafe { write(self.buf.as_ptr(), self.len as u64) };
    }

    fn flush(&mut self) {
        if self.len == 0 {
            return;
        }
        self.emit();
        self.len = 0;
    }

    fn push(&mut self, byte: u8) {
        if byte == b'\n' {
            // Emit the line even if it is empty: the kernel proper asked for it.
            self.emit();
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

/// Prints formatted arguments to the kernel log.
pub fn early_print(args: Arguments) {
    let mut writer = LineWriter::new(Sink::Log);
    let _ = writer.write_fmt(args);
    writer.flush();
}

/// Prints formatted arguments to the console.
pub fn console_print(args: Arguments) {
    let mut writer = LineWriter::new(Sink::Console);
    let _ = writer.write_fmt(args);
    writer.flush();
}

/// Prints to the kernel log.
#[macro_export]
macro_rules! early_print {
    ($fmt: literal $(, $($arg: tt)+)?) => {
        $crate::console::early_print(format_args!($fmt $(, $($arg)+)?))
    }
}

/// Prints to the kernel log with a newline.
#[macro_export]
macro_rules! early_println {
    () => { $crate::early_print!("\n") };
    ($fmt: literal $(, $($arg: tt)+)?) => {
        $crate::console::early_print(format_args!(concat!($fmt, "\n") $(, $($arg)+)?))
    }
}

/// Prints to the console: the prelude's `print!`.
#[macro_export]
macro_rules! console_print {
    ($fmt: literal $(, $($arg: tt)+)?) => {
        $crate::console::console_print(format_args!($fmt $(, $($arg)+)?))
    }
}

/// Prints to the console with a newline: the prelude's `println!`.
#[macro_export]
macro_rules! console_println {
    () => { $crate::console_print!("\n") };
    ($fmt: literal $(, $($arg: tt)+)?) => {
        $crate::console::console_print(format_args!(concat!($fmt, "\n") $(, $($arg)+)?))
    }
}
