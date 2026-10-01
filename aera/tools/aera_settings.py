#!/usr/bin/env python3
"""Read and edit AERA's saved settings file (TWRP InfoManager `.aera`).

    aera_settings.py dump FILE
    aera_settings.py set FILE key=value ...   # creates FILE when missing

Layout (infomanager.cpp, as flutter-aera src/aera_settings.rs reads it):
i32 version 0x00010010, then [u16 len][name\\0][u16 len][value\\0] pairs,
little-endian on x86_64 and arm64.
"""
import struct, sys
from pathlib import Path

VERSION = 0x00010010


def read(path):
    data = Path(path).read_bytes() if Path(path).exists() else b""
    if len(data) < 4 or struct.unpack_from("<i", data)[0] != VERSION:
        return {}
    off, out = 4, {}
    def field():
        nonlocal off
        if off + 2 > len(data): return None
        (n,) = struct.unpack_from("<H", data, off); off += 2
        if n == 0 or n >= 512 or off + n > len(data): return None
        s = data[off:off + n - 1].decode("utf-8", "replace"); off += n
        return s
    while True:
        k = field()
        if k is None: break
        v = field()
        if v is None: break
        out[k] = v
    return out


def write(path, values):
    b = bytearray(struct.pack("<i", VERSION))
    for k, v in values.items():
        for s in (k, v):
            e = s.encode() + b"\0"
            b += struct.pack("<H", len(e)) + e
    Path(path).write_bytes(bytes(b))


if __name__ == "__main__":
    cmd, path, *rest = sys.argv[1:]
    values = read(path)
    if cmd == "set":
        for kv in rest:
            k, v = kv.split("=", 1)
            values[k] = v
        write(path, values)
    for k in sorted(values):
        if cmd == "dump" or any(kv.startswith(k + "=") for kv in rest):
            print(f"{k}={values[k]}")
