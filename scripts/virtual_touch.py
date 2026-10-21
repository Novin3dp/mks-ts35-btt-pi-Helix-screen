#!/usr/bin/env python3
import ctypes
import fcntl
import os
import select
import struct
import threading
import time

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


# --- Minimal SPI / uinput access (Python standard library only) -------------
# Replaces python3-spidev and python3-evdev so the driver runs on a stock
# MainsailOS/Armbian image without installing extra packages.
def _iow(kind, nr, size):
    return (1 << 30) | (size << 16) | (ord(kind) << 8) | nr


def _io(kind, nr):
    return (ord(kind) << 8) | nr


SPI_IOC_WR_MODE = _iow("k", 1, 1)
SPI_IOC_WR_MAX_SPEED_HZ = _iow("k", 4, 4)
SPI_TRANSFER_FMT = "QQIIHBBBBBB"  # struct spi_ioc_transfer (32 bytes)
SPI_IOC_MESSAGE_1 = _iow("k", 0, struct.calcsize(SPI_TRANSFER_FMT))


class SpiDev:
    def __init__(self, bus, device, speed_hz, mode=0):
        self.fd = os.open(f"/dev/spidev{bus}.{device}", os.O_RDWR)
        self.speed_hz = speed_hz
        fcntl.ioctl(self.fd, SPI_IOC_WR_MODE, struct.pack("B", mode))
        fcntl.ioctl(self.fd, SPI_IOC_WR_MAX_SPEED_HZ, struct.pack("I", speed_hz))

    def xfer2(self, data):
        n = len(data)
        tx = ctypes.create_string_buffer(bytes(data), n)
        rx = ctypes.create_string_buffer(n)
        msg = struct.pack(SPI_TRANSFER_FMT, ctypes.addressof(tx), ctypes.addressof(rx),
                          n, self.speed_hz, 0, 8, 0, 0, 0, 0, 0)
        fcntl.ioctl(self.fd, SPI_IOC_MESSAGE_1, msg)
        return list(rx.raw)

    def close(self):
        os.close(self.fd)


EV_SYN, EV_KEY, EV_ABS = 0x00, 0x01, 0x03
SYN_REPORT = 0
BTN_TOUCH = 0x14A
ABS_X, ABS_Y, ABS_PRESSURE = 0x00, 0x01, 0x18
ABS_CNT = 64
UI_SET_EVBIT = _iow("U", 100, 4)
UI_SET_KEYBIT = _iow("U", 101, 4)
UI_SET_ABSBIT = _iow("U", 103, 4)
UI_DEV_CREATE = _io("U", 1)
UI_DEV_DESTROY = _io("U", 2)
BUS_USB = 0x03


class UInput:
    def __init__(self, name, abs_ranges, keys):
        self.fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_KEY)
        for key in keys:
            fcntl.ioctl(self.fd, UI_SET_KEYBIT, key)
        fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_ABS)
        absmax = [0] * ABS_CNT
        absmin = [0] * ABS_CNT
        for code, (lo, hi) in abs_ranges.items():
            fcntl.ioctl(self.fd, UI_SET_ABSBIT, code)
            absmin[code], absmax[code] = lo, hi
        # struct uinput_user_dev
        dev = struct.pack("80sHHHHi", name.encode()[:79], BUS_USB, 1, 1, 1, 0)
        dev += struct.pack(f"{ABS_CNT}i", *absmax) + struct.pack(f"{ABS_CNT}i", *absmin)
        dev += struct.pack(f"{ABS_CNT * 2}i", *([0] * ABS_CNT * 2))  # fuzz, flat
        os.write(self.fd, dev)
        fcntl.ioctl(self.fd, UI_DEV_CREATE)

    def write(self, etype, code, value):
        now = time.time()
        sec = int(now)
        os.write(self.fd, struct.pack("llHHi", sec, int((now - sec) * 1e6), etype, code, value))

    def syn(self):
        self.write(EV_SYN, SYN_REPORT, 0)

    def close(self):
        try:
            fcntl.ioctl(self.fd, UI_DEV_DESTROY)
        finally:
            os.close(self.fd)


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

spi = SpiDev(0, 2, 2000000, mode=0)


def read(cmd):
    r = spi.xfer2([cmd, 0x00, 0x00])
    return ((r[1] << 8) | r[2]) >> 3


ui = UInput(
    "ADS7846 Touchscreen",
    {ABS_X: (0, 4095), ABS_Y: (0, 4095), ABS_PRESSURE: (0, 1024)},
    [BTN_TOUCH],
)
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
                ui.write(EV_KEY, BTN_TOUCH, 1)
                ui.write(EV_ABS, ABS_X, out_x)
                ui.write(EV_ABS, ABS_Y, out_y)
                ui.write(EV_ABS, ABS_PRESSURE, 500)
                ui.syn()
                touched = True
                beep()
        else:
            x_raw = read(0x90)
            y_raw = read(0xD0)
            z1 = read(0xB0)
            if z1 > PRESS_TH and x_raw < 4090:
                out_x, out_y = map_axes(x_raw, y_raw)
                ui.write(EV_ABS, ABS_X, out_x)
                ui.write(EV_ABS, ABS_Y, out_y)
                ui.write(EV_ABS, ABS_PRESSURE, 500)
                ui.syn()
            else:
                ui.write(EV_KEY, BTN_TOUCH, 0)
                ui.write(EV_ABS, ABS_PRESSURE, 0)
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
