# Building Kernelets on Linux

This directory contains the mdBook source and its tooling. Start reading at
[How to read this book](src/README.md).

The book has two parts: **Accepted Design** describes the endorsed design and
the companion implementation in `../prototype/`; **Design Proposals** holds
ideas under discussion and the record of their review. To contribute an idea,
read the [proposal guide](src/design-proposals/README.md) and copy the
[template](src/design-proposals/template.md) into a dated proposal file.

| Path | Contents |
|---|---|
| `book.toml` | Book title, build settings, and preprocessors |
| `src/README.md`, `src/SUMMARY.md` | Introduction and table of contents |
| `src/accepted-design/` | The accepted design and implementation chapters |
| `src/design-proposals/` | Proposal guide, template, and dated proposals |
| `assets/` | Styles and diagram rendering scripts |
| `tools/` | Source checker and browser renderer |
| `tmp.md` | Existing working notes, outside the published book |
| `build/` | Generated HTML, ignored by Git |

Run these commands from this directory:

```sh
make check
make build
make serve
make render PAGE=accepted-design/carrier-hooks.html OUT=/tmp/carrier-hooks.png
```

The build needs `mdbook` and `mdbook-mermaid`; rendering also needs a headless
Chrome browser. The repository's root Makefile delegates the same book commands
here. `make clean` removes generated HTML and renderer output, keeping the book's
source and the prototype intact.
