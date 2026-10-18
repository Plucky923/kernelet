# yield: kernelet code that never gives the processor back

A kernel proper whose one task computes for several seconds inside the
kernelet, in safe Rust, without a system call, an allocation or any other
voluntary preemption point. On a Linux booted with `preempt=none` nothing in
that computation would ever give the processor back, and an ordinary process
pinned to the same processor would starve. The endovisor's watch timer is
what stops that: it delivers the kernelet's tick as an upcall, and when Linux
wants the processor the upcall gives it back with the `vcpu_yield` service
(through the yield stub instead, if the upcall cannot be delivered).

`make yield` boots twice under `preempt=none`: the control with the watch
timer off (`klet_watch=0`), which must starve the competitor, and the real run
with it on, which must not, and must compute the same checksum as with it off
and as the competitor's independent user-space implementation. The ten live
registers of the computation make the checksum a test that the stubs restore
every register and the flags.

The book explains the watch timer and the upcall in chapter 10 (virtual
interrupts) and the yield stub in chapter 11 (sharing a processor politely).

## Files

| file | what it is |
|---|---|
| `src/lib.rs` | the kernel proper and its computation |
| `yield.S` | the tenant program: ask for the computation, then exit |
| `Cargo.toml` | the crate (`yieldk`) |
