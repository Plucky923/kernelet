# Kbuild file for the endovisor.
#
# Built from the parent directory: make module DIR=linux/endovisor
#
# image.o is the kernelet image: the Rust staticlib of vostd and one kernel
# proper, pre-linked with `ld -r --whole-archive --gc-sections` and dropped in
# here as image.o_shipped by the parent Makefile's `image` target.
obj-m += kernelet.o

kernelet-y := main.o carrier.o space.o evict.o watch.o sched.o switch.o image.o

# objtool understands neither the Rust object nor a function that returns on a
# different stack than it was called on.
OBJECT_FILES_NON_STANDARD_image.o := y
OBJECT_FILES_NON_STANDARD_switch.o := y
