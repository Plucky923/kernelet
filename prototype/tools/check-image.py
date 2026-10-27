#!/usr/bin/env python3
"""Check the restricted ELF PIE contract before an image reaches the kernel."""
import re
import struct
import sys
from pathlib import Path


def check(path):
    data = Path(path).read_bytes()
    if len(data) < 64:
        raise ValueError('truncated ELF header')
    ident, typ, machine, version, entry, phoff, shoff, flags, ehsize, phentsize, phnum, shentsize, shnum, shstrndx = struct.unpack_from('<16sHHIQQQIHHHHHH', data)
    if ident[:7] != b'\x7fELF\x02\x01\x01' or typ != 3 or machine != 62 or version != 1:
        raise ValueError('expected a little-endian x86-64 ET_DYN image')
    if ehsize != 64 or phentsize != 56 or not 1 <= phnum <= 16 or phoff + phnum * 56 > len(data):
        raise ValueError('invalid program header table')
    headers = [struct.unpack_from('<IIQQQQQQ', data, phoff + i * 56) for i in range(phnum)]
    loads, dynamic = [], []
    for kind, perm, off, va, pa, filesz, memsz, align in headers:
        if kind not in (1, 2):
            raise ValueError(f'unsupported program header {kind:#x}')
        if filesz > memsz or off + filesz > len(data):
            raise ValueError('segment outside the file or file bytes exceed memory size')
        if kind == 2:
            dynamic.append((off, va, filesz))
            continue
        if not memsz or perm not in (4, 5, 6) or align != 4096 or off % 4096 or va % 4096:
            raise ValueError('load segment must be nonempty, page aligned, and R, RX, or RW')
        if va + memsz > 16 * 1024 * 1024:
            raise ValueError('image virtual span exceeds 16 MiB')
        loads.append((va, va + memsz, off, filesz, perm))
    loads.sort()
    if len(loads) != 3 or [s[4] for s in loads] != [5, 4, 6] or loads[0][0] != 0:
        raise ValueError('expected three RX/R/RW load segments starting at virtual offset zero')
    for previous, current in zip(loads, loads[1:]):
        if (previous[1] + 4095) & ~4095 != current[0]:
            raise ValueError('load segments overlap or leave a hole')
    def segment(va, size=1, writable=None, file_backed=False):
        for lo, hi, off, filesz, perm in loads:
            limit = lo + filesz if file_backed else hi
            if lo <= va and size <= limit - va and (writable is None or bool(perm & 2) == writable):
                return off + va - lo
        raise ValueError(f'address range {va:#x}+{size:#x} is not in an allowed load segment')
    # Entry is an object, not the initial instruction pointer: ABI + three callbacks.
    entry_offset = segment(entry, 32, writable=True, file_backed=True)
    abi_header = Path(__file__).resolve().parents[1] / 'linux/endovisor/kernelet.h'
    abi_version = re.search(r'^#define\s+KLET_ABI_VERSION\s+([0-9]+)ULL\s*$', abi_header.read_text(), re.MULTILINE)
    if abi_version is None:
        raise ValueError('cannot read KLET_ABI_VERSION from kernelet.h')
    if struct.unpack_from('<Q', data, entry_offset)[0] != int(abi_version[1]):
        raise ValueError('entry table ABI version differs from the endovisor')
    if len(dynamic) != 1:
        raise ValueError('expected one dynamic table')
    off, va, size = dynamic[0]
    if size % 16 or segment(va, size, file_backed=True) != off:
        raise ValueError('invalid dynamic table mapping')
    tags = {}
    terminated = False
    for pos in range(off, off + size, 16):
        tag, val = struct.unpack_from('<qQ', data, pos)
        if tag == 0:
            terminated = True
            break
        if tag in tags:
            raise ValueError(f'duplicate dynamic tag {tag:#x}')
        tags[tag] = val
    allowed = {4, 5, 6, 7, 8, 9, 10, 11, 21, 30, 0x6ffffef5, 0x6ffffff9, 0x6ffffffb}
    if not terminated or set(tags) - allowed:
        raise ValueError(f'unterminated or unsupported dynamic tags: {set(tags) - allowed}')
    if tags.get(30, 0) != 0 or tags.get(0x6ffffffb, 0) != 0x8000000:
        raise ValueError('unsupported dynamic flags or missing DF_1_PIE')
    if tags.get(9) != 24 or tags.get(8, 0) % 24:
        raise ValueError('invalid RELA dimensions')
    count = tags.get(8, 0) // 24
    reloff = segment(tags.get(7, 0), count * 24, writable=False, file_backed=True)
    seen = set()
    relocations = {}
    for i in range(count):
        target, info, addend = struct.unpack_from('<QQq', data, reloff + i * 24)
        if info != 8:
            raise ValueError(f'relocation {i} is not symbol-free R_X86_64_RELATIVE')
        segment(target, 8, writable=True)
        segment(addend)
        if target % 8 or target in seen:
            raise ValueError('unaligned or duplicate relocation target')
        if target == entry:
            raise ValueError('relocation overwrites the entry table ABI version')
        seen.add(target)
        relocations[target] = addend
    if tags.get(0x6ffffff9, count) != count:
        raise ValueError('RELACOUNT differs from the relocation table size')
    for delta in (8, 16, 24):
        target = relocations.get(entry + delta)
        if target is None or not loads[0][0] <= target < loads[0][1]:
            raise ValueError('entry callback is not relocated into executable code')
    print(f'image: {path}: ET_DYN, {len(loads)} load segments, {count} RELATIVE relocations, {len(data)} bytes')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit('usage: check-image.py IMAGE')
    try:
        check(sys.argv[1])
    except (ValueError, struct.error, OSError) as err:
        sys.exit(f'image: {sys.argv[1]}: {err}')
