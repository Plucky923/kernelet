# Documentation conventions

## Repository and book structure

- `book/` contains the mdBook source, assets, and tools; `prototype/` contains the implementation. Shared instructions and build shortcuts stay at the repository root.
- The book is titled **Building Kernelets on Linux**. Its introduction precedes two parts: **Accepted Design** and **Design Proposals**.
- Accepted Design chapters live in `book/src/accepted-design/`. Proposed changes live in `book/src/design-proposals/`, using the guide and template there.
- Each proposal's filename starts with its original submission date: `YYYY-MM-DD-descriptive-title.md`. Its heading and table-of-contents label start with the same date followed by the title. Keep that date when revising the proposal.
- A proposal's status distinguishes discussion from acceptance. When accepted, integrate the agreed changes into Accepted Design and the prototype where applicable; retain the proposal and decision rationale as history.
- Code-caption paths such as `prototype/linux/endovisor/image.c` are relative to the repository root. Label proposed code separately from excerpts of existing implementation.
- Run book commands from `book/`, or use the root Makefile's shortcuts. Generated HTML belongs in `book/build/`, never alongside the book source.

## Background knowledge in the book

- Introduce background beyond the assumed operating-systems course and C/Rust knowledge at its first use in a background box. This applies to Linux, ELF, compilers, processor architecture, and other subjects.
- Use `<div class="background">` with blank lines around the Markdown content and before the closing `</div>`.
- Begin with a bold label in the form `**Subject: topic.**`, such as `**Linux: control groups.**` or `**ELF: relocations.**`. Use the same visual style for every subject.
- Explain the concept, the terminology used in the relevant source or format, and its relevance to the design. Keep the box focused on the knowledge needed at that point.
- Use the bold label instead of a chapter subsection heading for the background explanation. Keep the main argument and implementation requirements in the surrounding text.

## C comments

These conventions apply to all C comments in source files, headers, and
the book's C code excerpts. The basic principle is to model documentation prose on Rust documentation comments. More specifically,

- Prefer `//` to block comments, including short field annotations.
- Begin with a concise, complete summary sentence describing the documented item.
  - Short comments beside fields needn’t be complete sentences:
- Follow the summary with the details needed to understand the item.
- Group related information into paragraphs separated by an empty `//` line.
- Group related paragraphs under a section.
- Wrap identifiers, types, field names, error constants, paths, and code expressions in backticks within comments.
- Use semantic line breaks: start each sentence on a new line, and split long sentences at clause or phrase boundaries. Keep closely related words together rather than wrapping mechanically at a fixed width.
  - Limit the use of semantic line breaks in source code; documentation such as README and Markdown files do not follow semantic line breaks. 

## Ioctl definitions

Apply the general C comment conventions to every ioctl in the UAPI header
and keep the book's excerpts consistent with that header.

- Begin with a summary of the operation,
  such as “The ioctl for doing sth.”
- Document the arguments, behavior, constraints, return value, and relevant errors.
  Explain privilege requirements under `// # Security` when applicable.

## C code excerpts in the book

- Keep excerpts labeled “Unchanged” verbatim with their source, including comments. Use C code fences for C declarations, even though the comments follow Rust's style.
- Run `make check` and `make build` after updating the book and its source excerpts.
