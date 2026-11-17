#!/usr/bin/env python3
"""Pack a Host API 2 `.aerap` from an extracted flutter-aera kit and a debug
Flutter bundle (flutter-aera upstream-host-api-2, spec/aerap.md).

    aerap_api2.py KIT_DIR FLUTTER_ASSETS OUT.aerap --id ID --name NAME \\
        --payload-url https://... [--version 1.0.0] [--description TEXT]

KIT_DIR is the kit tarball extracted as is (kit.json at its root, which is
not packed); FLUTTER_ASSETS is `flutter build bundle --debug`'s output and
becomes usr/share/flutter/flutter_assets. The manifest carries exactly the
API 2 values the spec fixes (schema 1, ui-runtime/main, usr/bin/aera-plugin,
min_host_api and protocol_version 2, display, touch-input, desktop-surface);
the payload fields are computed by aerap.py's packer, whose stream layout
matches AERA's reader. Every limit the spec states is checked before writing.
"""
import argparse, re, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import aerap  # noqa: E402

ASSETS = "usr/share/flutter/flutter_assets/"
LAUNCHER = "usr/bin/aera-plugin"
PERMISSIONS = ["display", "touch-input", "desktop-surface"]
MAX_MEMBERS = 4096
MAX_BYTES = 512 << 20


def fail(msg):
    sys.exit(f"aerap_api2: {msg}")


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("kit", type=Path)
    p.add_argument("assets", type=Path)
    p.add_argument("out", type=Path)
    p.add_argument("--id", required=True)
    p.add_argument("--name", required=True)
    p.add_argument("--version", default="1.0.0")
    p.add_argument("--description", default="A Flutter app for AERA Recovery.")
    p.add_argument("--icon", default="plugin")
    p.add_argument("--payload-url", required=True)
    a = p.parse_args()

    if a.id == "browser" or not re.fullmatch(r"[a-z0-9-](?:[a-z0-9.-]{0,62}[a-z0-9-])?", a.id):
        fail(f"id {a.id!r}: 1-64 of [a-z0-9.-], not starting or ending with '.', never 'browser'")
    for field, value, limit in (("name", a.name, 80), ("description", a.description, 320),
                                ("version", a.version, 32), ("icon", a.icon, 24)):
        if not 0 < len(value) <= limit:
            fail(f"{field} must be 1-{limit} characters, got {len(value)}")
    if not a.payload_url.startswith("https://"):
        fail(f"payload_url must be https, got {a.payload_url!r}")
    if not (a.kit / "kit.json").is_file():
        fail(f"{a.kit}: no kit.json; pass the kit tarball extracted as is")
    if not (a.assets / "kernel_blob.bin").is_file():
        fail(f"{a.assets}: no kernel_blob.bin; the kit is debug (JIT) and needs a debug bundle")

    kit = [m for m in aerap.tree_members(a.kit) if m[0] != "kit.json"]
    if any(name.startswith(ASSETS) or name == "usr/lib/libapp.so" for name, _, _ in kit):
        fail(f"{a.kit}: the kit already carries an app")
    if not any(name == LAUNCHER and mode == 0o755 for name, mode, _ in kit):
        fail(f"{a.kit}: no executable {LAUNCHER}")
    app = [(ASSETS + name, mode, body) for name, mode, body in aerap.tree_members(a.assets)]
    members = kit + app
    if len(members) > MAX_MEMBERS:
        fail(f"{len(members)} members, more than {MAX_MEMBERS}")
    for name, _, body in members:
        if not 0 < len(name.encode()) <= 239:
            fail(f"member name {name!r}: 1-239 bytes")
        if len(body) > MAX_BYTES:
            fail(f"member {name}: {len(body)} bytes, more than 512 MiB")

    manifest = {
        "schema": 1, "id": a.id, "name": a.name, "version": a.version,
        "description": a.description, "icon": a.icon, "type": "ui-runtime", "entry": "main",
        "executable": LAUNCHER, "min_host_api": 2, "protocol_version": 2,
        "payload": "runtime.xz", "payload_url": a.payload_url, "permissions": PERMISSIONS,
    }
    print(f"app {len(app)} members, kit {len(kit)} members")
    aerap.save(manifest, members, a.out)
    size = a.out.stat().st_size
    m = aerap.load(a.out)[0]
    if m["payload_size"] > MAX_BYTES or m["expanded_size"] > MAX_BYTES:
        fail(f"payload {m['payload_size']} / expanded {m['expanded_size']} bytes, more than 512 MiB")
    print(f"{a.out}: {size} bytes, id {a.id}, host API 2")


if __name__ == "__main__":
    main()
