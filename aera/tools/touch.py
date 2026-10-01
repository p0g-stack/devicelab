#!/usr/bin/env python3
"""Raw evdev bytes for one tap on a multitouch screen (protocol B), x86_64
`struct input_event` layout. Writing them to /dev/input/eventN as root
injects the tap without needing sendevent on the device.

    touch.py X Y DIR   ->  DIR/down.ev  DIR/up.ev   (touch-panel units)
"""
import struct, sys
from pathlib import Path

EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
BTN_TOUCH, ABS_X, ABS_Y = 0x14a, 0, 1
SLOT, TRACK, MT_X, MT_Y = 0x2f, 0x39, 0x35, 0x36

def ev(t, c, v): return struct.pack("<qqHHi", 0, 0, t, c, v)

x, y, out = int(sys.argv[1]), int(sys.argv[2]), Path(sys.argv[3])
out.mkdir(parents=True, exist_ok=True)
(out / "down.ev").write_bytes(ev(EV_ABS, SLOT, 0) + ev(EV_ABS, TRACK, 7) + ev(EV_ABS, MT_X, x) +
    ev(EV_ABS, MT_Y, y) + ev(EV_KEY, BTN_TOUCH, 1) + ev(EV_ABS, ABS_X, x) + ev(EV_ABS, ABS_Y, y) + ev(EV_SYN, 0, 0))
(out / "up.ev").write_bytes(ev(EV_ABS, SLOT, 0) + ev(EV_ABS, TRACK, -1) + ev(EV_KEY, BTN_TOUCH, 0) + ev(EV_SYN, 0, 0))
