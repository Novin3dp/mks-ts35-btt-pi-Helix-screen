# Deployment notes

## Display

MKS TS35 V2 uses ST7796S with framebuffer `fb_st7796s`. The final tested configuration uses SPI1 CS1 for LCD and SPI1 CS2 for XPT2046 touch.

- LCD: 48 MHz
- Touch: 2 MHz
- LCD reset: PC12
- LCD DC: PC14
- Touch IRQ: PC10
- Touch CS: PC13

## Touch architecture

The project uses `linux,spidev` instead of the kernel `ads7846` driver. `virtual_touch.py` reads XPT2046 directly and exposes a standard `uinput` device named `ADS7846 Touchscreen`.

The driver waits for the touch IRQ while idle and reports coordinates at about 30 Hz while pressed.

## Beeper

GPIO70 / PC6 drives the optional active 5V beeper through a transistor. Klipper emits `BEEPER_TOGGLE_EVENT`; `beeper_watcher.py` watches Moonraker's gcode store and toggles the `beeper_enabled` flag consumed by `virtual_touch.py`.

## Validation

```bash
ls -l /dev/fb0 /dev/spidev0.2
dmesg | grep -i spi
systemctl status helixscreen --no-pager
systemctl status virtual-touch.service --no-pager
systemctl status beeper-watcher.service --no-pager
```
