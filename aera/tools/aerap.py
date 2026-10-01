#!/usr/bin/env python3
"""Unpack and repack `.aerap` packages (flutter-aera spec/aerap.md).

    aerap.py unpack PKG.aerap DIR          # DIR/plugin.json + DIR/root/...
    aerap.py pack DIR OUT.aerap            # recomputes sizes and hashes
    aerap.py retarget PKG.aerap KIT OUT.aerap
        # keep the app (usr/share/flutter/flutter_assets, usr/lib/libapp.so),
        # take everything else from an extracted kit tree (e.g. the x64 kit)

Stream layout as AERA's reader (aeraui/features/browser/runtime.cpp@abf3316):
header, then per member u16 name length, u16 mode (0 = alias), u64 size,
name, zero padding to a 4-byte stream offset, body (no padding after).
Packing writes plain LZMA2 with a CRC32 check and no BCJ filter, which every
xz decoder accepts whatever BCJ filters it was built with.
"""
import hashlib, io, json, lzma, os, shutil, struct, subprocess, sys, zipfile
from pathlib import Path

MAGIC = b"AERAWEB1"
APP = ("usr/share/flutter/flutter_assets/", "usr/lib/libapp.so")


def read_stream(data, member_relative=False):
    """AERA pads the name to a 4-byte *stream* offset. member_relative=True
    reads streams padded to a multiple of 4 from the member header instead
    (what flutter_p0g wrote on 2026-10-01; AERA rejects those once a body
    size is not a multiple of 4)."""
    if data[:8] != MAGIC:
        raise ValueError("not an AERAWEB1 stream")
    (count,) = struct.unpack_from("<I", data, 8)
    off, out = 12, []
    for i in range(count):
        start = off
        nlen, mode, size = struct.unpack_from("<HHQ", data, off); off += 12
        if not 0 < nlen < 240 or mode not in (0, 0o644, 0o755) or size > 100 << 20:
            raise ValueError(f"member {i} at {start}: bad header")
        name = data[off:off + nlen].decode(); off += nlen
        pad = (-(off - start) if member_relative else -off) % 4
        if data[off:off + pad].strip(b"\0"):
            raise ValueError(f"member {i} ({name}): non-zero padding")
        off += pad
        out.append((name, mode, data[off:off + size])); off += size
    if off != len(data):
        raise ValueError(f"trailing bytes in stream: {len(data) - off}")
    return out


def write_stream(members):
    b = io.BytesIO(); b.write(MAGIC); b.write(struct.pack("<I", len(members)))
    for name, mode, body in members:
        n = name.encode()
        b.write(struct.pack("<HHQ", len(n), mode, len(body))); b.write(n)
        b.write(b"\0" * ((-b.tell()) % 4)); b.write(body)
    return b.getvalue()


def load(pkg):
    with zipfile.ZipFile(pkg) as z:
        manifest = json.loads(z.read("plugin.json"))
        xz = z.read("runtime.xz")
    # liblzma via the xz CLI: Python's lzma may lack the ARM64 BCJ filter.
    raw = subprocess.run(["xz", "-dc"], input=xz, capture_output=True, check=True).stdout
    try:
        return manifest, read_stream(raw)
    except ValueError as e:
        members = read_stream(raw, member_relative=True)
        print(f"warning: {pkg} is not readable by AERA ({e}); "
              "read it with member-relative padding", file=sys.stderr)
        return manifest, members


def save(manifest, members, out):
    members = sorted(members, key=lambda m: m[0])
    raw = write_stream(members)
    xz = lzma.compress(raw, format=lzma.FORMAT_XZ, check=lzma.CHECK_CRC32,
                       filters=[{"id": lzma.FILTER_LZMA2, "preset": 9}])
    m = dict(manifest)
    m.update(payload_size=len(xz), payload_sha256=hashlib.sha256(xz).hexdigest(),
             expanded_size=len(raw), expanded_sha256=hashlib.sha256(raw).hexdigest(),
             member_count=len(members))
    with zipfile.ZipFile(out, "w", zipfile.ZIP_STORED) as z:
        z.writestr("plugin.json", json.dumps(m, indent=2) + "\n")
        z.writestr("runtime.xz", xz)
    Path(str(out) + ".json").write_text(json.dumps(m, indent=2) + "\n")
    print(f"{out}: {len(members)} members, {len(raw)/1e6:.1f} MB expanded, {len(xz)/1e6:.1f} MB xz")


def tree_members(root):
    root = Path(root)
    return [(p.relative_to(root).as_posix(), 0o755 if os.access(p, os.X_OK) else 0o644, p.read_bytes())
            for p in sorted(root.rglob("*")) if p.is_file()]


def main():
    cmd, *a = sys.argv[1:] or ["-h"]
    if cmd == "unpack":
        manifest, members = load(a[0]); d = Path(a[1])
        (d / "root").mkdir(parents=True, exist_ok=True)
        (d / "plugin.json").write_text(json.dumps(manifest, indent=2) + "\n")
        for name, mode, body in members:  # mode 0: alias (hard link) to another member
            p = d / "root" / name; p.parent.mkdir(parents=True, exist_ok=True)
            if mode == 0:
                continue
            p.write_bytes(body); p.chmod(mode)
        for name, mode, body in members:
            if mode == 0:
                os.link(d / "root" / body.decode(), d / "root" / name)
        print(f"{len(members)} members -> {d}/root")
    elif cmd == "pack":
        d = Path(a[0]); save(json.loads((d / "plugin.json").read_text()), tree_members(d / "root"), a[1])
    elif cmd == "retarget":
        manifest, members = load(a[0])
        app = [m for m in members if m[0].startswith(APP[0]) or m[0] == APP[1]]
        kit = [m for m in tree_members(a[1]) if m[0] != "kit.json" and not m[0].startswith(APP[0])]
        print(f"app {len(app)} members, kit {len(kit)} members")
        save(manifest, kit + app, a[2])
    else:
        print(__doc__); sys.exit(0 if cmd in ("-h", "--help") else 2)


if __name__ == "__main__":
    main()
