#!/usr/bin/env python3
"""Print a core file's mapped files (NT_FILE note): start end file_offset path.

    core_maps.py CORE [PATH_SUFFIX]   # with a suffix: only the lowest start
                                       # of that file's offset-0 mapping
"""
import struct, sys

NT_FILE = 0x46494C45


def maps(path):
    d = open(path, "rb").read()
    assert d[:4] == b"\x7fELF" and d[4] == 2, "not an ELF64 core"
    phoff, = struct.unpack_from("<Q", d, 0x20)
    phentsize, phnum = struct.unpack_from("<HH", d, 0x36)
    for i in range(phnum):
        p_type, _, p_offset, _, _, p_filesz = struct.unpack_from("<IIQQQQ", d, phoff + i * phentsize)
        if p_type != 4:  # PT_NOTE
            continue
        off, end = p_offset, p_offset + p_filesz
        while off + 12 <= end:
            namesz, descsz, ntype = struct.unpack_from("<III", d, off)
            off += 12 + ((namesz + 3) & ~3)
            desc = d[off:off + descsz]
            off += (descsz + 3) & ~3
            if ntype != NT_FILE:
                continue
            count, page = struct.unpack_from("<QQ", desc, 0)
            ents = [struct.unpack_from("<QQQ", desc, 16 + 24 * k) for k in range(count)]
            names = desc[16 + 24 * count:].split(b"\0")
            for (s, e, po), n in zip(ents, names):
                yield s, e, po * page, n.decode(errors="replace")


if __name__ == "__main__":
    rows = list(maps(sys.argv[1]))
    if len(sys.argv) > 2:
        hits = [s for s, e, o, n in rows if n.endswith(sys.argv[2]) and o == 0]
        print(hex(min(hits)) if hits else "")
    else:
        for s, e, o, n in rows:
            print(f"{s:#x} {e:#x} {o:#x} {n}")
