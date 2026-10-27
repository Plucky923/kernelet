// SPDX-License-Identifier: MPL-2.0

//! Checks that concurrent instances of one PIE image have independent state.
//! The host checks the physical backing of the image mappings; this kernel
//! checks the references and initialized and zero-initialized data they expose.

#![no_std]
#![deny(unsafe_code)]

use core::hint::{black_box, spin_loop};
use core::sync::atomic::{AtomicU64, Ordering};
use ostd::boot::boot_info;
use ostd::power::{poweroff, ExitCode};
use ostd::prelude::*;

const INITIAL: u64 = 0x1357_2468_9abc_def0;
static INITIALIZED: AtomicU64 = AtomicU64::new(INITIAL);
static ZEROED: AtomicU64 = AtomicU64::new(0);

struct References {
    initialized: &'static AtomicU64,
    zeroed: &'static AtomicU64,
    transform: fn(u64) -> u64,
}

// These pointers require per-instance relocation. `black_box` at the use sites
// prevents the optimizer from replacing the table accesses with direct ones.
static REFERENCES: References = References {
    initialized: &INITIALIZED,
    zeroed: &ZEROED,
    transform,
};

#[inline(never)]
fn transform(value: u64) -> u64 {
    value.rotate_left(13) ^ INITIAL
}

#[ostd::main]
pub fn main() {
    let id: u64 = boot_info().kernel_cmdline.parse().expect("instance id");
    assert!(id != 0);
    let refs = black_box(&REFERENCES);
    assert!(core::ptr::eq(refs.initialized, &INITIALIZED));
    assert!(core::ptr::eq(refs.zeroed, &ZEROED));
    assert!(core::ptr::fn_addr_eq(refs.transform, transform as fn(u64) -> u64));
    assert_eq!(refs.initialized.load(Ordering::SeqCst), INITIAL);
    assert_eq!(refs.zeroed.load(Ordering::SeqCst), 0);
    assert_eq!((refs.transform)(id), transform(id));
    refs.initialized.store(id, Ordering::SeqCst);
    println!("PIE-CHECK id={} ready fresh-data relocated-pointers", id);

    let mut next = ostd::time::now_ns();
    let mut expected = 0;
    loop {
        let refs = black_box(&REFERENCES);
        if refs.initialized.load(Ordering::SeqCst) != id
            || refs.zeroed.load(Ordering::SeqCst) != expected
            || (refs.transform)(id) != transform(id)
        {
            println!("PIE-CHECK id={} FAIL private-state", id);
            poweroff(ExitCode::Failure);
        }
        expected += 1;
        refs.zeroed.store(expected, Ordering::SeqCst);
        println!("PIE-CHECK id={} progress={}", id, expected);
        next += 50_000_000;
        while ostd::time::now_ns() < next {
            spin_loop();
        }
    }
}
