#!/usr/bin/env python3
import os
import select
import spidev
import threading
import time
from evdev import UInput, AbsInfo, ecodes as e

TOUCH_GPIO = 74
BEEPER_GPIO = 70
BEEP_MS = 25
FLAG_FILE = os.environ.get("TS35_BEEPER_FLAG", "/home/biqu/beeper_enabled")
FLAG_CHECK_INTERVAL = 1.0
PRESS_TH = 60
BEEPER_ENABLED_BUILD = os.environ.get("TS35_BEEPER_HARDWARE", "1") != "0"

# --- Touch axis calibration -------------------------------------------------
# The raw X/Y channel assignment and direction can differ slightly between
# physical MKS TS35 units even with identical wiring, because it depends on
# how the resistive touch layer itself is oriented internally. If touch is
# rotated or mirrored on your unit, do NOT edit the mapping logic below;
# just flip these three booleans and restart the service. See README.md
# "Touch calibration" for the 4-corner test procedure to determine the
# correct combination for your unit.
SWAP_XY = False   # swap the two raw ADC channels before anything else
INVERT_X = True   # mirror the final X axis (0 <-> 4095)
INVERT_Y = False  # mirror the final Y axis (0 <-> 4095)

# --- Touch range rescale -----------------------------------------------------
# The raw ADC range of the resistive panel is narrower than the theoretical
# 0-4095 span. If touch is accurate in the center but off by a few mm near
# the edges, adjust these to match your panel (see README.md).
X_RAW_MIN = 200
X_RAW_MAX = 3900
Y_RAW_MIN = 200
Y_RAW_MAX = 3900


def rescale(value, raw_min, raw_max):
    value = max(raw_min, min(raw_max, value))
    return int((value - raw_min) * 4095 / (raw_max - raw_min))


def map_axes(x_raw, y_raw):
    if SWAP_XY:
        x_raw, y_raw = y_raw, x_raw
    x = rescale(x_raw, X_RAW_MIN, X_RAW_MAX)
    y = rescale(y_raw, Y_RAW_MIN, Y_RAW_MAX)
    if INVERT_X:
        x = 4095 - x
    if INVERT_Y:
        y = 4095 - y
    return x, y


def export_gpio(number):
    path = f"/sys/class/gpio/gpio{number}"
    if not os.path.exists(path):
        with open("/sys/class/gpio/export", "w") as f:
            f.write(str(number))
        time.sleep(0.1)
    return path


def touch_gpio_setup():
    path = export_gpio(TOUCH_GPIO)
    with open(f"{path}/direction", "w") as f:
        f.write("in")
    with open(f"{path}/edge", "w") as f:
        f.write("both")
    return path


def beeper_gpio_setup():
    path = export_gpio(BEEPER_GPIO)
    with open(f"{path}/direction", "w") as f:
        f.write("out")
    with open(f"{path}/value", "w") as f:
        f.write("0")
    return path


touch_path = touch_gpio_setup()
touch_value_fd = os.open(f"{touch_path}/value", os.O_RDONLY)
os.read(touch_value_fd, 8)

poller = select.poll()
poller.register(touch_value_fd, select.POLLPRI | select.POLLERR)

beeper_value_fd = None
if BEEPER_ENABLED_BUILD:
    try:
        beeper_path = beeper_gpio_setup()
        beeper_value_fd = os.open(f"{beeper_path}/value", os.O_WRONLY)
    except OSError as exc:
        print(f"Beeper GPIO unavailable, continuing without beep feedback: {exc}")
        beeper_value_fd = None


def gpio_is_low():
    os.lseek(touch_value_fd, 0, os.SEEK_SET)
    return os.read(touch_value_fd, 8).strip() == b"0"


def _beep_off():
    try:
        os.write(beeper_value_fd, b"0")
    except OSError:
        pass


beeper_enabled = [True]


def beep():
    if beeper_value_fd is None or not beeper_enabled[0]:
        return
    try:
        os.write(beeper_value_fd, b"1")
        threading.Timer(BEEP_MS / 1000.0, _beep_off).start()
    except OSError:
        pass


def read_flag_loop():
    while True:
        try:
            with open(FLAG_FILE) as f:
                beeper_enabled[0] = f.read().strip() != "0"
        except FileNotFoundError:
            beeper_enabled[0] = True
        except Exception:
            pass
        time.sleep(FLAG_CHECK_INTERVAL)


if beeper_value_fd is not None:
    threading.Thread(target=read_flag_loop, daemon=True).start()

spi = spidev.SpiDev()
spi.open(0, 2)
spi.max_speed_hz = 2000000
spi.mode = 0


def read(cmd):
    r = spi.xfer2([cmd, 0x00, 0x00])
    return ((r[1] << 8) | r[2]) >> 3


capabilities = {
    e.EV_KEY: [e.BTN_TOUCH],
    e.EV_ABS: [
        (e.ABS_X, AbsInfo(value=0, min=0, max=4095, fuzz=0, flat=0, resolution=0)),
        (e.ABS_Y, AbsInfo(value=0, min=0, max=4095, fuzz=0, flat=0, resolution=0)),
        (e.ABS_PRESSURE, AbsInfo(value=0, min=0, max=1024, fuzz=0, flat=0, resolution=0)),
    ],
}

ui = UInput(capabilities, name="ADS7846 Touchscreen", version=0x1)
touched = False

print("Novin3dp TS35 virtual touchscreen (HelixScreen build) running.")

try:
    while True:
        if not touched:
            poller.poll()
            if not gpio_is_low():
                continue
            time.sleep(0.005)
            z1 = read(0xB0)
            if z1 > PRESS_TH:
                x_raw = read(0x90)
                y_raw = read(0xD0)
                out_x, out_y = map_axes(x_raw, y_raw)
                ui.write(e.EV_KEY, e.BTN_TOUCH, 1)
                ui.write(e.EV_ABS, e.ABS_X, out_x)
                ui.write(e.EV_ABS, e.ABS_Y, out_y)
                ui.write(e.EV_ABS, e.ABS_PRESSURE, 500)
                ui.syn()
                touched = True
                beep()
        else:
            x_raw = read(0x90)
            y_raw = read(0xD0)
            z1 = read(0xB0)
            if z1 > PRESS_TH and x_raw < 4090:
                out_x, out_y = map_axes(x_raw, y_raw)
                ui.write(e.EV_ABS, e.ABS_X, out_x)
                ui.write(e.EV_ABS, e.ABS_Y, out_y)
                ui.write(e.EV_ABS, e.ABS_PRESSURE, 500)
                ui.syn()
            else:
                ui.write(e.EV_KEY, e.BTN_TOUCH, 0)
                ui.write(e.EV_ABS, e.ABS_PRESSURE, 0)
                ui.syn()
                touched = False
            time.sleep(0.0333)
except KeyboardInterrupt:
    pass
finally:
    ui.close()
    spi.close()
    os.close(touch_value_fd)
    if beeper_value_fd is not None:
        os.close(beeper_value_fd)
