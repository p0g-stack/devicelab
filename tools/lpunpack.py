#!/usr/bin/env python3
"""Extract one logical partition (e.g. system) from an Android 'super' image.
Usage: lpunpack.py <super.img|block device> <name> <out.img>
Reads the primary LP metadata (liblp format): geometry at 4096, metadata
header at 4096 + 2*4096; partitions and linear extents in sector units."""
import struct, sys

src, want, out = sys.argv[1:4]
f = open(src, "rb")
f.seek(4096)
magic, = struct.unpack("<I", f.read(4))
assert magic == 0x616C4467, f"no LP geometry (magic {magic:#x})"
f.seek(4096 + 2 * 4096)
hdr = f.read(256)
magic, major, minor, header_size = struct.unpack_from("<IHHI", hdr, 0)
assert magic == 0x414C5030, f"no LP metadata header (magic {magic:#x})"
desc = [struct.unpack_from("<III", hdr, 80 + 12 * i) for i in range(4)]  # partitions, extents, groups, devices
f.seek(4096 + 2 * 4096 + header_size)
tables = f.read(max(o + n * s for o, n, s in desc))
po, pn, ps = desc[0]; eo, en, es = desc[1]
extents = [struct.unpack_from("<QIQI", tables, eo + i * es) for i in range(en)]
names = []
for i in range(pn):
    raw = struct.unpack_from("<36sIIII", tables, po + i * ps)
    name = raw[0].rstrip(b"\0").decode(); first, count = raw[2], raw[3]
    names.append(name)
    if name != want:
        continue
    with open(out, "wb") as o:
        for nsec, ttype, start, _ in extents[first:first + count]:
            if ttype == 0:  # linear
                f.seek(start * 512); left = nsec * 512
                while left:
                    chunk = f.read(min(left, 1 << 22)); o.write(chunk); left -= len(chunk)
            else:  # zero
                o.write(b"\0" * nsec * 512)
    print(f"{name}: {count} extents -> {out}")
    sys.exit(0)
sys.exit(f"{want} not in {names}")
