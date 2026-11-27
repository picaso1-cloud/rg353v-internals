#!/usr/bin/env python3
"""rg353v-touch-mouse - the Hynitron cst3xx panel as a pointer.

Why a bridge at all
-------------------
The panel is a *touch* device (ABS_MT_* plus BTN_TOUCH, axes 0..639 x 0..479).
libinput and sway expose it as touch only, so the seat ends up with no pointer:
the launcher cannot be tapped and the emulators that take a mouse (Draxcast for
the DS, melonDS through RetroArch's touchscreen driver) never see the finger.

Why a *relative* pointer
------------------------
The vendor 5.10 kernel ignores the absmin/absmax arrays of
`struct uinput_user_dev` (UI_DEV_SETUP with the id-first layout that this
kernel uses): a virtual absolute device comes out with a zero range and
libinput then ignores it. A relative pointer needs no range at all - libinput
accepts it as a normal mouse - and the bridge turns the panel's absolute
position into motion, so the cursor follows the finger and a tap is a click.

The panel itself is left alone: its touch events, the touch keyboard and
anything that reads the touch device directly keep working.
"""

import ctypes
import fcntl
import os
import struct
import sys
import time

UINPUT = "/dev/uinput"
EV_SYN, EV_KEY, EV_REL, EV_ABS = 0, 1, 2, 3
REL_X, REL_Y = 0, 1
BTN_LEFT = 0x110
BTN_TOUCH = 0x14A
INPUT_PROP_POINTER = 0x01

UI_SET_EVBIT = 0x40045564
UI_SET_KEYBIT = 0x40045565
UI_SET_RELBIT = 0x40045566
UI_SET_PROPBIT = 0x4004556E      # _IOW('U', 110, int)
UI_DEV_SETUP = 0x405C5503        # _IOW('U', 3, struct uinput_user_dev) = 1116
UI_DEV_CREATE = 0x5501
EVIOCGABS = 0x80244540


class InputId(ctypes.Structure):
    _fields_ = [
        ("bustype", ctypes.c_uint16),
        ("vendor", ctypes.c_uint16),
        ("product", ctypes.c_uint16),
        ("version", ctypes.c_uint16),
    ]


class UInputUserDev(ctypes.Structure):
    # This vendor kernel keeps struct input_id *before* the name: with the
    # upstream (name first) order the kernel copies the name from offset 8
    # and the device ends up called "ouch Panel".
    _fields_ = [
        ("id", InputId),
        ("name", ctypes.c_char * 80),
        ("ff_effects_max", ctypes.c_uint32),
        ("absmax", ctypes.c_int32 * 64),
        ("absmin", ctypes.c_int32 * 64),
        ("absfuzz", ctypes.c_int32 * 64),
        ("absflat", ctypes.c_int32 * 64),
    ]


class InputEvent(ctypes.Structure):
    _fields_ = [
        ("time_sec", ctypes.c_long),
        ("time_usec", ctypes.c_long),
        ("type", ctypes.c_uint16),
        ("code", ctypes.c_uint16),
        ("value", ctypes.c_int32),
    ]


def find_touch_node():
    """The event node of the cst3xx panel, found by name in /proc."""
    try:
        with open("/proc/bus/input/devices") as f:
            blocks = f.read().split("\n\n")
    except OSError:
        return None
    for block in blocks:
        low = block.lower()
        if "cst3xx" not in low and "hynitron" not in low:
            continue
        for line in block.splitlines():
            if line.startswith("H: Handlers="):
                for handler in line.split("=", 1)[1].split():
                    if handler.startswith("event"):
                        return "/dev/input/" + handler
    return None


def create_pointer():
    fd = os.open(UINPUT, os.O_WRONLY | os.O_NONBLOCK)
    # The UI_SET_*BIT ioctls take the bit value as the argument itself, not
    # a pointer to it: a pointer is taken for a huge bit number (EINVAL).
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_SYN)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_REL)
    fcntl.ioctl(fd, UI_SET_KEYBIT, BTN_LEFT)
    fcntl.ioctl(fd, UI_SET_RELBIT, REL_X)
    fcntl.ioctl(fd, UI_SET_RELBIT, REL_Y)
    fcntl.ioctl(fd, UI_SET_PROPBIT, INPUT_PROP_POINTER)

    dev = UInputUserDev()
    dev.name = b"RG353V Touch Panel"
    dev.id.bustype = 0x03
    dev.id.vendor = 0x0001
    dev.id.product = 0x0001
    dev.id.version = 0x0001
    fcntl.ioctl(fd, UI_DEV_SETUP, dev, True)
    fcntl.ioctl(fd, UI_DEV_CREATE)
    return fd


def emit(fd, ev_type, code, value):
    ev = InputEvent(0, 0, ev_type, code, value)
    os.write(fd, bytes(ev))


def main():
    node = find_touch_node()
    if not node:
        print("rg353v-touch-mouse: the cst3xx panel is not there", file=sys.stderr)
        return 1
    print(f"rg353v-touch-mouse: reading {node}", flush=True)

    ud = create_pointer()
    src = os.open(node, os.O_RDONLY | os.O_NONBLOCK)
    print("rg353v-touch-mouse: relative pointer created", flush=True)

    size = ctypes.sizeof(InputEvent)
    x = y = None
    pressed = 0
    while True:
        try:
            data = os.read(src, size * 64)
        except BlockingIOError:
            time.sleep(0.01)
            continue
        except OSError:
            time.sleep(0.5)
            continue
        if not data:
            time.sleep(0.1)
            continue
        for off in range(0, len(data) - size + 1, size):
            ev = InputEvent.from_buffer_copy(data[off:off + size])
            if ev.type == EV_ABS and ev.code == 0:          # ABS_X
                if x is not None and ev.value != x:
                    emit(ud, EV_REL, REL_X, ev.value - x)
                    emit(ud, EV_SYN, 0, 0)
                x = ev.value
            elif ev.type == EV_ABS and ev.code == 1:        # ABS_Y
                if y is not None and ev.value != y:
                    emit(ud, EV_REL, REL_Y, ev.value - y)
                    emit(ud, EV_SYN, 0, 0)
                y = ev.value
            elif ev.type == EV_KEY and ev.code == BTN_TOUCH:  # finger down/up
                pressed = 1 if ev.value else 0
                emit(ud, EV_KEY, BTN_LEFT, pressed)
                emit(ud, EV_SYN, 0, 0)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
