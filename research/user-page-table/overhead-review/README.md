# Kernelet implementation review

The current review covers the Asterinas-based Kernelet implementation in `poc/`: Endovisor, vOSTD, kernel adaptations, OSDK, and experiment tools, together with its Linux carrier patch. The separate teaching kernels in `prototype/` remain the book's reference implementation; their earlier behavior is not evidence about this image.

The implementation follows the user-confirmed [D1–D7 decisions](decisions.md). The [current design and validation record](syscall-path-validation/README.md) describes ownership, removed work, remaining costs, exact artifacts, and actual checks. Performance gains are not inferred from source deletions or correctness tests.

## Current evidence

- [2026-11-17 syscall measurements and source changes](../results/syscall-2026-11-17/README.md): matched Linux/Kernelet inputs, mitigation controls, preserved Asterinas interfaces, raw samples, and attribution limits.
- [Host lifecycle and loader review](syscall-path-validation/lifecycle-review.md).
- [Experiment input, result, and dependency review](syscall-path-validation/eval-review.md).
- [Current image builds and QEMU results](syscall-path-validation/).
- [Fixed event handlers](direct-handler-validation/README.md), [CPU-local access](cpu-local-validation/README.md), and [cold panic reporting](panic-cold-validation/README.md): earlier implementation-specific evidence, with their original input identities and limits.

## Source audit snapshots

These records describe their stated snapshots and preserve the original attribution analysis. Their proposed changes and old names are not descriptions of the current implementation.

- [Combined source audit](source-audit-2026-11-16.md).
- [Linux and Endovisor](linux-endovisor.md).
- [vOSTD and POSIX events](event-dispatch.md).
- [Memory and lifecycle](memory-lifecycle.md).
