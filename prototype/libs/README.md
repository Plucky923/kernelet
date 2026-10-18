# libs: two crates from the Asterinas tree

Two small crates of the Asterinas tree that vOSTD and the kernels proper use,
copied **unchanged** from commit `ab9a4cfdc`, so that this repository builds on
its own:

| crate | from | used by |
|---|---|---|
| `ostd-macros/` | `ostd/libs/ostd-macros` | vOSTD: `#[ostd::main]`, the macro every kernel proper's entry point is written with |
| `align_ext/` | `ostd/libs/align_ext` | the kernels proper: `align_up` and `align_down` on integers |

Only their `Cargo.toml` files are rewritten: the originals inherit their
package keys, dependency versions and lints from the Asterinas workspace,
which this repository is not part of, so the manifests here spell out the same
values. The sources (`src/lib.rs`) are byte-identical to the tree's.

The book introduces both with the OSTD API in chapter 3 (the kernel we will
run).

## How they are built

As ordinary members of the repository's Cargo workspace (`../Cargo.toml`):
`align_ext` for the kernel's target, `ostd-macros` as a procedural macro for
the host. `make crates` downloads the crates `ostd-macros` depends on.
