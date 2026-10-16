# Build-and-boot plumbing for the kernelet-in-Linux prototype.
#
# The suite and the measurements:
#
#   make test         every functional test, in order, stopping at the first
#                     failure: hello probe yield sched-policy sched-coop
#                     sched-fpu mem-func mem-r2 mem-conc mem-kill mem-pressure
#   make bench        the three measurements, sched-fair sched-perf mem-perf,
#                     reported but never failing the suite: their assertions
#                     depend on the host being quiet
#
# One test each (every one builds what it needs, boots, and checks the log):
#
#   make hello        the unedited 100-line kernel: Hello, world
#   make probe        demand paging, a non-page-fault exception, eviction
#   make yield        the watch timer: two boots under preempt=none, off and on
#   make sched-policy the sched kernel's own scheduler obeys its policy
#   make sched-coop   the mirror: with it, without it, and with an overstayer
#   make sched-fpu    floating-point state survives task switches
#   make mem-func     tenant memory: faults, protection, the withheld set
#   make mem-r2       the sleeping contract, broken on purpose
#   make mem-conc     two virtual CPUs: copies, the range lock, retire
#   make mem-kill     a carrier stopped, continued and killed from outside;
#                     its sibling carries on
#   make mem-pressure the area's entries survive Linux's reclaim
#
# The pieces:
#
#   make crates       download the Rust crates the build needs (once, online)
#   make source       fetch and unpack Linux v6.12 if it is not there yet
#   make patch        apply patches/0001-kernelet-gate.patch (idempotent)
#   make linux        configure (once) and build bzImage + modules_prepare
#   make image        build the kernelet image (vostd + a kernel proper) and
#                     pre-link it; KLET_KERNEL names the kernel proper
#   make initramfs    compile init and pack .build/initramfs.cpio.gz
#   make run          boot the kernel under QEMU, serial log to .build/serial.log
#   make clean        remove the harness artifacts (keeps the kernel build)
#
# Out-of-tree modules are built with `make module DIR=<dir>` and staged for
# the next `make initramfs` with `make stage-module DIR=<dir>`.

LINUX_VERSION ?= 6.12
BUILD         ?= $(CURDIR)/.build
LINUX_DIR     ?= $(BUILD)/linux-$(LINUX_VERSION)
QEMU          ?= /usr/local/qemu/bin/qemu-system-x86_64

ARCH           ?= x86_64
JOBS           ?= 8
TIMEOUT        ?= 120
KERNEL_CMDLINE ?= console=ttyS0 panic=-1

FRAGMENT  := $(CURDIR)/linux/config.fragment
CONFIG    := $(LINUX_DIR)/.config
BZIMAGE   := $(LINUX_DIR)/arch/x86/boot/bzImage
STAGE     := $(BUILD)/stage
INIT      := $(BUILD)/init
INITRAMFS := $(BUILD)/initramfs.cpio.gz
SERIAL    := $(BUILD)/serial.log

KBUILD := $(MAKE) -C $(LINUX_DIR) ARCH=$(ARCH)

# --- the kernelet prototype ---------------------------------------------
PATCH      := $(CURDIR)/patches/0001-kernelet-gate.patch
TEMPLATE   := $(CURDIR)/hello/upstream
CARGO      ?= cargo
RUST_TARGET := x86_64-unknown-none
CARGO_DIR  := $(BUILD)/cargo
# Which crate is the kernel proper of the image: `hello` (the unedited 100-line
# kernel), `probe`, `yieldk`, `schedk` or `mem`. One image per module build.
KLET_KERNEL ?= hello
STATICLIB  := $(CARGO_DIR)/$(RUST_TARGET)/release/lib$(KLET_KERNEL).a
ifeq ($(KLET_KERNEL),hello)
KERNEL_PROPER_DEP := kernel-proper-check $(CURDIR)/hello/hello
else ifeq ($(KLET_KERNEL),probe)
KERNEL_PROPER_DEP := $(CURDIR)/probe/probe
else ifeq ($(KLET_KERNEL),schedk)
KERNEL_PROPER_DEP := $(CURDIR)/sched/sched
else ifeq ($(KLET_KERNEL),mem)
KERNEL_PROPER_DEP := $(CURDIR)/mem/mem
else
KERNEL_PROPER_DEP := $(CURDIR)/yield/yield
endif
IMAGE      := $(CURDIR)/endovisor/image.o_shipped
HELLO_ELF  := $(CURDIR)/hello/hello
PROBE_ELF  := $(CURDIR)/probe/probe
YIELD_ELF  := $(CURDIR)/yield/yield
SCHED_ELF  := $(CURDIR)/sched/sched
KERNELET_KO := $(CURDIR)/endovisor/kernelet.ko
RUNTIME    := $(BUILD)/run-hello

# `-Z plt=yes` is not cosmetic: the x86_64-unknown-none target sets
# plt-by-default=false, which makes LLVM reach its own libcalls (memcpy,
# __adddf3, ...) through the GOT, and the module loader rejects every GOT
# relocation. The image target checks that none is left.
KLET_RUSTFLAGS := -C relocation-model=static -C code-model=kernel \
                  -C no-redzone=y -C panic=abort -C force-unwind-tables=no \
                  -Z plt=yes
KLET_BUILD_STD := -Zbuild-std=core,alloc,compiler_builtins \
                  -Zbuild-std-features=compiler-builtins-mem

.PHONY: all linux config initramfs run clean distclean module stage-module
.PHONY: patch kernel-proper-check image kernelet-module runtime
.PHONY: stage-hello stage-probe stage-yield hello probe yield
.PHONY: check-log check-probe-log check-yield-log

all: linux initramfs

# --- the suite and the measurements -------------------------------------

# Each test's whole output goes to .build/test-<name>.out and only its verdict
# lines are shown; the first failure stops the suite and prints the tail of
# that output. Every test's serial log stays in .build (see each target).
TESTS := hello probe yield sched-policy sched-coop sched-fpu \
         mem-func mem-r2 mem-conc mem-kill mem-pressure
BENCHES := sched-fair sched-perf mem-perf
BENCH_OUT := $(BUILD)/bench

.PHONY: test bench
test:
	@mkdir -p $(BUILD)
	@start=$$(date +%s); \
	for t in $(TESTS); do \
	  t0=$$(date +%s); \
	  if $(MAKE) --no-print-directory $$t > $(BUILD)/test-$$t.out 2>&1; then \
	    echo "  PASS    $$t ($$(( $$(date +%s) - t0 )) s)"; \
	  else \
	    echo "  FAIL    $$t ($$(( $$(date +%s) - t0 )) s); the end of $(BUILD)/test-$$t.out:"; \
	    tail -40 $(BUILD)/test-$$t.out; \
	    echo "make test: FAIL at $$t"; exit 1; \
	  fi; \
	done; \
	echo "make test: PASS ($(words $(TESTS)) tests, $$(( $$(date +%s) - start )) s)"

# The measurements. Each one's boots and checks go to .build/bench/<name>.out;
# what is printed is its table and its verdict, which is reported and never
# fails `make bench`.
bench:
	@mkdir -p $(BENCH_OUT)
	@for t in $(BENCHES); do \
	  echo "=== make $$t"; \
	  $(MAKE) --no-print-directory $$t > $(BENCH_OUT)/$$t.out 2>&1; \
	  $(MAKE) --no-print-directory check-$$t > $(BENCH_OUT)/$$t.table 2>&1; \
	  cat $(BENCH_OUT)/$$t.table; \
	done; \
	echo "make bench: done; the tables are in $(BENCH_OUT)/*.table"

# --- the Linux patch (the gate) -----------------------------------------

# Idempotent: a successful reverse dry-run means the patch is already in. The
# stamp makes it run once per change of the patch, not once per target.
PATCH_STAMP := $(LINUX_DIR)/.kernelet-gate-patch

patch: $(PATCH_STAMP)

$(PATCH_STAMP): $(PATCH) $(LINUX_DIR)/Makefile
	@cd $(LINUX_DIR) && \
	 if patch -p1 -R --dry-run --silent --force < $(PATCH) >/dev/null 2>&1; then \
	   echo "patch: already applied"; \
	 else \
	   patch -p1 --force --silent < $(PATCH) && echo "patch: applied"; \
	 fi
	@touch $@

# --- kernel -------------------------------------------------------------

# A clean checkout has no .build/linux-6.12: fetch the tarball, unpack it and
# throw the tarball away; `patch` then applies the gate. The df guard is here
# because the unpacked and built tree takes about 1.8 GB.
LINUX_TARBALL := linux-$(LINUX_VERSION).tar.xz
LINUX_URL     := https://cdn.kernel.org/pub/linux/kernel/v6.x/$(LINUX_TARBALL)
MIN_FREE_GB   ?= 6

.PHONY: df-guard
df-guard:
	@mkdir -p $(BUILD); \
	 free=$$(df -P -BG $(BUILD) | awk 'NR == 2 { print $$4 }' | tr -dc '0-9'); \
	 echo "free where $(BUILD) is: $${free} GiB (minimum $(MIN_FREE_GB))"; \
	 test "$$free" -ge "$(MIN_FREE_GB)" || \
	   { echo "refusing to continue with less than $(MIN_FREE_GB) GiB free"; exit 1; }

$(LINUX_DIR)/Makefile:
	$(MAKE) --no-print-directory df-guard
	mkdir -p $(BUILD)
	@echo "fetching $(LINUX_URL)"
	cd $(BUILD) && curl -fL -o $(LINUX_TARBALL) $(LINUX_URL)
	cd $(BUILD) && tar xf $(LINUX_TARBALL)
	rm -f $(BUILD)/$(LINUX_TARBALL)
	@test -f $@ || { echo "unpack failed: no $@"; exit 1; }

.PHONY: source
source: $(LINUX_DIR)/Makefile $(PATCH_STAMP)

# tinyconfig, then the fragment, then let olddefconfig settle the rest.
$(CONFIG): $(FRAGMENT) $(PATCH_STAMP)
	$(KBUILD) tinyconfig
	cd $(LINUX_DIR) && ARCH=$(ARCH) ./scripts/kconfig/merge_config.sh -m -O . .config $(FRAGMENT)
	$(KBUILD) olddefconfig

config: $(CONFIG)

# `modules` is not redundant next to `modules_prepare`: only it writes the
# tree's Module.symvers, and without that modpost cannot resolve even
# _printk for an out-of-tree module.
linux: $(PATCH_STAMP) $(CONFIG)
	$(MAKE) --no-print-directory df-guard
	$(KBUILD) -j$(JOBS) bzImage
	$(KBUILD) -j$(JOBS) modules modules_prepare
	@ls -l $(BZIMAGE)

# --- out-of-tree modules ------------------------------------------------

# make module DIR=endovisor
module:
	@test -n "$(DIR)" || { echo "usage: make module DIR=<dir>"; exit 2; }
	$(KBUILD) -j$(JOBS) M=$(abspath $(DIR)) modules

stage-module: module
	mkdir -p $(STAGE)/modules
	cp $(abspath $(DIR))/*.ko $(STAGE)/modules/

# --- the kernelet image -------------------------------------------------

# Every build is --offline, so that a boot never depends on the network. The
# crates the workspace's Cargo.lock names, and the ones the standard library's
# own build needs, are downloaded once: by `make crates`, or by the first build,
# through the stamp, if the local registry does not have them yet.
CRATES_STAMP := $(BUILD)/crates.stamp
FETCH_STD    := -Zbuild-std=core,alloc,compiler_builtins --target $(RUST_TARGET)

.PHONY: crates
crates:
	cd $(CURDIR) && $(CARGO) fetch
	cd $(CURDIR) && $(CARGO) fetch $(FETCH_STD)
	@mkdir -p $(BUILD) && touch $(CRATES_STAMP)

$(CRATES_STAMP): Cargo.lock
	@cd $(CURDIR) && \
	 if $(CARGO) fetch --offline >/dev/null 2>&1 && \
	    $(CARGO) fetch --offline $(FETCH_STD) >/dev/null 2>&1; then \
	   echo "crates: every crate is in the local registry"; \
	 else \
	   echo "crates: downloading what the local registry lacks (once; needs the network)"; \
	   $(CARGO) fetch && $(CARGO) fetch $(FETCH_STD) || \
	   { echo "crates: the download failed; run make crates where there is a network"; exit 1; }; \
	 fi
	@mkdir -p $(BUILD) && touch $@

# The kernel proper is never edited: it must stay byte-identical to the
# template in the Asterinas tree.
kernel-proper-check:
	cmp $(CURDIR)/hello/src/lib.rs $(TEMPLATE)/lib.rs
	cmp $(CURDIR)/hello/hello.S $(TEMPLATE)/hello.S
	@echo "kernel proper: identical to the template"

# The tenant program, assembled exactly as the book says. It has to sit next to
# the kernel proper because `include_bytes!("../hello")` says so.
$(HELLO_ELF): $(CURDIR)/hello/hello.S
	gcc -static -nostdlib $< -o $@

# vostd + the kernel proper -> one relocatable object for kbuild to swallow.
#
# image_start.o and image_end.o bracket the image's text with two symbols the
# eviction sweep needs; they have to be the first and the last object of the
# link, and `--gc-sections` has to be told to keep them.
# The kernelet-stack size the endovisor's pool hands out (KLET_STACK_SIZE, 256 KiB)
# and the one OSTD's task layer asks for have to be the same number.
KLET_STACK_PAGES := 64

# compiler_builtins gives the image weak global definitions of the memory
# functions. Left global, they would also satisfy the endovisor's own calls
# when Kbuild links image.o into the module, and Linux code would run kernelet
# code; made local, the image keeps them and the endovisor gets Linux's.
IMAGE_LOCAL := memcpy memmove memset memcmp bcmp

image: $(CRATES_STAMP) $(KERNEL_PROPER_DEP)
	cd $(CURDIR) && CARGO_TARGET_DIR=$(CARGO_DIR) RUSTFLAGS="$(KLET_RUSTFLAGS)" \
	  OSTD_TASK_STACK_SIZE_IN_PAGES=$(KLET_STACK_PAGES) \
	  $(CARGO) build --offline --release -p $(KLET_KERNEL) \
	    --target $(RUST_TARGET) $(KLET_BUILD_STD) || \
	  { echo "image: the build failed; it is --offline, so if a crate is missing, run make crates (once, with a network)"; exit 1; }
	gcc -c -o $(BUILD)/image_start.o endovisor/image_start.S
	gcc -c -o $(BUILD)/image_end.o endovisor/image_end.S
	ld -r --gc-sections \
	  -u kernelet_entry_table -u __klet_image_text_start -u __klet_image_text_end \
	  -o $(IMAGE) $(BUILD)/image_start.o \
	  --whole-archive $(STATICLIB) --no-whole-archive $(BUILD)/image_end.o
	objcopy $(foreach f,$(IMAGE_LOCAL),--localize-symbol=$(f)) $(IMAGE)
	@if readelf -rW $(IMAGE) | grep -q GOT; then \
	   echo "image.o has GOT relocations, which the module loader rejects"; \
	   readelf -rW $(IMAGE) | grep GOT | head; exit 1; fi
	@if nm -u $(IMAGE) | grep -q .; then \
	   echo "image.o has undefined symbols:"; nm -u $(IMAGE); exit 1; fi
	@echo "image: $$(stat -c %s $(IMAGE)) bytes, relocations:" \
	  "$$(readelf -rW $(IMAGE) | awk '$$3 ~ /^R_X86_64/ { print $$3 }' | sort -u | tr '\n' ' ')"
	@readelf -rW $(IMAGE) | awk '{print $$3}' | grep -E '^R_' | sort | uniq -c

$(PROBE_ELF): $(CURDIR)/probe/probe.S
	gcc -static -nostdlib $< -o $@

$(YIELD_ELF): $(CURDIR)/yield/yield.S
	gcc -static -nostdlib $< -o $@

$(SCHED_ELF): $(CURDIR)/sched/sched.S
	gcc -static -nostdlib $< -o $@

$(CURDIR)/mem/mem: $(CURDIR)/mem/mem.S
	gcc -static -nostdlib $< -o $@

kernelet-module: image
	$(MAKE) module DIR=endovisor
	@echo "kernelet.ko built with the $(KLET_KERNEL) kernel proper"

runtime: runtime/run-hello.c runtime/run-probe.c runtime/run-yield.c runtime/run-sched.c runtime/run-mem.c
	gcc -static -O2 -Wall -Wextra -o $(RUNTIME) runtime/run-hello.c
	gcc -static -O2 -Wall -Wextra -o $(BUILD)/run-probe runtime/run-probe.c
	gcc -static -O2 -Wall -Wextra -o $(BUILD)/run-yield runtime/run-yield.c
	gcc -static -O2 -Wall -Wextra -o $(BUILD)/run-sched runtime/run-sched.c -lpthread
	gcc -static -O2 -Wall -Wextra -o $(BUILD)/run-mem runtime/run-mem.c

# --- initramfs ----------------------------------------------------------

# Always repacked: what is staged under .build/stage changes independently
# of init.c.
initramfs: $(INITRAMFS)

# /dev/console has to be a real node in the archive: the kernel opens it
# from the unpacked initramfs to give init its stdio, before init has had a
# chance to mount devtmpfs. The archive is written by the kernel's own
# usr/gen_init_cpio from a list of what is in .build/stage, where a device
# node is one line, so no mknod, and no privilege, is needed: everything in
# the archive is owned by root, whoever builds it.
GEN_INIT_CPIO := $(LINUX_DIR)/usr/gen_init_cpio
INITRAMFS_LIST := $(BUILD)/initramfs.list

$(GEN_INIT_CPIO): $(PATCH_STAMP)
	$(KBUILD) usr/gen_init_cpio

.PHONY: $(INITRAMFS)
$(INITRAMFS): initramfs/init.c $(GEN_INIT_CPIO)
	gcc -static -O2 -Wall -Wextra -o $(INIT) initramfs/init.c
	mkdir -p $(STAGE)/dev $(STAGE)/proc $(STAGE)/sys $(STAGE)/modules $(STAGE)/tests
	rm -f $(STAGE)/dev/console
	cp $(INIT) $(STAGE)/init
	cd $(STAGE) && { \
	  find . -mindepth 1 -type d -printf 'dir /%P %m 0 0\n'; \
	  echo 'nod /dev/console 0600 0 0 c 5 1'; \
	  find . -type f -printf 'file /%P $(STAGE)/%P %m 0 0\n'; \
	} > $(INITRAMFS_LIST)
	$(GEN_INIT_CPIO) $(INITRAMFS_LIST) | gzip -9 > $@
	@ls -l $@

# --- staging the prototype ----------------------------------------------

# Only one test runs per boot, because the module carries one kernelet image.
stage-hello: kernelet-module runtime
	mkdir -p $(STAGE)/modules $(STAGE)/tests
	rm -f $(STAGE)/tests/* $(STAGE)/*.klet
	cp $(KERNELET_KO) $(STAGE)/modules/
	printf 'kernelet.ko\n' > $(STAGE)/modules/order
	cp $(RUNTIME) $(STAGE)/tests/10-hello
	chmod +x $(STAGE)/tests/10-hello
	printf 'KLET\002\000\000\000\001\000\000\000\n' > $(STAGE)/hello.klet
	chmod +x $(STAGE)/hello.klet
	@echo "staged: kernelet.ko (hello), /tests/10-hello, /hello.klet"

# WATCH=0 loads the module with the per-processor watch timer turned off, which
# is the control for the yield test.
WATCH ?= 1
stage-yield: kernelet-module runtime
	mkdir -p $(STAGE)/modules $(STAGE)/tests
	rm -f $(STAGE)/tests/* $(STAGE)/*.klet
	cp $(KERNELET_KO) $(STAGE)/modules/
	printf 'kernelet.ko klet_watch=$(WATCH)\n' > $(STAGE)/modules/order
	cp $(BUILD)/run-yield $(STAGE)/tests/10-yield
	chmod +x $(STAGE)/tests/10-yield
	printf 'KLET\002\000\000\000\001\000\000\000\n' > $(STAGE)/yield.klet
	chmod +x $(STAGE)/yield.klet
	@echo "staged: kernelet.ko (yield, klet_watch=$(WATCH)), /tests/10-yield, /yield.klet"

stage-probe: kernelet-module runtime
	mkdir -p $(STAGE)/modules $(STAGE)/tests
	rm -f $(STAGE)/tests/* $(STAGE)/*.klet
	cp $(KERNELET_KO) $(STAGE)/modules/
	printf 'kernelet.ko\n' > $(STAGE)/modules/order
	cp $(BUILD)/run-probe $(STAGE)/tests/10-probe
	chmod +x $(STAGE)/tests/10-probe
	printf 'KLET\002\000\000\000\001\000\000\000\n' > $(STAGE)/probe.klet
	chmod +x $(STAGE)/probe.klet
	@echo "staged: kernelet.ko (probe), /tests/10-probe, /probe.klet"

# --- the scheduler experiments ------------------------------------------

# A .klet file is the sandbox's configuration: magic, ABI version, how many
# virtual CPUs, and a command line that the kernel proper reads through
# ostd::boot::boot_info().kernel_cmdline.
SCHED_VCPUS   ?= 2
SCHED_MODE    ?= policy
SCHED_DUR     ?= 3000
SCHED_ARGS    ?=
SCHED_RUNMODE ?= policy
MIRROR        ?= 1

stage-sched: kernelet-module runtime
	mkdir -p $(STAGE)/modules $(STAGE)/tests
	rm -f $(STAGE)/tests/* $(STAGE)/*.klet
	cp $(KERNELET_KO) $(STAGE)/modules/
	printf 'kernelet.ko klet_watch=$(WATCH) klet_mirror=$(MIRROR)\n' > $(STAGE)/modules/order
	cp $(BUILD)/run-sched $(STAGE)/tests/10-sched
	chmod +x $(STAGE)/tests/10-sched
	printf 'KLET\002\000\000\000' > $(STAGE)/sched.klet
	printf "$$(printf '\\%03o' $(SCHED_VCPUS))\000\000\000" >> $(STAGE)/sched.klet
	printf 'mode=$(SCHED_MODE) dur=$(SCHED_DUR) $(SCHED_ARGS)\n' >> $(STAGE)/sched.klet
	chmod +x $(STAGE)/sched.klet
	printf '$(SCHED_RUNMODE)\n' > $(STAGE)/tests/10-sched.arg
	@echo "staged: kernelet.ko (sched), /tests/10-sched $(SCHED_RUNMODE), /sched.klet mode=$(SCHED_MODE)"

SCHED_CMDLINE := console=ttyS0 panic=-1

# One boot of the sched kernel. Everything about it comes from the variables above.
.PHONY: sched-boot
sched-boot:
	$(MAKE) KLET_KERNEL=schedk linux
	$(MAKE) KLET_KERNEL=schedk stage-sched initramfs
	-$(MAKE) run KERNEL_CMDLINE="$(SCHED_CMDLINE)" TIMEOUT=$(SCHED_TIMEOUT)

SCHED_TIMEOUT ?= 180

SCHED_POLICY_LOG := $(BUILD)/serial-sched-policy.log
SCHED_COOP_ON    := $(BUILD)/serial-sched-coop-on.log
SCHED_COOP_OFF   := $(BUILD)/serial-sched-coop-off.log
SCHED_COOP_OVER  := $(BUILD)/serial-sched-coop-over.log
SCHED_FAIR1      := $(BUILD)/serial-sched-fair1.log
SCHED_FAIR50     := $(BUILD)/serial-sched-fair50.log
SCHED_FAIR50O    := $(BUILD)/serial-sched-fair50o.log
SCHED_PERF_LOG   := $(BUILD)/serial-sched-perf-

.PHONY: sched-policy sched-coop sched-fair sched-perf sched-fpu sched
sched: sched-policy sched-coop sched-fair sched-perf

# 1. The policy is obeyed, and it preempts.
sched-policy:
	$(MAKE) sched-boot SCHED_MODE=policy SCHED_RUNMODE=policy SCHED_DUR=3000 SCHED_TIMEOUT=120
	cp $(SERIAL) $(SCHED_POLICY_LOG)
	@$(MAKE) --no-print-directory check-sched-policy

# 5. The floating-point state of two tenant threads survives the switch.
sched-fpu:
	$(MAKE) sched-boot SCHED_MODE=fpu SCHED_RUNMODE=policy SCHED_DUR=3000 SCHED_TIMEOUT=120
	-cp $(SERIAL) $(BUILD)/serial-sched-fpu.log
	@$(MAKE) --no-print-directory check-sched-fpu

# 2. Cooperative: the mirror, with it and without it, and the overstayer.
#
# The design bounds a critical section that Linux wants the processor back
# from at two 1 ms ticks (watch.c forces the yield at the first tick at least a
# millisecond after the first strike). The check allows 4000 us, because the
# deferral is measured in wall clock, and a tick that a busy host delivers late
# lengthens it; the check prints beside it the boot's stolen_ms and the longest
# gap between two watch ticks.
sched-coop:
	$(MAKE) sched-boot SCHED_MODE=coop SCHED_RUNMODE=coop SCHED_DUR=10000 SCHED_TIMEOUT=180 MIRROR=1
	cp $(SERIAL) $(SCHED_COOP_ON)
	$(MAKE) sched-boot SCHED_MODE=coop SCHED_RUNMODE=coop SCHED_DUR=10000 SCHED_TIMEOUT=180 MIRROR=0
	cp $(SERIAL) $(SCHED_COOP_OFF)
	$(MAKE) sched-boot SCHED_MODE=coop-over SCHED_RUNMODE=coop SCHED_DUR=10000 SCHED_TIMEOUT=180 MIRROR=1
	cp $(SERIAL) $(SCHED_COOP_OVER)
	@$(MAKE) --no-print-directory check-sched-coop

# 3. Fair: the sandbox's share of the processors, with 1, 50 and 50+overstayer.
sched-fair:
	$(MAKE) sched-boot SCHED_MODE=fair SCHED_ARGS="tasks=1" SCHED_RUNMODE=fair SCHED_DUR=10000 SCHED_TIMEOUT=180
	cp $(SERIAL) $(SCHED_FAIR1)
	$(MAKE) sched-boot SCHED_MODE=fair SCHED_ARGS="tasks=50" SCHED_RUNMODE=fair SCHED_DUR=10000 SCHED_TIMEOUT=180
	cp $(SERIAL) $(SCHED_FAIR50)
	$(MAKE) sched-boot SCHED_MODE=fair SCHED_ARGS="tasks=50 over=1" SCHED_RUNMODE=fair SCHED_DUR=10000 SCHED_TIMEOUT=180
	cp $(SERIAL) $(SCHED_FAIR50O)
	@$(MAKE) --no-print-directory check-sched-fair

# 4. Efficient: five runs, kernelet and native Linux side by side.
sched-perf:
	for i in 1 2 3 4 5; do \
	  $(MAKE) sched-boot SCHED_MODE=perf SCHED_RUNMODE=perf SCHED_DUR=8000 SCHED_TIMEOUT=180 && \
	  cp $(SERIAL) $(SCHED_PERF_LOG)$$i.log; \
	done
	@$(MAKE) --no-print-directory check-sched-perf

CHECK_SCHED_COMMON = \
	for pat in $(CHECK_BAD); do \
	  if grep -qF "$$pat" $(1); then \
	    echo "  BAD     $(1) contains $$pat"; grep -nF "$$pat" $(1) | head -2; rc=1; \
	  fi; \
	done

check-sched-policy:
	@rc=0; \
	sed -n '/INIT: loading kernelet.ko/,$$p' $(SCHED_POLICY_LOG) | sed 's/\r$$//' \
	  | grep -E 'SCHED-CONF|SCHED-PHASE|SCHED-TASK|SCHED-TRACE begin|SCHED-RESULT|SCHED-ELAPSED|STATS|vCPU' ; \
	python3 bench/sched-model.py $(SCHED_POLICY_LOG) || rc=1; \
	for pat in 'SCHED-DONE' 'kernelet: stopped, exit code 0'; do \
	  if grep -qF "$$pat" $(SCHED_POLICY_LOG); then echo "  ok      $$pat"; \
	  else echo "  MISSING $$pat"; rc=1; fi; \
	done; \
	for pat in $(CHECK_BAD); do \
	  if grep -qF "$$pat" $(SCHED_POLICY_LOG); then \
	    echo "  BAD     the log contains $$pat"; rc=1; \
	  else echo "  ok      no $$pat"; fi; \
	done; \
	if grep -qF 'delete_module kernelet failed' $(SCHED_POLICY_LOG) || ! grep -qF 'kernelet: STATS' $(SCHED_POLICY_LOG); then \
	  echo "  BAD     $(SCHED_POLICY_LOG): the module did not unload cleanly"; rc=1; fi; \
	if [ $$rc -eq 0 ]; then echo "make sched-policy: PASS"; else echo "make sched-policy: FAIL"; fi; \
	exit $$rc

check-sched-fpu:
	@rc=0; \
	grep -E 'SCHED-RESULT fpu|SCHED-FPU|fpu_swap' $(SERIAL) | sed 's/\r$$//'; \
	if grep -q 'SCHED-RESULT fpu OK' $(SERIAL); then \
	  echo "  ok      two tenant threads kept four distinct xmm values each across every switch"; \
	else echo "  BAD     the floating-point state did not survive the switch"; rc=1; fi; \
	n=$$(grep -o 'checkins=[0-9]*' $(SERIAL) | tail -1 | cut -d= -f2); \
	if [ "$${n:-0}" -ge 100 ]; then echo "  ok      $$n check-in(s)"; \
	else echo "  BAD     only $${n:-0} check-in(s): the test did not really run"; rc=1; fi; \
	for pat in $(CHECK_BAD); do \
	  if grep -qF "$$pat" $(SERIAL); then echo "  BAD     the log contains $$pat"; rc=1; fi; \
	done; \
	if grep -qF 'delete_module kernelet failed' $(SERIAL) || ! grep -qF 'kernelet: STATS' $(SERIAL); then \
	  echo "  BAD     $(SERIAL): the module did not unload cleanly"; rc=1; fi; \
	if [ $$rc -eq 0 ]; then echo "make sched-fpu: PASS"; else echo "make sched-fpu: FAIL"; fi; \
	exit $$rc

check-sched-coop:
	@rc=0; \
	for f in $(SCHED_COOP_ON) $(SCHED_COOP_OFF) $(SCHED_COOP_OVER); do \
	  echo "--- $$f"; grep -E 'STATS|SCHED-RESULT coop|competitor rounds|SIB-USEC|KLET-USEC|runnable task' $$f | sed 's/\r$$//'; \
	done; \
	bon=$$(grep -o 'bad_preempt=[0-9]*' $(SCHED_COOP_ON) | tail -1 | cut -d= -f2); \
	boff=$$(grep -o 'bad_preempt=[0-9]*' $(SCHED_COOP_OFF) | tail -1 | cut -d= -f2); \
	bovr=$$(grep -o 'bad_preempt=[0-9]*' $(SCHED_COOP_OVER) | tail -1 | cut -d= -f2); \
	fy=$$(grep -o 'forced_yields=[0-9]*' $(SCHED_COOP_OVER) | tail -1 | cut -d= -f2); \
	dus=$$(grep -o 'longest_defer_us=[0-9]*' $(SCHED_COOP_OVER) | tail -1 | cut -d= -f2); \
	stolen=$$(grep -o 'stolen_ms=[0-9]*' $(SCHED_COOP_OVER) | tail -1 | cut -d= -f2); \
	gap=$$(grep -o 'longest_tick_gap_us=[0-9]*' $(SCHED_COOP_OVER) | tail -1 | cut -d= -f2); \
	if [ "$${bon:-1}" -eq 0 ]; then \
	  echo "  ok      with the mirror on, 0 involuntary deschedules of a carrier in a critical section"; \
	else echo "  BAD     with the mirror on, $$bon involuntary deschedule(s) in a critical section"; rc=1; fi; \
	echo "  info    with the mirror off: $$boff involuntary deschedule(s) in a critical section"; \
	if [ "$${boff:-0}" -gt 0 ]; then \
	  echo "  ok      the mirror is what makes the difference (off: $$boff, on: $$bon)"; \
	else echo "  info    the control run also saw 0; the host did not preempt a critical section"; fi; \
	if [ "$${fy:-0}" -gt 0 ]; then \
	  echo "  ok      the overstayer was forced to yield $$fy time(s)"; \
	else echo "  BAD     the overstayer was never forced to yield"; rc=1; fi; \
	echo "  info    the overstayer boot's longest deferral was $$dus us, measured in wall clock;" \
	     "its carriers spent $${stolen:-?} ms off a processor while running kernelet code (stolen_ms)," \
	     "and the longest gap between two watch ticks was $${gap:-?} us"; \
	if [ "$${dus:-999999}" -le 4000 ]; then \
	  echo "  ok      no critical section kept a processor for more than 4000 us (longest deferral $$dus us)"; \
	else echo "  BAD     a critical section kept a processor for $$dus us"; rc=1; fi; \
	if [ "$${bovr:-1}" -eq 0 ]; then \
	  echo "  ok      even with an overstayer, 0 involuntary deschedules in a critical section"; \
	else echo "  BAD     with an overstayer, $$bovr involuntary deschedule(s)"; rc=1; fi; \
	for f in $(SCHED_COOP_ON) $(SCHED_COOP_OFF) $(SCHED_COOP_OVER); do \
	  for pat in $(CHECK_BAD); do \
	    if grep -qF "$$pat" $$f; then echo "  BAD     $$f contains $$pat"; rc=1; fi; \
	  done; \
	  if grep -qF 'delete_module kernelet failed' $$f || ! grep -qF 'kernelet: STATS' $$f; then \
	    echo "  BAD     $$f: the module did not unload cleanly"; rc=1; fi; \
	done; \
	if [ $$rc -eq 0 ]; then echo "make sched-coop: PASS"; else echo "make sched-coop: FAIL"; fi; \
	exit $$rc

check-sched-fair:
	@rc=0; \
	for f in $(SCHED_FAIR1) $(SCHED_FAIR50) $(SCHED_FAIR50O); do \
	  echo "--- $$f"; grep -E 'SIB-USEC|KLET-USEC|competitor rounds|runnable task|STATS|SCHED-RESULT fair' $$f | sed 's/\r$$//'; \
	done; \
	s1=$$(grep -o 'SIB-USEC [0-9]*' $(SCHED_FAIR1) | tail -1 | awk '{print $$2}'); \
	s2=$$(grep -o 'SIB-USEC [0-9]*' $(SCHED_FAIR50) | tail -1 | awk '{print $$2}'); \
	s3=$$(grep -o 'SIB-USEC [0-9]*' $(SCHED_FAIR50O) | tail -1 | awk '{print $$2}'); \
	e1=$$(grep -o 'elapsed_ms [0-9]*' $(SCHED_FAIR1) | tail -1 | awk '{print $$2}'); \
	e2=$$(grep -o 'elapsed_ms [0-9]*' $(SCHED_FAIR50) | tail -1 | awk '{print $$2}'); \
	e3=$$(grep -o 'elapsed_ms [0-9]*' $(SCHED_FAIR50O) | tail -1 | awk '{print $$2}'); \
	echo "  info    the sibling group got $$s1, $$s2 and $$s3 microseconds of processor over $$e1, $$e2 and $$e3 ms"; \
	echo "  info    the runs are not the same length: strict priority means the lower levels"; \
	echo "          only notice the deadline once the higher ones have gone, so the share -"; \
	echo "          processor microseconds per millisecond of wall clock - is what may be compared"; \
	spread=$$(awk -v a=$$s1 -v b=$$s2 -v c=$$s3 -v x=$$e1 -v y=$$e2 -v z=$$e3 'BEGIN{ \
	  ra=a/x/1000; rb=b/y/1000; rc=c/z/1000; \
	  lo=ra; hi=ra; if(rb<lo)lo=rb; if(rb>hi)hi=rb; if(rc<lo)lo=rc; if(rc>hi)hi=rc; \
	  printf "%.2f %.3f %.3f %.3f", 100.0*(hi-lo)/hi, ra, rb, rc }'); \
	set -- $$spread; \
	echo "  info    the sibling's share was $$2, $$3 and $$4 processors; spread $$1%"; \
	if awk -v s=$$1 'BEGIN{exit !(s<=3.0)}'; then \
	  echo "  ok      the sibling's share is the same whether the sandbox runs 1, 50 or 50 tasks and an overstayer (within 3%)"; \
	else echo "  BAD     the sibling's share varies by $$1%"; rc=1; fi; \
	if awk -v s=$$2 'BEGIN{exit !(s>=0.90 && s<=1.10)}'; then \
	  echo "  ok      and it is close to the ideal of one of the two shared processors"; \
	else echo "  BAD     the sibling's share is $$2 processors, not close to 1"; rc=1; fi; \
	for f in $(SCHED_FAIR1) $(SCHED_FAIR50) $(SCHED_FAIR50O); do \
	  n=$$(grep -o 'at most [0-9]* runnable' $$f | tail -1 | awk '{print $$3}'); \
	  if [ "$${n:-99}" -le 3 ]; then \
	    echo "  ok      $$f: the host never saw more than $$n runnable task(s) of the sandbox"; \
	  else echo "  BAD     $$f: the host saw $$n runnable tasks of the sandbox"; rc=1; fi; \
	  if grep -qF 'delete_module kernelet failed' $$f || ! grep -qF 'kernelet: STATS' $$f; then \
	    echo "  BAD     $$f: the module did not unload cleanly"; rc=1; fi; \
	  for pat in $(CHECK_BAD); do \
	    if grep -qF "$$pat" $$f; then echo "  BAD     $$f contains $$pat"; rc=1; fi; \
	  done; \
	done; \
	if [ $$rc -eq 0 ]; then echo "make sched-fair: PASS"; else echo "make sched-fair: FAIL"; fi; \
	exit $$rc

check-sched-perf:
	@rc=0; \
	python3 bench/sched-perf.py $(SCHED_PERF_LOG)*.log || rc=1; \
	for f in $(SCHED_PERF_LOG)*.log; do \
	  for pat in $(CHECK_BAD); do \
	    if grep -qF "$$pat" $$f; then echo "  BAD     $$f contains $$pat"; rc=1; fi; \
	  done; \
	  if grep -qF 'delete_module kernelet failed' $$f || ! grep -qF 'kernelet: STATS' $$f; then \
	    echo "  BAD     $$f: the module did not unload cleanly"; rc=1; fi; \
	done; \
	if [ $$rc -eq 0 ]; then echo "make sched-perf: PASS"; else echo "make sched-perf: FAIL"; fi; \
	exit $$rc

# --- tenant memory: the mem kernel ---------------------------------------

# One boot of the mem kernel. MEM_ARGS is the sandbox's command line (mode=...),
# MEM_MODPARAMS the endovisor's module parameters, MEM_RUNMODE what run-mem
# does around the sandbox (plain, pressure for E7, kill for E11).
MEM_VCPUS     ?= 1
MEM_ARGS      ?= mode=func
MEM_MODPARAMS ?=
MEM_RUNMODE   ?= plain
MEM_TIMEOUT   ?= 180
MEM_LOGDIR    := $(BUILD)/mem
SWAP_IMG      := $(MEM_LOGDIR)/swap.img

.PHONY: stage-mem mem-boot mem mem-func mem-r2 mem-conc mem-kill mem-pressure mem-perf
.PHONY: check-mem-log check-mem-r2 check-mem-perf check-mem-kill

stage-mem: kernelet-module runtime
	mkdir -p $(STAGE)/modules $(STAGE)/tests
	rm -f $(STAGE)/tests/* $(STAGE)/*.klet
	cp $(KERNELET_KO) $(STAGE)/modules/
	printf 'kernelet.ko $(MEM_MODPARAMS)\n' > $(STAGE)/modules/order
	cp $(BUILD)/run-mem $(STAGE)/tests/10-mem
	chmod +x $(STAGE)/tests/10-mem
	printf 'KLET\002\000\000\000' > $(STAGE)/mem.klet
	printf "$$(printf '\\%03o' $(MEM_VCPUS))\000\000\000" >> $(STAGE)/mem.klet
	printf '$(MEM_ARGS)\n' >> $(STAGE)/mem.klet
	chmod +x $(STAGE)/mem.klet
	printf '$(MEM_RUNMODE)\n' > $(STAGE)/tests/10-mem.arg
	@echo "staged: kernelet.ko (mem) $(MEM_MODPARAMS), /mem.klet $(MEM_ARGS)"

# MEM_LOG names the copy of the serial log this boot leaves in .build/mem.
mem-boot:
	mkdir -p $(MEM_LOGDIR)
	$(MAKE) KLET_KERNEL=mem linux
	$(MAKE) KLET_KERNEL=mem stage-mem initramfs
	-$(MAKE) run TIMEOUT=$(MEM_TIMEOUT)
	cp $(SERIAL) $(MEM_LOGDIR)/$(MEM_LOG).log

# Everything a passing mem boot's log must and must not contain.
check-mem-log:
	@f=$(MEM_LOGDIR)/$(MEM_LOG).log; rc=0; \
	sed 's/\r$$//' $$f | grep -E 'MEM-|E7-|RUN-MEM: HOG|RUN-MEM: (swap|whole)|MEMSTATS|kernelet: stopped' ; \
	if grep -q 'MEM-CHECK FAIL' $$f; then echo "  BAD     a check failed"; rc=1; fi; \
	n=$$(grep -c 'MEM-CHECK ok' $$f); echo "  info    $$n check(s) passed"; \
	for pat in 'MEM-DONE ok' 'kernelet: stopped, exit code 0' 'INIT: done'; do \
	  if grep -qF "$$pat" $$f; then echo "  ok      $$pat"; else echo "  MISSING $$pat"; rc=1; fi; \
	done; \
	if grep -qF 'delete_module kernelet failed' $$f; then echo "  BAD     unclean module unload"; rc=1; \
	else echo "  ok      clean module unload"; fi; \
	for pat in $(CHECK_BAD); do \
	  if grep -qF "$$pat" $$f; then echo "  BAD     the log contains $$pat"; grep -nF "$$pat" $$f | head -3; rc=1; \
	  else echo "  ok      no $$pat"; fi; \
	done; \
	if [ $$rc -eq 0 ]; then echo "$(MEM_LOG): PASS"; else echo "$(MEM_LOG): FAIL"; fi; exit $$rc

# E2, E3, E4 and E10: mapped pages need no Linux fault, one fault maps a
# fault-around window, a protection change keeps the entries, a map under a
# preemption guard is legal, and PROT_NONE goes through the withheld set.
mem-func:
	$(MAKE) mem-boot MEM_ARGS="mode=func" MEM_LOG=func
	@$(MAKE) --no-print-directory check-mem-log MEM_LOG=func

# E5: a sleeping service under a kernelet spin lock ends the kernelet by vOSTD's
# R2 assertion, and Linux reports nothing.
mem-r2:
	$(MAKE) mem-boot MEM_ARGS="mode=r2" MEM_LOG=r2
	@$(MAKE) --no-print-directory check-mem-r2

check-mem-r2:
	@f=$(MEM_LOGDIR)/r2.log; rc=0; sed 's/\r$$//' $$f | grep -E 'MEM-E5|R2 violated|panicked|kernelet: stopped|sleeping function'; \
	if grep -q 'R2 violated: the sleeping service vm_map was called holding 1 kernelet spin lock' $$f; then echo "  ok      vOSTD's assertion fired"; else echo "  MISSING the R2 assertion"; rc=1; fi; \
	if grep -q 'kernelet: stopped, exit code [1-9]' $$f; then echo "  ok      the kernelet was stopped by its own panic"; else echo "  MISSING the stop"; rc=1; fi; \
	if grep -q 'MEM-E5 FAIL' $$f; then echo "  BAD     the map returned"; rc=1; fi; \
	m=$$(grep -o 'MEMSTATS faults=[0-9]* mkwrites=[0-9]* reported=[0-9]* kernel_faults=[0-9]* maps=[0-9]*' $$f | sed 's/.*maps=//'); \
	if [ "$${m:-1}" = "0" ]; then echo "  ok      no vm_map ever reached the endovisor"; else echo "  BAD     vm_map crossed ($$m)"; rc=1; fi; \
	for pat in $(CHECK_BAD); do if grep -qF "$$pat" $$f; then echo "  BAD     Linux reported $$pat"; rc=1; fi; done; \
	if [ $$rc -eq 0 ]; then echo "mem-r2: PASS"; else echo "mem-r2: FAIL"; fi; exit $$rc

# E8 and E11 on two virtual CPUs: lockless copies against concurrent unmaps,
# a contended cursor whose holder sleeps in vm_map (the test hook), and a
# process that exits under a copy into its memory.
mem-conc:
	$(MAKE) mem-boot MEM_VCPUS=2 MEM_ARGS="mode=conc dur=3000" \
	  MEM_MODPARAMS="klet_test_hooks=1" MEM_LOG=conc
	@$(MAKE) --no-print-directory check-mem-log MEM_LOG=conc

# E11's second half, and the carriers as Linux tasks: vCPU 1's carrier of a
# two-thread process is preempted (a competitor on its processor), sent
# SIGTERM and SIGUSR1 (ignored: it must live), stopped and continued, and
# killed, while vCPU 0's tenant thread faults in the same address space. The
# kill must end the whole sandbox cleanly. All the while vCPU 1's tenant runs
# the rewind check: its register count and its memory count must never part.
mem-kill:
	$(MAKE) mem-boot MEM_VCPUS=2 MEM_ARGS="mode=kill dur=20000" MEM_RUNMODE=kill MEM_LOG=kill
	@$(MAKE) --no-print-directory check-mem-kill

check-mem-kill:
	@f=$(MEM_LOGDIR)/kill.log; rc=0; \
	sed 's/\r$$//' $$f | grep -E 'MEM-CHECK|MEM-REWIND|RUN-MEM|lifeline closed|sandbox is dying|evicting' | tail -n 24; \
	if grep -q 'MEM-CHECK FAIL' $$f; then echo "  BAD     a check failed"; rc=1; fi; \
	n=$$(grep -ao 'MEM-REWIND checkpoints=[0-9]* rewinds=[0-9]*' $$f | tail -1); \
	cp=$$(echo "$$n" | sed 's/.*checkpoints=\([0-9]*\).*/\1/'); \
	rw=$$(echo "$$n" | sed 's/.*rewinds=//'); \
	if [ "$${cp:-0}" -ge 1000 ] && [ "$${rw:-1}" = 0 ]; then \
	  echo "  ok      the rewind check made $$cp checkpoints across the preemption, the signals and the stop, and none found the tenant's registers put back"; \
	else echo "  BAD     the rewind check: $${n:-no report}"; rc=1; fi; \
	for pat in 'RUN-MEM: preempted the carrier of vcpu 1' \
	           'is alive (state ' 'the root carrier alive' \
	           'MEM-KILL survivor rounds=' \
	           'lifeline closed, the sandbox is dying' \
	           'a carrier is gone, the sandbox is dying' \
	           'RUN-MEM: no carrier left (module references: 0)' 'INIT: done'; do \
	  if grep -qF "$$pat" $$f; then echo "  ok      $$pat"; else echo "  MISSING $$pat"; rc=1; fi; \
	done; \
	if grep -q 'vcpu 1 carrier state [RS], after SIGSTOP T, after SIGCONT [RS]' $$f; then \
	  echo "  ok      SIGSTOP stopped the carrier of vcpu 1 (state T) and SIGCONT let it go on"; \
	else echo "  BAD     the carrier of vcpu 1 did not stop and go on"; rc=1; fi; \
	if grep -q 'root carrier (pid [0-9]*) lifeline closed' $$f; then echo "  ok      the root carrier died"; \
	else echo "  MISSING the root carrier's death"; rc=1; fi; \
	if grep -qF 'MEM-DONE' $$f; then echo "  BAD     the sandbox outlived the kill of a carrier"; rc=1; fi; \
	if grep -qF 'delete_module kernelet failed' $$f; then echo "  BAD     unclean module unload"; rc=1; \
	else echo "  ok      clean module unload"; fi; \
	for pat in $(CHECK_BAD); do \
	  if grep -qF "$$pat" $$f; then echo "  BAD     the log contains $$pat"; grep -nF "$$pat" $$f | head -3; rc=1; \
	  else echo "  ok      no $$pat"; fi; \
	done; \
	if [ $$rc -eq 0 ]; then echo "kill: PASS"; else echo "kill: FAIL"; fi; exit $$rc

# E7: the area's entries survive reclaim. A 512 MiB sparse swap file on a
# virtio disk; the hog in run-mem pushes the guest into swap.
$(SWAP_IMG):
	mkdir -p $(MEM_LOGDIR)
	truncate -s 512M $@
	mkswap $@ >/dev/null

mem-pressure: $(SWAP_IMG)
	$(MAKE) mem-boot MEM_ARGS="mode=pressure wait_ms=30000" MEM_RUNMODE=pressure \
	  MEM_LOG=pressure QEMU_EXTRA="-drive file=$(SWAP_IMG),if=virtio,format=raw"
	@$(MAKE) --no-print-directory check-mem-log MEM_LOG=pressure

# E6 and E9: five boots, the medians of the per-boot medians.
MEM_PERF_BOOTS ?= 5
mem-perf:
	mkdir -p $(MEM_LOGDIR)
	rm -f $(MEM_LOGDIR)/perf-*.log
	@for i in $$(seq 1 $(MEM_PERF_BOOTS)); do \
	  $(MAKE) mem-boot MEM_ARGS="mode=perf rounds=8 rounds9=3" MEM_LOG=perf-$$i MEM_TIMEOUT=300 >/dev/null 2>&1; \
	  echo "  boot perf-$$i done"; \
	done
	@$(MAKE) --no-print-directory check-mem-perf

check-mem-perf:
	@fail=0; for f in $(MEM_LOGDIR)/perf-*.log; do \
	  b=$$(basename $$f .log); \
	  if $(MAKE) --no-print-directory check-mem-log MEM_LOG=$$b >/dev/null 2>&1; then \
	    echo "  ok      boot $$b"; \
	  else echo "  BAD     boot $$b failed its checks"; fail=$$((fail+1)); fi; \
	done; \
	python3 bench/mem-perf.py $(MEM_LOGDIR) || fail=$$((fail+1)); \
	if [ $$fail -eq 0 ]; then echo "make mem-perf: PASS"; else echo "make mem-perf: FAIL ($$fail)"; exit 1; fi

mem: mem-func mem-r2 mem-conc mem-kill mem-pressure mem-perf

# --- boot ---------------------------------------------------------------

# Only builds the kernel if the image is not there at all; an existing
# bzImage is left alone.
$(BZIMAGE):
	$(MAKE) linux

run: $(BZIMAGE) $(INITRAMFS)
	rm -f $(SERIAL)
	@echo "booting (timeout $(TIMEOUT)s), serial -> $(SERIAL)"
	timeout $(TIMEOUT) $(QEMU) \
	  -enable-kvm -cpu host -smp 2 -m 512M \
	  -nographic -no-reboot -monitor none \
	  -kernel $(BZIMAGE) -initrd $(INITRAMFS) \
	  -append "$(KERNEL_CMDLINE)" \
	  -serial file:$(SERIAL) $(QEMU_EXTRA) </dev/null; \
	  rc=$$?; echo "qemu exit status: $$rc"; exit $$rc

# --- the whole prototype ------------------------------------------------

hello:
	$(MAKE) KLET_KERNEL=hello linux stage-hello initramfs
	-$(MAKE) run
	-cp $(SERIAL) $(BUILD)/serial-hello.log
	@$(MAKE) --no-print-directory check-log

probe:
	$(MAKE) KLET_KERNEL=probe linux stage-probe initramfs
	-$(MAKE) run
	-cp $(SERIAL) $(BUILD)/serial-probe.log
	@$(MAKE) --no-print-directory check-probe-log

# Two boots, both with preempt=none so that Linux will not preempt kernel code:
# first the control with the watch timer off, then the real run with it on.
YIELD_CMDLINE := console=ttyS0 panic=-1 preempt=none rcupdate.rcu_cpu_stall_timeout=3
YIELD_OFF_LOG := $(BUILD)/serial-yield-off.log

yield:
	$(MAKE) KLET_KERNEL=yieldk linux
	$(MAKE) KLET_KERNEL=yieldk WATCH=0 stage-yield initramfs
	-$(MAKE) run KERNEL_CMDLINE="$(YIELD_CMDLINE)" TIMEOUT=180
	cp $(SERIAL) $(YIELD_OFF_LOG)
	$(MAKE) KLET_KERNEL=yieldk WATCH=1 stage-yield initramfs
	-$(MAKE) run KERNEL_CMDLINE="$(YIELD_CMDLINE)" TIMEOUT=180
	-cp $(SERIAL) $(BUILD)/serial-yield-on.log
	@$(MAKE) --no-print-directory check-yield-log

# Everything the log must contain, and everything it must not.
CHECK_BAD := 'BUG:' 'Oops' 'WARNING:' 'Call Trace' 'switching to a task already running'

# The control boot (tick off) is expected to starve the competitor, so it is
# reported rather than asserted; the real boot (tick on) is asserted.
check-yield-log:
	@test -f $(YIELD_OFF_LOG) || { echo "check-log: no $(YIELD_OFF_LOG)"; exit 1; }
	@test -f $(SERIAL) || { echo "check-log: no $(SERIAL)"; exit 1; }
	@echo "=== control boot: preempt=none, watch timer OFF ================="
	@sed -n '/INIT: loading kernelet.ko/,$$p' $(YIELD_OFF_LOG) | sed 's/\r$$//'
	@echo "=== real boot: preempt=none, watch timer ON ====================="
	@sed -n '/INIT: loading kernelet.ko/,$$p' $(SERIAL) | sed 's/\r$$//'
	@echo "================================================================"
	@echo "--- the two checksums -------------------------------------------"
	@grep -ho 'yield: checksum 0x[0-9a-f]*' $(YIELD_OFF_LOG) $(SERIAL) | sed 's/^/  kernelet  /'
	@grep -ho 'competitor reference checksum 0x[0-9a-f]*' $(YIELD_OFF_LOG) $(SERIAL) | sed 's/^/  reference /'
	@rc=0; \
	off=$$(grep -ho 'yield: checksum 0x[0-9a-f]*' $(YIELD_OFF_LOG) | head -1 | sed 's/.*0x//'); \
	on=$$(grep -ho 'yield: checksum 0x[0-9a-f]*' $(SERIAL) | head -1 | sed 's/.*0x//'); \
	ref=$$(grep -ho 'competitor reference checksum 0x[0-9a-f]*' $(SERIAL) | head -1 | sed 's/.*0x//'); \
	test -n "$$on" && echo "  ok      the kernelet computed a checksum with the watch on" || \
	  { echo "  MISSING the kernelet's checksum with the watch on"; rc=1; }; \
	if [ -n "$$on" ] && [ "$$on" = "$$off" ]; then \
	  echo "  ok      checksum identical with the watch on and off ($$on)"; \
	else echo "  BAD     checksum differs: watch on $$on, watch off $$off"; rc=1; fi; \
	if [ -n "$$on" ] && [ "$$on" = "$$ref" ]; then \
	  echo "  ok      checksum identical to the user-space reference ($$ref)"; \
	else echo "  BAD     checksum differs from the reference: $$on vs $$ref"; rc=1; fi; \
	y=$$(grep -o '[0-9]* voluntary yield(s)' $(SERIAL) | tail -1 | sed 's/ .*//'); \
	u=$$(grep -o '[0-9]* upcall(s)' $(SERIAL) | tail -1 | sed 's/ .*//'); \
	if [ -n "$$y" ] && [ "$$y" -ge 100 ]; then \
	  echo "  ok      the kernelet gave the processor back $$y time(s), after $$u virtual-interrupt upcall(s)"; \
	else echo "  BAD     the kernelet gave the processor back only $${y:-0} time(s)"; rc=1; fi; \
	yoff=$$(grep -o '[0-9]* voluntary yield(s)' $(YIELD_OFF_LOG) | tail -1 | sed 's/ .*//'); \
	uoff=$$(grep -o '[0-9]* upcall(s)' $(YIELD_OFF_LOG) | tail -1 | sed 's/ .*//'); \
	if [ "$${uoff:-0}" -eq 0 ] && [ "$${yoff:-0}" -le 5 ]; then \
	  echo "  ok      the control boot took 0 upcalls and yielded only $${yoff:-0} time(s), during setup"; \
	else echo "  BAD     the control boot yielded $$yoff times and took $$uoff upcalls"; rc=1; fi; \
	gon=$$(sed 's/\r$$//' $(SERIAL) | grep -o 'competitor progress .* at t+[0-9]*ms' | sed 's/.*t+//;s/ms//' | awk 'NR>1{d=$$1-p; if(d>m)m=d} {p=$$1} END{print m+0}'); \
	goff=$$(sed 's/\r$$//' $(YIELD_OFF_LOG) | grep -o 'competitor progress .* at t+[0-9]*ms' | sed 's/.*t+//;s/ms//' | awk 'NR>1{d=$$1-p; if(d>m)m=d} {p=$$1} END{print m+0}'); \
	echo "  info    longest gap between the competitor's reports: $${gon}ms with the watch on, $${goff}ms with it off"; \
	if [ "$${gon:-99999}" -lt 1000 ]; then \
	  echo "  ok      the competitor never stalled for a second with the watch on"; \
	else echo "  BAD     the competitor stalled for $${gon}ms with the watch on"; rc=1; fi; \
	if [ "$${goff:-0}" -ge 1000 ]; then \
	  echo "  ok      the competitor stalled for $${goff}ms with the watch off (the control)"; \
	else echo "  BAD     the control did not starve the competitor ($${goff}ms)"; rc=1; fi; \
	son=$$(grep -c 'rcu:.*stall' $(SERIAL) || true); \
	soff=$$(grep -c 'rcu:.*stall' $(YIELD_OFF_LOG) || true); \
	echo "  info    RCU stall reports: $$son with the watch on, $$soff with it off"; \
	if [ "$$son" -eq 0 ]; then echo "  ok      no RCU stall with the watch on"; \
	else echo "  BAD     RCU stalled with the watch on"; rc=1; fi; \
	for pat in 'INIT: unloading kernelet' 'INIT: done'; do \
	  if grep -qF "$$pat" $(SERIAL); then echo "  ok      $$pat"; \
	  else echo "  MISSING $$pat"; rc=1; fi; \
	done; \
	if grep -qF 'delete_module kernelet failed' $(SERIAL); then \
	  echo "  BAD     the module did not unload cleanly"; rc=1; \
	else echo "  ok      clean module unload"; fi; \
	for pat in $(CHECK_BAD); do \
	  if grep -qF "$$pat" $(SERIAL); then \
	    echo "  BAD     the log contains $$pat"; \
	    grep -nF "$$pat" $(SERIAL) | head -3; rc=1; \
	  else echo "  ok      no $$pat"; fi; \
	done; \
	if [ $$rc -eq 0 ]; then echo "make yield: PASS"; else echo "make yield: FAIL"; fi; \
	exit $$rc

check-probe-log:
	@test -f $(SERIAL) || { echo "check-log: no $(SERIAL)"; exit 1; }
	@echo "--- serial log, from the module load to the end -----------------"
	@sed -n '/INIT: loading kernelet.ko/,$$p' $(SERIAL) | sed 's/\r$$//'
	@echo "----------------------------------------------------------------"
	@rc=0; \
	for pat in 'probe: demand paging: read back "PROBE-OK"' \
	           'probe: illegal instruction at' \
	           'probe: breakpoint before' \
	           'probe: spinning inside the kernelet at depth 0' \
	           'kernelet: evicting vcpu carrier' \
	           'INIT: unloading kernelet' 'INIT: done'; do \
	  if grep -qF "$$pat" $(SERIAL); then echo "  ok      $$pat"; \
	  else echo "  MISSING $$pat"; rc=1; fi; \
	done; \
	if grep -qF 'delete_module kernelet failed' $(SERIAL); then \
	  echo "  BAD     the module did not unload cleanly"; rc=1; \
	else echo "  ok      clean module unload"; fi; \
	for pat in $(CHECK_BAD); do \
	  if grep -qF "$$pat" $(SERIAL); then \
	    echo "  BAD     the log contains $$pat"; \
	    grep -nF "$$pat" $(SERIAL) | head -3; rc=1; \
	  else echo "  ok      no $$pat"; fi; \
	done; \
	if [ $$rc -eq 0 ]; then echo "make probe: PASS"; else echo "make probe: FAIL"; fi; \
	exit $$rc

check-log:
	@test -f $(SERIAL) || { echo "check-log: no $(SERIAL)"; exit 1; }
	@echo "--- serial log, from the module load to the end -----------------"
	@sed -n '/INIT: loading kernelet.ko/,$$p' $(SERIAL) | sed 's/\r$$//'
	@echo "----------------------------------------------------------------"
	@rc=0; \
	stub=$$(grep -o 'service stub: [0-9]* cycles through the stack switch, [0-9]* for the service body alone' $(SERIAL) | head -1); \
	if [ -n "$$stub" ]; then echo "  ok      $$stub"; \
	else echo "  MISSING the service stub measurement"; rc=1; fi; \
	for pat in 'Hello, world' 'kernelet: stopped, exit code 0' \
	           'INIT: unloading kernelet' 'INIT: done'; do \
	  if grep -qF "$$pat" $(SERIAL); then echo "  ok      $$pat"; \
	  else echo "  MISSING $$pat"; rc=1; fi; \
	done; \
	if grep -qF 'delete_module kernelet failed' $(SERIAL); then \
	  echo "  BAD     the module did not unload cleanly"; rc=1; \
	else echo "  ok      clean module unload"; fi; \
	for pat in $(CHECK_BAD); do \
	  if grep -qF "$$pat" $(SERIAL); then \
	    echo "  BAD     the log contains $$pat"; \
	    grep -nF "$$pat" $(SERIAL) | head -3; rc=1; \
	  else echo "  ok      no $$pat"; fi; \
	done; \
	if [ $$rc -eq 0 ]; then echo "make hello: PASS"; else echo "make hello: FAIL"; fi; \
	exit $$rc

# --- cleaning -----------------------------------------------------------

clean:
	rm -rf $(STAGE) $(INIT) $(INITRAMFS) $(SERIAL)
	-$(KBUILD) M=$(CURDIR)/endovisor clean
	rm -f $(IMAGE) $(HELLO_ELF) $(PROBE_ELF) $(YIELD_ELF) $(SCHED_ELF) $(CURDIR)/mem/mem $(RUNTIME)
	rm -f $(BUILD)/run-probe $(BUILD)/run-yield $(BUILD)/run-sched $(BUILD)/run-mem
	rm -f $(BUILD)/image_start.o $(BUILD)/image_end.o $(INITRAMFS_LIST)
	rm -f $(BUILD)/*.log $(BUILD)/*.out
	rm -rf $(CARGO_DIR) $(MEM_LOGDIR) $(BENCH_OUT) $(BUILD)/loops

# Also throws away the configured and built kernel.
distclean: clean
	-$(KBUILD) mrproper
