# pie: concurrent instances of one image

`make -C prototype pie` builds this kernel as `piecheck.image`, registers it
once, and runs overlapping sandboxes of that kind. The kernel runs entirely
in kernel mode and embeds no tenant program.

Each instance checks fresh initialized data and zeroed BSS, then stores its
own identifier and advances a private counter. Static pointers to data and
to a function exercise runtime relocations; the checks verify that those
pointers resolve to the current instance's mapping.

The host driver, `prototype/host/runtime/run-pie.c`, waits for both instances
to make progress, kills and destroys one, and checks that the survivor keeps
running. It then starts a replacement, checks its fresh state, destroys it,
and checks the survivor again before cleaning up the kind.

The endovisor compares every image page in overlapping instances: their
virtual mappings must differ, immutable pages must have the same physical
backing, and writable pages must have distinct backing. The test requires
the resulting sharing confirmations in the serial log, as well as the
kernel's state and progress checks. Its output is
`prototype/.build/serial-pie.log`.
