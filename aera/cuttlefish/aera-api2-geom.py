#!/usr/bin/env python3
"""Screen geometry for aera-api2-check.sh, derived from the recovery source
(AERA-Recovery android_bootable_recovery 1cabc509 + p0g recovery d80a712) and
from the real capture/panel sizes of the booted image.

Coordinate spaces:
  panel    physical framebuffer pixels: /tmp/aeraui.png pixels and AERA
           Remote /api/input/touch coordinates (its uinput axes are
           gr_fb_width/height, aera_remote/input.cpp)
  logical  AERA's LVGL canvas (DisplayTransform: adaptive logical size,
           touch is mapped physical -> logical per axis)
  visible  logical, turned the way the user sees it (engine.cpp SetPointer:
           rotation 90 = software landscape, 270 = GPU landscape)
  view     panel pixels turned upright (the *-view.png captures); manual
           overrides (API2_*_TAP) are given in these pixels
  guest    the plugin's desktop frame (960x540 unless API2_FRAME)

Usage: aera-api2-geom.py COMMAND GEOMETRY.json ...
  init GEOM PNG LOGICAL          LOGICAL "WxH", or "" for the adaptive default
  set GEOM key=value...
  tap GEOM home|guest X Y|toolbar esc|key CHAR|pick-row INDEX|view X Y
                                 prints "PANEL_X PANEL_Y VIEW_X VIEW_Y"
  desktop GEOM                   prints the guest rectangle (view and panel)
  view GEOM IN.png OUT.png [VX,VY ...]   upright copy with tap crosshairs
  differ GEOM A.png B.png        exit 0 when the guest rectangle differs
  detect GEOM PNG                bright-rectangle detection, for comparison
"""
import json
import struct
import sys

# generic_plugin_scene / plugin_desktop.cpp: virtual input layout and toolbar.
VIRTUAL_W, VIRTUAL_H = 960, 540
TOOLBAR = {"exit": (40, 32), "menu": (130, 32), "esc": (240, 32),
           "keys": (345, 32), "enter": (445, 32), "tab": (535, 32)}
# home_scene.cpp FileListLayout(): (row_height, row_pitch) per interface size.
FILE_ROWS = {"small": (150, 156), "normal": (174, 180),
             "large": (228, 236), "spacious": (264, 272)}
# phone_keyboard.hpp lower-case maps, (label, width units) per row.
_R0 = [(c, 1) for c in "1234567890"]
_R4 = [("?123", 2), (",", 1), (" ", 8), (".", 1), ("OK", 2)]
KEYBOARDS = {
    "qwerty": [_R0, [(c, 1) for c in "qwertyuiop"],
               [("", 1)] + [(c, 2) for c in "asdfghjkl"] + [("", 1)],
               [("SHIFT", 2)] + [(c, 1) for c in "zxcvbnm"] + [("BKSP", 2)], _R4],
    "qwertz": [_R0, [(c, 1) for c in "qwertzuiop"],
               [("", 1)] + [(c, 2) for c in "asdfghjkl"] + [("", 1)],
               [("SHIFT", 2)] + [(c, 1) for c in "yxcvbnm"] + [("BKSP", 2)], _R4],
    "azerty": [_R0, [(c, 1) for c in "azertyuiop"],
               [(c, 2) for c in "qsdfghjklm"],
               [("SHIFT", 2)] + [(c, 1) for c in "wxcvbn"] + [("BKSP", 2)], _R4],
}


def die(msg):
    sys.stderr.write(f"aera-api2-geom: {msg}\n")
    sys.exit(2)


def load(path):
    with open(path) as f:
        return json.load(f)


def save(path, g):
    with open(path, "w") as f:
        json.dump(g, f, indent=1, sort_keys=True)
        f.write("\n")


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        die(f"{path} is not a PNG")
    return struct.unpack(">II", head[16:24])


def visible_logical(g):
    return (g["lw"], g["lh"]) if g["rotation"] == 0 else (g["lh"], g["lw"])


def to_panel(g, x, y):
    """visible logical -> panel (inverse of SetPointer + DisplayTransform)."""
    r, lw, lh = g["rotation"], g["lw"], g["lh"]
    if r == 0:
        lx, ly = x, y
    elif r == 90:
        lx, ly = y, lh - 1 - x
    elif r == 270:
        lx, ly = lw - 1 - y, x
    else:
        die(f"rotation {r} is not 0, 90 or 270")
    return (round(lx * (g["pw"] - 1) / (lw - 1)), round(ly * (g["ph"] - 1) / (lh - 1)))


def panel_to_view(g, px, py):
    r = g["rotation"]
    if r == 0:
        return px, py
    if r == 90:
        return g["ph"] - 1 - py, px
    return py, g["pw"] - 1 - px


def view_to_panel(g, vx, vy):
    r = g["rotation"]
    if r == 0:
        return vx, vy
    if r == 90:
        return vy, g["ph"] - 1 - vx
    return g["pw"] - 1 - vy, vx


def desktop(g):
    """OpenPluginDesktop(): the frame scaled to fit the screen, centred."""
    sw, sh = visible_logical(g)
    fw, fh = g["frame_w"], g["frame_h"]
    scale = min(sw * 256 // fw, sh * 256 // fh)
    w, h = fw * scale // 256, fh * scale // 256
    return (sw - w) // 2, (sh - h) // 2, w, h


def virtual_to_visible(g, vx, vy):
    """Centre of the visible pixel run that PluginDesktopHandlePointer maps to vx,vy."""
    left, top, w, h = desktop(g)
    if not (0 <= vx < VIRTUAL_W and 0 <= vy < VIRTUAL_H):
        die(f"virtual {vx},{vy} outside {VIRTUAL_W}x{VIRTUAL_H}")
    return left + (2 * vx + 1) * w // (2 * VIRTUAL_W), top + (2 * vy + 1) * h // (2 * VIRTUAL_H)


def guest_to_visible(g, fx, fy):
    if not (0 <= fx < g["frame_w"] and 0 <= fy < g["frame_h"]):
        die(f"guest {fx},{fy} outside the {g['frame_w']}x{g['frame_h']} frame")
    return virtual_to_visible(g, fx * VIRTUAL_W // g["frame_w"], fy * VIRTUAL_H // g["frame_h"])


def home_tile(g):
    """First tile of BuildHomeScene()'s plugin grid (launcher_scene.cpp,
    home_plugin_grid.cpp Bounds() for cell 0,0)."""
    sw, sh = visible_logical(g)
    cols = g["home_columns"]
    icons = cols >= 4
    if sw > sh:  # landscape Home
        gx, gy, gw, gh = 64, 810, 2992, 360
        columns, rows, th = (cols if icons else 4), 1, (250 if icons else 360)
    else:
        gx, gy, gw = 64, 1378, sw - 128
        columns, rows = cols, (cols if icons else 3)
        th = 250 if cols == 4 else 240 if cols == 5 else 318
        gh = 1320 if cols == 5 else 1050
    gap = 40 if columns == 2 else 32
    width = 170 if icons else (gw - gap * (columns - 1)) // columns
    y = ((gh - th) // 2 if rows == 1 else 0) if icons else 0
    return gx + width // 2, gy + y + th // 2


def keyboard_key(g, char):
    """Centre of a key of the desktop keyboard (plugin_desktop.cpp
    BuildKeyboard: full width, 55 % high, bottom; phone_keyboard::Style pads;
    LVGL buttonmatrix update_map())."""
    rows = KEYBOARDS.get(g["kb_layout"]) or die(f"unknown keyboard layout {g['kb_layout']}")
    sw, sh = visible_logical(g)
    kh = sh * 55 // 100
    ky = sh - kh
    pad, prow, pcol = 18, 18, 10
    max_w, max_h = sw - 2 * pad, kh - 2 * pad
    no_gap_h = max_h - prow * (len(rows) - 1)
    for r, row in enumerate(rows):
        units = sum(u for _, u in row)
        no_gap_w = max(0, max_w - pcol * (len(row) - 1))
        before = 0
        for i, (label, u) in enumerate(row):
            if label and label == char:
                x1 = no_gap_w * before // units + i * pcol + pad
                x2 = no_gap_w * (before + u) // units + i * pcol - 1 + pad
                y1 = pad + no_gap_h * r // len(rows) + r * prow
                y2 = pad + no_gap_h * (r + 1) // len(rows) + r * prow - 1
                return (x1 + x2) // 2, ky + (y1 + y2) // 2
            before += u
    die(f"key {char!r} is not on the {g['kb_layout']} lower-case map")


def pick_row(g, index):
    """Row INDEX of the Files selection overlay (home_scene.cpp
    BuildFilesSurface/RenderEntries; row 0 is "Parent folder" unless at /).
    Refuses rows under the picker's Cancel bar (UpdateActionBar)."""
    sw, sh = visible_logical(g)
    landscape = sw > sh
    row_h, pitch = FILE_ROWS.get(g["ui_size"]) or die(f"unknown interface size {g['ui_size']}")
    y = (500 if landscape else 826) + index * pitch + row_h // 2
    bar_top = sh - (g["nav_h"] or (160 if landscape else 226)) - 160
    if y + 24 > bar_top:
        die(f"file row {index} (logical y {y}) is under the Cancel bar at {bar_top}: "
            "too many entries before the fixture; give API2_PICK_TAP from the picker capture")
    return 64 + min((sw - 128) // 3, 600), y


def cmd_tap(g, args):
    kind = args[0] if args else die("tap needs a kind")
    if kind == "view":
        vx, vy = int(args[1]), int(args[2])
        px, py = view_to_panel(g, vx, vy)
        print(px, py, vx, vy)
        return
    if kind == "home":
        x, y = home_tile(g)
    elif kind == "guest":
        x, y = guest_to_visible(g, int(args[1]), int(args[2]))
    elif kind == "toolbar":
        x, y = virtual_to_visible(g, *(TOOLBAR.get(args[1]) or die(f"no toolbar button {args[1]}")))
    elif kind == "key":
        x, y = keyboard_key(g, args[1])
    elif kind == "pick-row":
        x, y = pick_row(g, int(args[1]))
    else:
        die(f"unknown tap kind {kind}")
    px, py = to_panel(g, x, y)
    vx, vy = panel_to_view(g, px, py)
    print(px, py, vx, vy)


def guest_panel_box(g):
    left, top, w, h = desktop(g)
    corners = [to_panel(g, left, top), to_panel(g, left + w - 1, top + h - 1)]
    xs, ys = [c[0] for c in corners], [c[1] for c in corners]
    return min(xs), min(ys), max(xs) + 1, max(ys) + 1


def pil():
    try:
        from PIL import Image, ImageChops, ImageDraw
    except ImportError:
        die("python3 PIL (pillow) is required for images")
    return Image, ImageChops, ImageDraw


def upright(g, image):
    Image, _, _ = pil()
    r = g["rotation"]
    if r == 90:
        return image.transpose(Image.Transpose.ROTATE_270)
    if r == 270:
        return image.transpose(Image.Transpose.ROTATE_90)
    return image


def cmd_view(g, args):
    Image, _, ImageDraw = pil()
    src, dst = args[0], args[1]
    image = upright(g, Image.open(src).convert("RGB"))
    draw = ImageDraw.Draw(image)
    left, top, w, h = desktop(g)
    a = panel_to_view(g, *to_panel(g, left, top))
    b = panel_to_view(g, *to_panel(g, left + w - 1, top + h - 1))
    draw.rectangle([min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1])],
                   outline=(0, 160, 255))
    for item in args[2:]:
        vx, vy = (int(v) for v in item.split(","))
        draw.line([vx - 14, vy, vx + 14, vy], fill=(255, 0, 0), width=3)
        draw.line([vx, vy - 14, vx, vy + 14], fill=(255, 0, 0), width=3)
    image.save(dst)


def cmd_differ(g, args):
    Image, ImageChops, _ = pil()
    box = guest_panel_box(g)
    a = Image.open(args[0]).convert("RGB").crop(box)
    b = Image.open(args[1]).convert("RGB").crop(box)
    if a.size != b.size:
        die("captures differ in size")
    diff = ImageChops.difference(a, b)
    changed = sum(1 for p in diff.getdata() if p != (0, 0, 0))
    print(f"{changed} of {a.width * a.height} guest pixels changed (panel box {box})")
    sys.exit(0 if changed else 1)


def cmd_detect(g, args):
    Image, _, _ = pil()
    image = upright(g, Image.open(args[0]).convert("L"))
    w, h = image.size
    px = image.load()
    cols = [x for x in range(w) if sum(px[x, y] > 100 for y in range(0, h, 2)) * 2 > h / 2]
    rows = [y for y in range(h) if sum(px[x, y] > 100 for x in range(0, w, 2)) * 2 > w / 2]
    left, top, dw, dh = desktop(g)
    a = panel_to_view(g, *to_panel(g, left, top))
    b = panel_to_view(g, *to_panel(g, left + dw - 1, top + dh - 1))
    computed = (min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1]))
    found = (cols[0], rows[0], cols[-1], rows[-1]) if cols and rows else None
    print(f"computed guest rect (view) {computed}; bright region {found}")


def main():
    if len(sys.argv) < 3:
        die(__doc__)
    cmd, path, args = sys.argv[1], sys.argv[2], sys.argv[3:]
    if cmd == "init":
        pw, ph = png_size(args[0])
        if args[1:] and args[1]:
            lw, lh = (int(v) for v in args[1].lower().split("x"))
        else:
            # DisplayTransform::Adaptive: 1440-wide design canvas, height in
            # the same scale (BoardConfig: AERA_SCREEN_H 2022 per 1080 = 2696).
            lw, lh = 1440, round(ph * 1440 / pw)
        save(path, {"pw": pw, "ph": ph, "lw": lw, "lh": lh, "rotation": 0,
                    "frame_w": 960, "frame_h": 540, "ui_size": "normal", "nav_h": 0,
                    "kb_layout": "qwerty", "home_columns": 3})
        return
    g = load(path)
    if cmd == "set":
        for item in args:
            key, value = item.split("=", 1)
            g[key] = int(value) if value.lstrip("-").isdigit() else value
        save(path, g)
    elif cmd == "tap":
        cmd_tap(g, args)
    elif cmd == "desktop":
        left, top, w, h = desktop(g)
        print(f"visible logical {left},{top} {w}x{h}; panel box {guest_panel_box(g)}")
    elif cmd == "view":
        cmd_view(g, args)
    elif cmd == "differ":
        cmd_differ(g, args)
    elif cmd == "detect":
        cmd_detect(g, args)
    else:
        die(f"unknown command {cmd}")


if __name__ == "__main__":
    main()
