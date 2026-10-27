#!/usr/bin/env python3
"""The book's checker. Run from the repository root: `python3 book/tools/check.py`.

It fails, with a line per problem, if:

  - a page listed in src/SUMMARY.md does not exist, or a .md file under src/ is not listed;
  - an internal link does not resolve to an existing page, or to an anchor that page has
    (an explicit `{#id}` on a heading, or mdBook's slug of the heading text);
  - an Accepted Design external link points anywhere but Linux v6.12 on elixir.bootlin.com;
  - a proposal filename, title, or table-of-contents entry lacks its submission date;
  - a code caption names a file of the companion prototype that does not exist, or an
    identifier that does not appear in that file. A caption is any line that holds a code
    span starting with `prototype/`; every other code span on that line that looks like an
    identifier (`klet_enter`, `VmSpace::new`, `vm_map()`) is looked for in the named file(s).
    Only caption lines are checked: a line beginning with `*Simplified from`, `*Unchanged from`,
    `*Unchanged:` or `*From`.

So a sentence such as

    *Simplified from `prototype/endovisor/carrier.c`: `klet_on_syscall` and `klet_enter`.*

is a promise the checker keeps: the file exists, and both names are in it.
"""

import os
import re
import sys
from datetime import date

BOOK = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(BOOK)
SRC = os.path.join(BOOK, "src")

LINK_RE = re.compile(r"(?<!!)\[([^\[\]]*)\]\(([^)\s]+)\)")
HEADING_RE = re.compile(r"^(#{1,6})\s+(.*?)\s*(?:\{#([A-Za-z0-9_-]+)\})?\s*$")
SUMMARY_ITEM_RE = re.compile(r"^\s*[-*]\s+\[([^\]]*)\]\(([^)]+)\)\s*$")
SUMMARY_PREFIX_RE = re.compile(r"^\[([^\]]*)\]\(([^)]+)\)\s*$")
CODE_SPAN_RE = re.compile(r"`([^`]+)`")
IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*(?:\(\))?$")
CAPTION_RE = re.compile(r"^\s*\*(Simplified from|Unchanged from|Unchanged:|From) ")
ALLOWED_EXTERNAL = ("https://elixir.bootlin.com/linux/v6.12/",)


def is_proposal(path):
    return path.startswith("design-proposals/") and path not in (
        "design-proposals/README.md", "design-proposals/template.md")


def slugify(text):
    text = re.sub(r"<[^>]*>", "", text).replace("`", "")
    out = []
    for ch in text.lower():
        if ch.isalnum() or ch in "-_":
            out.append(ch)
        elif ch.isspace():
            out.append("-")
    return "".join(out)


def lines_outside_fences(text):
    in_fence = False
    for i, line in enumerate(text.split("\n")):
        s = line.lstrip()
        if s.startswith("```") or s.startswith("~~~"):
            in_fence = not in_fence
            continue
        if not in_fence:
            yield i + 1, line


def headings(text):
    ids = set()
    for _, line in lines_outside_fences(text):
        m = HEADING_RE.match(line)
        if m:
            ids.add(m.group(3) or slugify(m.group(2)))
    return ids


def summary_pages():
    pages = []
    with open(os.path.join(SRC, "SUMMARY.md"), encoding="utf-8") as f:
        for line in f:
            m = SUMMARY_ITEM_RE.match(line) or SUMMARY_PREFIX_RE.match(line.strip())
            if m:
                pages.append(m.group(2))
    return pages


def main():
    problems = []
    pages = summary_pages()
    listed = set(os.path.normpath(os.path.join(SRC, p)) for p in pages)
    for p in pages:
        if not os.path.isfile(os.path.join(SRC, p)):
            problems.append(f"SUMMARY.md: {p} does not exist")
    for dirpath, _, files in os.walk(SRC):
        for fn in files:
            if fn.endswith(".md") and fn != "SUMMARY.md":
                full = os.path.normpath(os.path.join(dirpath, fn))
                if full not in listed:
                    problems.append(f"{os.path.relpath(full, ROOT)}: not listed in SUMMARY.md")

    texts = {}
    for p in pages:
        full = os.path.join(SRC, p)
        if os.path.isfile(full):
            with open(full, encoding="utf-8") as f:
                texts[full] = f.read()
    anchors = {full: headings(text) for full, text in texts.items()}

    for page in pages:
        if not is_proposal(page):
            continue
        match = re.fullmatch(r"(\d{4}-\d{2}-\d{2})-[a-z0-9]+(?:-[a-z0-9]+)*\.md", os.path.basename(page))
        if not match:
            problems.append(f"{page}: proposal filename must be YYYY-MM-DD-descriptive-title.md")
            continue
        submitted = match.group(1)
        try:
            date.fromisoformat(submitted)
        except ValueError:
            problems.append(f"{page}: invalid submission date {submitted}")
        text = texts.get(os.path.join(SRC, page), "")
        title = next((line for _, line in lines_outside_fences(text) if line.startswith("# ")), "")
        if not title.startswith(f"# {submitted} ") or not title[len(submitted) + 3:].strip():
            problems.append(f"{page}: proposal title must begin with {submitted} followed by a title")
    with open(os.path.join(SRC, "SUMMARY.md"), encoding="utf-8") as f:
        for line in f:
            match = SUMMARY_ITEM_RE.match(line) or SUMMARY_PREFIX_RE.match(line.strip())
            if match and is_proposal(match.group(2)):
                submitted = os.path.basename(match.group(2))[:10]
                if not match.group(1).startswith(submitted + " "):
                    problems.append(f"SUMMARY.md: proposal label for {match.group(2)} must begin with {submitted}")

    n_links = n_refs = n_figs = 0
    for full, text in texts.items():
        rel = os.path.relpath(full, ROOT)
        proposal_area = os.path.relpath(full, SRC).startswith("design-proposals" + os.sep)
        n_figs += text.count("```mermaid") + text.count("<svg")
        for lineno, line in lines_outside_fences(text):
            for m in LINK_RE.finditer(line):
                href = m.group(2)
                n_links += 1
                if href.startswith("http://") or href.startswith("https://"):
                    if not proposal_area and not href.startswith(ALLOWED_EXTERNAL):
                        problems.append(f"{rel}:{lineno}: external link outside Linux v6.12 on elixir: {href}")
                    continue
                if href.startswith("mailto:"):
                    problems.append(f"{rel}:{lineno}: mail link {href}")
                    continue
                path, _, anchor = href.partition("#")
                target = full if path == "" else os.path.normpath(os.path.join(os.path.dirname(full), path))
                if path and not os.path.isfile(target):
                    problems.append(f"{rel}:{lineno}: link to a missing page: {href}")
                    continue
                if path and not path.endswith(".md"):
                    problems.append(f"{rel}:{lineno}: link to a non-page: {href}")
                    continue
                if anchor and target in anchors and anchor not in anchors[target]:
                    problems.append(f"{rel}:{lineno}: no heading {anchor!r} in {os.path.relpath(target, ROOT)}")
            spans = CODE_SPAN_RE.findall(line)
            # Proposals can name files they intend to add. Only explicit source
            # captions promise that their files and identifiers already exist.
            if proposal_area and not CAPTION_RE.match(line):
                continue
            files = [s for s in spans if s.startswith("prototype/")]
            bodies = []
            for fspan in files:
                fpath = os.path.join(ROOT, fspan)
                if not os.path.exists(fpath):
                    problems.append(f"{rel}:{lineno}: no such file in the companion repo: {fspan}")
                elif os.path.isfile(fpath):
                    with open(fpath, encoding="utf-8", errors="replace") as f:
                        bodies.append(f.read())
            if not files or not CAPTION_RE.match(line):
                continue
            for s in spans:
                if s.startswith("prototype/") or not IDENT_RE.match(s):
                    continue
                n_refs += 1
                found = any(
                    all(re.search(r"\b" + re.escape(part) + r"\b", body) for part in s.rstrip("()").split("::"))
                    for body in bodies
                )
                if bodies and not found:
                    problems.append(f"{rel}:{lineno}: `{s}` is not in {' or '.join(files)}")

    # An "Unchanged" caption promises that the fenced block after it is a verbatim
    # run of lines from the one file it names (trailing whitespace aside).
    n_verbatim = 0
    for full, text in texts.items():
        rel = os.path.relpath(full, ROOT)
        tl = text.split("\n")
        for i, line in enumerate(tl):
            if not re.match(r"^\s*\*Unchanged( from|:) ", line):
                continue
            files = [s for s in CODE_SPAN_RE.findall(line) if s.startswith("prototype/")]
            if len(files) != 1:
                problems.append(f"{rel}:{i+1}: an Unchanged caption must name exactly one file")
                continue
            j = i + 1
            while j < len(tl) and not tl[j].startswith("```"):
                j += 1
            k = j + 1
            while k < len(tl) and not tl[k].startswith("```"):
                k += 1
            if j >= len(tl) or k >= len(tl):
                problems.append(f"{rel}:{i+1}: no fenced block after the Unchanged caption")
                continue
            block = [l.rstrip() for l in tl[j+1:k]]
            fpath = os.path.join(ROOT, files[0])
            if not os.path.isfile(fpath):
                continue
            with open(fpath, encoding="utf-8", errors="replace") as f:
                fl = [l.rstrip() for l in f.read().split("\n")]
            n_verbatim += 1
            if not any(fl[s:s+len(block)] == block for s in range(len(fl) - len(block) + 1)):
                problems.append(f"{rel}:{i+1}: the block after this Unchanged caption is not a verbatim run of {files[0]}")

    for p in problems:
        print(p)
    print(f"check: {len(pages)} pages, {n_links} links, {n_refs} code references checked, {n_verbatim} verbatim blocks, {n_figs} figures")
    if problems:
        print(f"check: FAILED with {len(problems)} problem(s)")
        return 1
    print("check: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
